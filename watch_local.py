#!/usr/bin/env python3
"""Lokalny dashboard + sterowanie 1× GPU — wybór kawałka, losowo, start/stop."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from watch_multi import DEFAULT_LOGS, PUZZLE_END, PUZZLE_START, gpu_entry, parse_kv_file, parse_log_speed

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "dashboard_local.html"
PORT = 8769
PUZZLE_SPACE = 1 << 70
ACTIVE_CKPT = ROOT / "puzzle71.progress"
RUN_LOG = ROOT / "run.log"

_proc: subprocess.Popen | None = None
_proc_meta: dict = {}


def find_bin() -> Path:
    for p in (
        ROOT / "bin" / "puzzle71-cuda.exe",
        ROOT / "dist" / "puzzle71-cuda-win64" / "bin" / "puzzle71-cuda.exe",
    ):
        if p.is_file():
            return p
    return ROOT / "bin" / "puzzle71-cuda.exe"


def pct_to_int(pct: float) -> int:
    pct = max(0.0, min(100.0, float(pct)))
    if pct >= 100.0:
        return PUZZLE_END
    return PUZZLE_START + int(PUZZLE_SPACE * pct / 100.0)


def int_to_pct(val: int) -> float:
    if val <= PUZZLE_START:
        return 0.0
    if val >= PUZZLE_END:
        return 100.0
    return (val - PUZZLE_START) / PUZZLE_SPACE * 100.0


def trim_hex(h: str) -> str:
    h = (h or "").strip().lower().lstrip("0x")
    return h.lstrip("0") or "0"


def norm_hex(h: str) -> str:
    h = trim_hex(h)
    return h if h else f"{PUZZLE_START:x}"


def parse_progress(path: Path) -> dict:
    if not path.is_file():
        return {"ok": False, "path": str(path)}
    data = parse_kv_file(path)
    data["ok"] = True
    data["path"] = str(path)
    try:
        data["total_keys"] = int(data.get("total_keys", "0"))
    except ValueError:
        data["total_keys"] = 0
    data["age_sec"] = int(max(0, time.time() - path.stat().st_mtime))
    speed = parse_log_speed(path.with_suffix(".log"))
    if speed is None and path == ACTIVE_CKPT:
        speed = parse_log_speed(RUN_LOG)
    data["speed"] = speed
    return data


def list_checkpoints(logs_dir: Path) -> list[dict]:
    out: list[dict] = []
    for p in sorted(logs_dir.glob("gpu*.progress")):
        g = gpu_entry(p)
        if g is None:
            continue
        g["pct_start"] = round(int_to_pct(g["start_i"]), 4) if g.get("start_i") is not None else 0.0
        g["pct_end"] = round(int_to_pct(g["end_i"]), 4) if g.get("end_i") is not None else 100.0
        g["start_short"] = trim_hex(g.get("start", ""))
        g["end_short"] = trim_hex(g.get("end", ""))
        out.append(g)
    return out


def proc_running() -> bool:
    global _proc
    if _proc is None:
        return False
    code = _proc.poll()
    if code is not None:
        _proc = None
        return False
    return True


def stop_search() -> dict:
    global _proc, _proc_meta
    if not proc_running():
        _proc_meta = {}
        return {"ok": True, "stopped": False, "msg": "nic nie dziala"}
    assert _proc is not None
    _proc.terminate()
    try:
        _proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        _proc.kill()
        _proc.wait(timeout=3)
    _proc = None
    meta = dict(_proc_meta)
    _proc_meta = {}
    return {"ok": True, "stopped": True, "was": meta}


def start_search(body: dict, logs_dir: Path) -> dict:
    global _proc, _proc_meta

    if proc_running():
        return {"ok": False, "error": "Szukanie juz trwa — najpierw STOP"}

    exe = find_bin()
    if not exe.is_file():
        return {"ok": False, "error": f"Brak {exe} — uruchom build.bat"}

    mode = (body.get("mode") or "sequential").lower()
    gpu = (body.get("gpu") or "").strip()
    resume = bool(body.get("resume", True))

    args = [str(exe)]
    checkpoint = ACTIVE_CKPT
    meta: dict = {"mode": mode, "started_at": time.time()}

    if mode == "sequential":
        if gpu:
            cp = logs_dir / f"{gpu}.progress"
            if not cp.is_file():
                return {"ok": False, "error": f"Brak {cp.name} w {logs_dir}"}
            if resume:
                args += ["--resume", "--checkpoint", str(cp)]
                meta["gpu"] = gpu
                meta["checkpoint"] = str(cp)
                meta["resume"] = True
            else:
                raw = parse_kv_file(cp)
                start_h = norm_hex(raw.get("start", f"{PUZZLE_START:x}"))
                end_h = norm_hex(raw.get("end", f"{PUZZLE_END:x}"))
                args += [
                    "--mode", "sequential",
                    "--start", start_h,
                    "--end", end_h,
                    "--checkpoint", str(checkpoint),
                ]
                meta["gpu"] = gpu
                meta["start"] = start_h
                meta["end"] = end_h
                meta["resume"] = False
        else:
            start_h = norm_hex(body.get("start_hex") or f"{PUZZLE_START:x}")
            end_h = norm_hex(body.get("end_hex") or f"{PUZZLE_END:x}")
            if resume and checkpoint.is_file():
                args += ["--resume", "--checkpoint", str(checkpoint)]
                meta["resume"] = True
            else:
                args += [
                    "--mode", "sequential",
                    "--start", start_h,
                    "--end", end_h,
                    "--checkpoint", str(checkpoint),
                ]
                meta["resume"] = False
            meta["start"] = start_h
            meta["end"] = end_h

    elif mode == "random":
        sp = body.get("start_pct")
        ep = body.get("end_pct")
        if sp is not None and ep is not None:
            a, b = float(sp), float(ep)
            if a > b:
                a, b = b, a
            start_i = pct_to_int(a)
            end_i = pct_to_int(b)
            if end_i <= start_i:
                end_i = min(PUZZLE_END, start_i + max(1, PUZZLE_SPACE // 1_000_000))
        else:
            start_i = int(norm_hex(body.get("start_hex") or f"{PUZZLE_START:x}"), 16)
            end_i = int(norm_hex(body.get("end_hex") or f"{PUZZLE_END:x}"), 16)
            if start_i > end_i:
                start_i, end_i = end_i, start_i
        start_h = f"{start_i:x}"
        end_h = f"{end_i:x}"
        args += [
            "--mode", "random",
            "--start", start_h,
            "--end", end_h,
            "--checkpoint", str(checkpoint),
        ]
        meta["start"] = start_h
        meta["end"] = end_h
        meta["start_pct"] = round(int_to_pct(start_i), 4)
        meta["end_pct"] = round(int_to_pct(end_i), 4)
    else:
        return {"ok": False, "error": f"Nieznany tryb: {mode}"}

    RUN_LOG.parent.mkdir(parents=True, exist_ok=True)
    with RUN_LOG.open("a", encoding="utf-8") as lf:
        lf.write(f"\n--- START {time.ctime()} ---\n")
        lf.write(" ".join(args) + "\n")

    creationflags = 0
    if sys.platform == "win32":
        creationflags = subprocess.CREATE_NO_WINDOW  # type: ignore[attr-defined]

    try:
        log_fh = RUN_LOG.open("a", encoding="utf-8")
        _proc = subprocess.Popen(
            args,
            cwd=str(ROOT),
            stdout=log_fh,
            stderr=subprocess.STDOUT,
            creationflags=creationflags,
        )
    except OSError as e:
        return {"ok": False, "error": str(e)}

    _proc_meta = meta
    meta["pid"] = _proc.pid
    meta["cmd"] = args
    return {"ok": True, "started": meta}


def active_progress_path(logs_dir: Path) -> Path:
    if _proc_meta.get("checkpoint"):
        p = Path(_proc_meta["checkpoint"])
        if p.is_file():
            return p
    if ACTIVE_CKPT.is_file():
        return ACTIVE_CKPT
    gpu = _proc_meta.get("gpu")
    if gpu:
        p = logs_dir / f"{gpu}.progress"
        if p.is_file():
            return p
    return ACTIVE_CKPT


def collect(logs_dir: Path) -> dict:
    checkpoints = list_checkpoints(logs_dir)
    running = proc_running()
    prog_path = active_progress_path(logs_dir)
    progress = parse_progress(prog_path if prog_path.is_file() else ACTIVE_CKPT)

    return {
        "ok": True,
        "running": running,
        "proc_meta": _proc_meta,
        "progress": progress,
        "progress_path": str(prog_path),
        "checkpoints": checkpoints,
        "bin_exists": find_bin().is_file(),
        "bin_path": str(find_bin()),
        "logs_dir": str(logs_dir),
        "puzzle_start_hex": f"{PUZZLE_START:x}",
        "puzzle_end_hex": f"{PUZZLE_END:x}",
        "puzzle_start_short": trim_hex(f"{PUZZLE_START:x}"),
        "puzzle_end_short": trim_hex(f"{PUZZLE_END:x}"),
        "puzzle_space": PUZZLE_SPACE,
    }


class Handler(BaseHTTPRequestHandler):
    logs_dir = DEFAULT_LOGS

    def log_message(self, *args):
        return

    def _send(self, code: int, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/dashboard_local.html"):
            self._send(200, HTML.read_bytes(), "text/html; charset=utf-8")
        elif path == "/api":
            self._send(200, json.dumps(collect(self.logs_dir)).encode("utf-8"))
        else:
            self._send(404, b'{"ok":false,"error":"not found"}')

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, b'{"ok":false,"error":"invalid json"}')
            return

        if path == "/api/start":
            self._send(200, json.dumps(start_search(body, self.logs_dir)).encode("utf-8"))
        elif path == "/api/stop":
            self._send(200, json.dumps(stop_search()).encode("utf-8"))
        else:
            self._send(404, b'{"ok":false,"error":"not found"}')


def main() -> None:
    ap = argparse.ArgumentParser(description="Lokalny dashboard + sterowanie 1 GPU")
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--logs", type=Path, default=DEFAULT_LOGS, help="katalog gpu*.progress z vast")
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()

    if not HTML.exists():
        raise SystemExit("Brak dashboard_local.html")
    args.logs.mkdir(parents=True, exist_ok=True)

    Handler.logs_dir = args.logs.resolve()
    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    host = "127.0.0.1" if args.bind == "0.0.0.0" else args.bind
    url = f"http://{host}:{args.port}/"
    print(f"Lokalny panel (1 GPU): {url}")
    print(f"Checkpointy vast:      {Handler.logs_dir}/gpu*.progress")
    print(f"Binarny solver:        {find_bin()}")
    print("Start / Stop z przegladarki. Odswiezanie co 1 s.")
    if not args.no_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        stop_search()
        print("\nStop.")


if __name__ == "__main__":
    main()
