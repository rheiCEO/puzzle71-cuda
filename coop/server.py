#!/usr/bin/env python3
"""
puzzle71-cuda — serwer koordynacji (3+ GPU, wspólny postęp online).

Uruchomienie:
  python server.py
  python server.py --host 0.0.0.0 --port 8765

Zmienne:
  PUZZLE71_RANGE_START  hex (domyślnie prefiks 74: 0x7400…00)
  PUZZLE71_RANGE_END    hex (domyślnie prefiks 74: 0x74ff…ff)
  PUZZLE71_CHUNK_BITS   rozmiar przydzielanego bloku (domyślnie 38)
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

DB_PATH = Path(__file__).with_name("coop.db")
RANGE_START = int(os.environ.get("PUZZLE71_RANGE_START", "0x740000000000000000"), 16)
RANGE_END = int(os.environ.get("PUZZLE71_RANGE_END", "0x74ffffffffffffffff"), 16)
CHUNK_BITS = int(os.environ.get("PUZZLE71_CHUNK_BITS", "38"))
TARGET_H160 = "f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8"
PUZZLE_ADDR = "1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU"

_db_lock = threading.Lock()


def hex256(n: int) -> str:
    return format(n & ((1 << 256) - 1), "064x")


def init_db() -> None:
    with sqlite3.connect(DB_PATH) as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS workers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              last_seen REAL NOT NULL,
              keys_done INTEGER NOT NULL DEFAULT 0,
              current_start TEXT,
              current_end TEXT
            );
            CREATE TABLE IF NOT EXISTS claims (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              worker_id TEXT NOT NULL,
              start_hex TEXT NOT NULL,
              end_hex TEXT NOT NULL,
              status TEXT NOT NULL,
              keys_in_range INTEGER NOT NULL DEFAULT 0,
              claimed_at REAL NOT NULL,
              completed_at REAL
            );
            CREATE TABLE IF NOT EXISTS found (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              worker_id TEXT,
              privkey TEXT NOT NULL,
              hash160 TEXT,
              found_at REAL NOT NULL
            );
            """
        )
        cur = con.execute("SELECT value FROM meta WHERE key='next_start'")
        if cur.fetchone() is None:
            con.execute("INSERT INTO meta(key,value) VALUES('next_start',?)", (hex256(RANGE_START),))
            con.execute("INSERT INTO meta(key,value) VALUES('range_end',?)", (hex256(RANGE_END),))
            con.execute("INSERT INTO meta(key,value) VALUES('chunk_bits',?)", (str(CHUNK_BITS),))
            con.execute("INSERT INTO meta(key,value) VALUES('target',?)", (TARGET_H160,))


def get_meta(con: sqlite3.Connection) -> dict:
    rows = con.execute("SELECT key,value FROM meta").fetchall()
    return {k: v for k, v in rows}


def claim_range(worker_id: str, name: str) -> dict:
    with _db_lock:
        with sqlite3.connect(DB_PATH) as con:
            meta = get_meta(con)
            next_start = int(meta["next_start"], 16)
            range_end = int(meta["range_end"], 16)
            chunk_bits = int(meta.get("chunk_bits", str(CHUNK_BITS)))

            found = con.execute("SELECT privkey, hash160 FROM found ORDER BY id DESC LIMIT 1").fetchone()
            if found:
                return {"status": "found", "privkey": found[0], "hash160": found[1]}

            if next_start > range_end:
                return {"status": "exhausted", "message": "Caly zakres przydzielony"}

            chunk = (1 << chunk_bits) - 1
            end = min(next_start + chunk, range_end)
            start_hex = hex256(next_start)
            end_hex = hex256(end)

            con.execute(
                "INSERT INTO meta(key,value) VALUES('next_start',?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (hex256(end + 1),),
            )
            now = time.time()
            con.execute(
                "INSERT INTO workers(id,name,last_seen,current_start,current_end) "
                "VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET "
                "name=excluded.name, last_seen=excluded.last_seen, "
                "current_start=excluded.current_start, current_end=excluded.current_end",
                (worker_id, name, now, start_hex, end_hex),
            )
            con.execute(
                "INSERT INTO claims(worker_id,start_hex,end_hex,status,claimed_at) "
                "VALUES(?,?,?,?,?)",
                (worker_id, start_hex, end_hex, "active", now),
            )
            claim_id = con.execute("SELECT last_insert_rowid()").fetchone()[0]
            con.commit()

            return {
                "status": "ok",
                "claim_id": claim_id,
                "start": start_hex,
                "end": end_hex,
                "target": meta.get("target", TARGET_H160),
                "chunk_keys": end - next_start + 1,
            }


