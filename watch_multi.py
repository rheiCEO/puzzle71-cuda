#!/usr/bin/env python3
"""Dashboard HTML — suma postępu z logs/gpu*.progress (multi-GPU / vast)."""
from __future__ import annotations

import argparse
import io
import json
import re
import time
import webbrowser
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "dashboard_multi.html"
DEFAULT_LOGS = ROOT / "logs"
PORT = 8768
PUZZLE_START = 1 << 70
PUZZLE_END = (1 << 71) - 1

SPEED_RE = re.compile(r"~(\d+)\s*M/s")


def parse_kv_file(path: Path) -> dict:
    data: dict = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        data[k.strip()] = v.strip()
    return data


def hex_int(h: str) -> int:
    return int(h.strip(), 16)


def parse_log_speed(path: Path) -> int | None:
    if not path.exists():
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    matches = SPEED_RE.findall(text)
    if not matches:
        return None
    return int(matches[-1]) * 1_000_000


def gpu_entry(progress: Path) -> dict | None:
    if not progress.exists():
        return None
    raw = parse_kv_file(progress)
    name = progress.stem
    try:
        total_keys = int(raw.get("total_keys", "0"))
    except ValueError:
        total_keys = 0

    start_h = raw.get("start", "")
    end_h = raw.get("end", "")
    base_h = raw.get("base_key", "")

    slice_keys = 0
    slice_done_pct = 0.0
    start_i = None
    end_i = None
    base_i = None
    try:
        start_i = hex_int(start_h)
        end_i = hex_int(end_h)
        base_i = hex_int(base_h) if base_h else None
        slice_keys = end_i - start_i + 1
        if base_i is not None:
            pos = max(0, base_i - start_i)
            slice_done_pct = min(100.0, pos / slice_keys * 100) if slice_keys else 0.0
        elif slice_keys:
            slice_done_pct = min(100.0, total_keys / slice_keys * 100)
    except ValueError:
        pass

    log_path = progress.with_suffix(".log")
    speed = parse_log_speed(log_path)

    return {
        "id": name,
        "gpu": name.replace("gpu", "GPU ", 1) if name.startswith("gpu") else name,
        "ok": True,
        "total_keys": total_keys,
        "mode": raw.get("mode", "—"),
        "start": start_h,
        "end": end_h,
        "base_key": base_h,
        "start_i": start_i,
        "end_i": end_i,
        "base_i": base_i,
        "slice_keys": slice_keys,
        "slice_done_pct": round(slice_done_pct, 4),
        "speed": speed,
        "age_sec": int(max(0, time.time() - progress.stat().st_mtime)),
        "progress_file": str(progress),
        "log_file": str(log_path),
    }


def merge_intervals(intervals: list[tuple[int, int]]) -> list[tuple[int, int]]:
    if not intervals:
        return []
    intervals.sort()
    merged: list[tuple[int, int]] = [intervals[0]]
    for s, e in intervals[1:]:
        ps, pe = merged[-1]
        if s <= pe + 1:
            merged[-1] = (ps, max(pe, e))
        else:
            merged.append((s, e))
    return merged


def build_coverage(gpus: list[dict]) -> tuple[int, list[tuple[int, int]], int, int]:
    # Pokrycie unikalne: suma przedzialow [start, base_key) z plikow progress.
    raw: list[tuple[int, int]] = []
    for g in gpus:
        s = g.get("start_i")
        e = g.get("end_i")
        b = g.get("base_i")
        if s is None or e is None:
            continue
        if b is None:
            b = s + int(g.get("total_keys", 0))
        if b <= s:
            continue
        scan_end = min(e + 1, b) - 1
        if scan_end < s:
            continue
        rs = max(PUZZLE_START, s)
        re = min(PUZZLE_END, scan_end)
        if rs <= re:
            raw.append((rs, re))

    merged = merge_intervals(raw)
    covered = sum((e - s + 1) for s, e in merged)

    # Zakres "focus" dla mapy: aktualnie skanowany obszar (min start .. max end).
    starts = [g.get("start_i") for g in gpus if g.get("start_i") is not None]
    ends = [g.get("end_i") for g in gpus if g.get("end_i") is not None]
    if starts and ends:
        focus_start = max(PUZZLE_START, min(starts))
        focus_end = min(PUZZLE_END, max(ends))
        if focus_start <= focus_end:
            return covered, merged, focus_start, focus_end
    return covered, merged, PUZZLE_START, PUZZLE_END


def covered_in_range(segments: list[tuple[int, int]], rs: int, re: int) -> int:
    total = 0
    for s, e in segments:
        a = max(s, rs)
        b = min(e, re)
        if a <= b:
            total += b - a + 1
    return total


def clip_segments(segments: list[tuple[int, int]], rs: int, re: int) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for s, e in segments:
        a = max(s, rs)
        b = min(e, re)
        if a <= b:
            out.append((a, b))
    return merge_intervals(out)


