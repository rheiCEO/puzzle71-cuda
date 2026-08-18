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
    try:
        start_i = hex_int(start_h)
        end_i = hex_int(end_h)
        slice_keys = end_i - start_i + 1
        if base_h:
            pos = max(0, hex_int(base_h) - start_i)
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
        "slice_keys": slice_keys,
        "slice_done_pct": round(slice_done_pct, 4),
        "speed": speed,
        "age_sec": int(max(0, time.time() - progress.stat().st_mtime)),
        "progress_file": str(progress),
        "log_file": str(log_path),
    }


def collect(logs_dir: Path) -> dict:
    files = sorted(logs_dir.glob("gpu*.progress"))
    gpus = [g for p in files if (g := gpu_entry(p)) is not None]

    total_keys = sum(g["total_keys"] for g in gpus)
    speed_sum = sum(g["speed"] for g in gpus if g.get("speed"))

    puzzle_space = 1 << 70
    puzzle_pct = min(100.0, total_keys / puzzle_space * 100) if puzzle_space else 0.0

    ages = [g["age_sec"] for g in gpus]
    return {
        "ok": bool(gpus),
        "gpu_count": len(gpus),
        "total_keys": total_keys,
        "speed_sum": speed_sum or None,
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
