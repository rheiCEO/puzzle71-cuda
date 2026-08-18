#!/usr/bin/env python3
"""
Worker — laczy sie z serwerem coop i uruchamia puzzle71-cuda.exe na przydzielonym zakresie.

Uzycie:
  python worker.py http://IP:8765 Kuba
  python worker.py https://twoj-serwer.pl:8765 GPU2
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / "bin" / "puzzle71-cuda.exe"
FOUND_RE = re.compile(r"Klucz:\s*([0-9a-fA-F]+)", re.I)
H160_RE = re.compile(r"Hash160:\s*([0-9a-fA-F]+)", re.I)


def api(base: str, path: str, data: dict | None = None) -> dict:
    url = base.rstrip("/") + path
    if data is None:
        req = urllib.request.Request(url, method="GET")
    else:
        body = json.dumps(data).encode("utf-8")
        req = urllib.request.Request(
            url, data=body, method="POST",
            headers={"Content-Type": "application/json"},
        )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def run_chunk(base: str, worker_id: str, claim: dict) -> tuple[int, bool, str | None]:
    start = claim["start"]
    end = claim["end"]
    claim_id = claim["claim_id"]
    target = claim.get("target", "f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8")
    ckpt = ROOT / f"coop_{worker_id}.progress"

    cmd = [
        str(EXE),
        "--mode", "sequential",
        "--start", start,
        "--end", end,
        "--target", target,
        "--checkpoint", str(ckpt),
    ]
    print(f"\n>>> Batch claim #{claim_id}")
    print(f"    zakres: {start} .. {end}")
    print(f"    (~{claim.get('chunk_keys', '?')} kluczy)\n")

    proc = subprocess.Popen(
        cmd,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proc.stdout
    output_lines = []
    found = False
    privkey = None
    for line in proc.stdout:
        print(line, end="")
        output_lines.append(line)
        if "ZNALEZIONO" in line:
            found = True
    proc.wait()
    full = "".join(output_lines)

    if found:
        m = FOUND_RE.search(full)
        privkey = m.group(1) if m else None
        h = H160_RE.search(full)
        hash160 = h.group(1) if h else target
        if privkey:
            api(base, "/found", {
                "worker_id": worker_id,
                "privkey": privkey,
                "hash160": hash160,
            })
        return claim.get("chunk_keys", 0), True, privkey

    keys_done = claim.get("chunk_keys", 0)
    return keys_done, False, None


def main():
    if len(sys.argv) < 3:
        print("Uzycie: python worker.py URL NAZWA")
        print("Przyklad: python worker.py http://192.168.1.10:8765 Kuba")
        sys.exit(1)

    base = sys.argv[1].rstrip("/")
    name = sys.argv[2]
    worker_id = re.sub(r"[^a-zA-Z0-9_-]", "_", name)[:32] or "worker"

    if not EXE.exists():
        print(f"BLAD: brak {EXE} — uruchom build.bat lub rozpakuj paczke portable")
        sys.exit(1)

    print(f"Coop worker: {name} ({worker_id})")
    print(f"Serwer: {base}")
    print(f"Exe: {EXE}\n")

    while True:
        try:
            st = api(base, "/status")
            if st.get("found"):
                f = st["found"]
                print(f"\n*** JUZ ZNALEZIONO (worker {f.get('worker')}) ***")
                print(f"Klucz: {f.get('privkey')}")
                break

            claim = api(base, "/claim", {"worker_id": worker_id, "name": name})

            if claim.get("status") == "found":
                print(f"\n*** JUZ ZNALEZIONO: {claim.get('privkey')} ***")
                break
            if claim.get("status") == "exhausted":
                print("\nCalý zakres rozdany — koniec coop.")
                break
            if claim.get("status") != "ok":
                print("Nieoczekiwana odpowiedz:", claim)
                time.sleep(5)
                continue

            keys_done, found, privkey = run_chunk(base, worker_id, claim)

            if not found:
                api(base, "/complete", {
                    "worker_id": worker_id,
                    "claim_id": claim["claim_id"],
                    "keys_done": keys_done,
                })

            if found:
                print(f"\n*** TRAFIENIE! Klucz: {privkey} ***")
                break

        except urllib.error.URLError as e:
            print(f"Blad polaczenia z serwerem: {e} — retry za 10s...")
            time.sleep(10)
        except KeyboardInterrupt:
            print("\nPrzerwano.")
            break


if __name__ == "__main__":
    main()
