#!/usr/bin/env python3
"""Lokalny dashboard HTML z puzzle71.progress — bez COOP."""
from __future__ import annotations

import json
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROGRESS = ROOT / "puzzle71.progress"
HTML = ROOT / "dashboard.html"
PORT = 8767


def parse_progress() -> dict:
    if not PROGRESS.exists():
        return {"ok": False}
    data = {"ok": True}
    for line in PROGRESS.read_text(encoding="utf-8", errors="ignore").splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        data[k.strip()] = v.strip()
    try:
        data["total_keys"] = int(data.get("total_keys", "0"))
    except ValueError:
        data["total_keys"] = 0
    data["age_sec"] = int(max(0, time.time() - PROGRESS.stat().st_mtime))
    return data


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        return

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/dashboard.html"):
            self._send(200, HTML.read_bytes(), "text/html; charset=utf-8")
        elif path == "/api":
            self._send(200, json.dumps(parse_progress()).encode("utf-8"), "application/json")
        else:
            self._send(404, b"not found", "text/plain")


def main():
    if not HTML.exists():
        raise SystemExit("Brak dashboard.html")
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}/"
    print(f"Dashboard: {url}")
    print(f"Plik:      {PROGRESS}")
    print("Zostaw to okno otwarte. Odswiezanie co 1 s.")
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