def complete_claim(worker_id: str, claim_id: int, keys_done: int) -> None:
    with _db_lock:
        with sqlite3.connect(DB_PATH) as con:
            now = time.time()
            con.execute(
                "UPDATE claims SET status='done', completed_at=?, keys_in_range=? "
                "WHERE id=? AND worker_id=?",
                (now, keys_done, claim_id, worker_id),
            )
            row = con.execute(
                "SELECT keys_done FROM workers WHERE id=?", (worker_id,)
            ).fetchone()
            prev = row[0] if row else 0
            con.execute(
                "UPDATE workers SET last_seen=?, keys_done=?, current_start=NULL, current_end=NULL "
                "WHERE id=?",
                (now, prev + keys_done, worker_id),
            )
            con.commit()


def report_found(worker_id: str, privkey: str, hash160: str) -> None:
    with _db_lock:
        with sqlite3.connect(DB_PATH) as con:
            con.execute(
                "INSERT INTO found(worker_id,privkey,hash160,found_at) VALUES(?,?,?,?)",
                (worker_id, privkey, hash160, time.time()),
            )
            con.commit()


def build_status() -> dict:
    with sqlite3.connect(DB_PATH) as con:
        meta = get_meta(con)
        next_start = int(meta["next_start"], 16)
        range_start = RANGE_START
        range_end = int(meta["range_end"], 16)
        total_space = range_end - range_start + 1
        assigned = max(0, next_start - range_start)
        pct = (assigned / total_space * 100) if total_space else 0

        workers = [
            {
                "id": r[0],
                "name": r[1],
                "last_seen": r[2],
                "keys_done": r[3],
                "current_start": r[4],
                "current_end": r[5],
                "online": (time.time() - r[2]) < 120,
            }
            for r in con.execute(
                "SELECT id,name,last_seen,keys_done,current_start,current_end FROM workers"
            )
        ]
        done_claims = con.execute(
            "SELECT COUNT(*), COALESCE(SUM(keys_in_range),0) FROM claims WHERE status='done'"
        ).fetchone()
        found = con.execute(
            "SELECT privkey, hash160, found_at, worker_id FROM found ORDER BY id DESC LIMIT 1"
        ).fetchone()

        return {
            "puzzle_address": PUZZLE_ADDR,
            "target_hash160": meta.get("target", TARGET_H160),
            "range_start": hex256(range_start),
            "range_end": meta["range_end"],
            "next_start": meta["next_start"],
            "assigned_keys": assigned,
            "total_keys": total_space,
            "assigned_percent": round(pct, 10),
            "completed_chunks": done_claims[0],
            "completed_keys_reported": done_claims[1],
            "workers": workers,
            "found": (
                {"privkey": found[0], "hash160": found[1], "at": found[2], "worker": found[3]}
                if found
                else None
            ),
        }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[{time.strftime('%H:%M:%S')}] {self.address_string()} {fmt % args}")

    def _json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        n = int(self.headers.get("Content-Length", 0))
        if n <= 0:
            return {}
        return json.loads(self.rfile.read(n))

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/status"):
            self._json(200, build_status())
        elif path == "/health":
            self._json(200, {"ok": True})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        data = self._read_json()

        if path == "/claim":
            worker_id = str(data.get("worker_id", "")).strip()
            name = str(data.get("name", worker_id)).strip()
            if not worker_id:
                self._json(400, {"error": "worker_id required"})
                return
            self._json(200, claim_range(worker_id, name))

        elif path == "/complete":
            worker_id = str(data.get("worker_id", "")).strip()
            claim_id = int(data.get("claim_id", 0))
            keys_done = int(data.get("keys_done", 0))
            if not worker_id or not claim_id:
                self._json(400, {"error": "worker_id and claim_id required"})
                return
            complete_claim(worker_id, claim_id, keys_done)
            self._json(200, {"ok": True})

        elif path == "/found":
            worker_id = str(data.get("worker_id", "")).strip()
            privkey = str(data.get("privkey", "")).strip()
            hash160 = str(data.get("hash160", TARGET_H160)).strip()
            if not privkey:
                self._json(400, {"error": "privkey required"})
                return
            report_found(worker_id, privkey, hash160)
            self._json(200, {"ok": True, "message": "KEY FOUND — stop all workers"})

        else:
            self._json(404, {"error": "not found"})


def main():
    parser = argparse.ArgumentParser(description="puzzle71 coop server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    init_db()
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"puzzle71 coop server: http://{args.host}:{args.port}")
    print(f"  status:  http://127.0.0.1:{args.port}/status")
    print(f"  puzzle:  {PUZZLE_ADDR}")
    print(f"  DB:      {DB_PATH}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStop.")


if __name__ == "__main__":
    main()