def collect(logs_dir: Path) -> dict:
    files = sorted(logs_dir.glob("gpu*.progress"))
    gpus = [g for p in files if (g := gpu_entry(p)) is not None]

    total_keys = sum(g["total_keys"] for g in gpus)
    speed_sum = sum(g["speed"] for g in gpus if g.get("speed"))

    puzzle_space = 1 << 70
    puzzle_pct = min(100.0, total_keys / puzzle_space * 100) if puzzle_space else 0.0
    covered_keys, coverage_segments, cov_start, cov_end = build_coverage(gpus)
    focus_space = cov_end - cov_start + 1
    covered_focus = covered_in_range(coverage_segments, cov_start, cov_end)
    remaining_focus = max(0, focus_space - covered_focus)
    covered_pct_focus = min(100.0, covered_focus / focus_space * 100) if focus_space else 0.0
    map_segments = clip_segments(coverage_segments, cov_start, cov_end)

    ages = [g["age_sec"] for g in gpus]
    return {
        "ok": bool(gpus),
        "gpu_count": len(gpus),
        "total_keys": total_keys,
        "speed_sum": speed_sum or None,
        "covered_keys": covered_focus,
        "covered_pct": covered_pct_focus,
        "remaining_keys": remaining_focus,
        "focus_space": focus_space,
        "coverage_segments": [{"start": f"{s:x}", "end": f"{e:x}"} for s, e in map_segments],
        "coverage_start_hex": f"{cov_start:x}",
        "coverage_end_hex": f"{cov_end:x}",
        "puzzle_pct": puzzle_pct,
        "puzzle_space": puzzle_space,
        "newest_sec": min(ages) if ages else None,
        "oldest_sec": max(ages) if ages else None,
        "gpus": gpus,
        "logs_dir": str(logs_dir),
    }


SAFE_FILE = re.compile(r"^(gpu\d+\.(?:progress|log)|FOUND\.txt|puzzle71\.progress)$")


def safe_log_file(logs_dir: Path, name: str) -> Path | None:
    name = Path(unquote(name)).name
    if not SAFE_FILE.match(name):
        return None
    path = (logs_dir / name).resolve()
    if path.parent != logs_dir.resolve():
        return None
    return path if path.is_file() else None


def zip_progress(logs_dir: Path) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in sorted(logs_dir.glob("gpu*.progress")):
            zf.write(p, p.name)
        found = logs_dir / "FOUND.txt"
        if found.is_file():
            zf.write(found, found.name)
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    logs_dir = DEFAULT_LOGS

    def log_message(self, *args):
        return

    def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/dashboard_multi.html"):
            self._send(200, HTML.read_bytes(), "text/html; charset=utf-8")
        elif path == "/api":
            self._send(200, json.dumps(collect(self.logs_dir)).encode("utf-8"), "application/json")
        elif path in ("/download/progress.zip", "/progress.zip"):
            data = zip_progress(self.logs_dir)
            self._send(
                200,
                data,
                "application/zip",
                {"Content-Disposition": "attachment; filename=\"puzzle71-progress.zip\""},
            )
        elif path.startswith("/file/"):
            target = safe_log_file(self.logs_dir, path[6:])
            if target is None:
                self._send(404, b"not found", "text/plain")
                return
            self._send(
                200,
                target.read_bytes(),
                "application/octet-stream",
                {"Content-Disposition": f'attachment; filename="{target.name}"'},
            )
        else:
            self._send(404, b"not found", "text/plain")


def main() -> None:
    ap = argparse.ArgumentParser(description="Multi-GPU dashboard puzzle71-cuda")
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--bind", default="127.0.0.1", help="0.0.0.0 na vast / tunel")
    ap.add_argument("--logs", type=Path, default=DEFAULT_LOGS, help="katalog z gpu*.progress")
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()

    if not HTML.exists():
        raise SystemExit("Brak dashboard_multi.html")
    args.logs.mkdir(parents=True, exist_ok=True)

    Handler.logs_dir = args.logs.resolve()
    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    url = f"http://{'127.0.0.1' if args.bind == '0.0.0.0' else args.bind}:{args.port}/"
    print(f"Dashboard multi-GPU: {url}")
    print(f"Logi:              {Handler.logs_dir}/gpu*.progress")
    print(f"Pobierz ZIP:       {url}download/progress.zip")
    print("Odswiezanie co 1 s w przegladarce.")
    if args.bind == "0.0.0.0":
        print("Na vast Instance Portal: Create new tunnel -> http://localhost:%s" % args.port)
    if not args.no_browser and args.bind != "0.0.0.0":
        try:
            webbrowser.open(url)
        except Exception:
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStop.")


if __name__ == "__main__":
    main()
