#!/usr/bin/env python3
"""Wyślij na Telegram gdy Puzzle #71 zostanie znaleziony. Nie wymaga przebudowy CUDA."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEFAULT_LOGS = ROOT / "logs"
FOUND_FILES = (ROOT / "FOUND.txt", DEFAULT_LOGS / "FOUND.txt")
PUZZLE_ADDR = "1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU"
B58 = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

KEY_RE = re.compile(r"Klucz:\s*([0-9a-fA-F]+)")
H160_RE = re.compile(r"Hash160:\s*([0-9a-fA-F]+)")
HIT_RE = re.compile(r"\*\*\*\s*ZNALEZIONO\s*\*\*\*")


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip().strip('"').strip("'")
        if k and k not in os.environ:
            os.environ[k] = v


def creds() -> tuple[str, str]:
    load_dotenv(ROOT / "telegram.env")
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
    if not token or not chat:
        raise SystemExit(
            "Brak TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID.\n"
            "1) Telegram: @BotFather → /newbot → skopiuj token\n"
            "2) Napisz do bota cokolwiek, potem:\n"
            "   curl -s https://api.telegram.org/botTOKEN/getUpdates\n"
            "   (chat.id z odpowiedzi = TELEGRAM_CHAT_ID)\n"
            "3) export TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=...\n"
            "   albo zapisz w telegram.env"
        )
    return token, chat


def b58encode(data: bytes) -> str:
    n = int.from_bytes(data, "big")
    out = bytearray()
    while n > 0:
        n, r = divmod(n, 58)
        out.append(B58[r])
    pad = 0
    for b in data:
        if b == 0:
            pad += 1
        else:
            break
    return (B58[0:1] * pad + out[::-1]).decode("ascii")


def b58check(payload: bytes) -> str:
    chk = hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]
    return b58encode(payload + chk)


def p2pkh(hash160_hex: str) -> str:
    raw = bytes.fromhex(hash160_hex.strip())
    if len(raw) != 20:
        return PUZZLE_ADDR
    return b58check(b"\x00" + raw)


def wif_compressed(priv_hex: str) -> str:
    h = priv_hex.strip().lstrip("0") or "0"
    if len(h) % 2:
        h = "0" + h
    raw = bytes.fromhex(h)
    raw = (b"\x00" * (32 - len(raw))) + raw
    if len(raw) != 32:
        return ""
    return b58check(b"\x80" + raw + b"\x01")


def format_message(priv: str, hash160: str, source: str = "") -> str:
    addr = p2pkh(hash160) if hash160 else PUZZLE_ADDR
    wif = wif_compressed(priv) if priv else ""
    lines = [
        "Puzzle #71 ZNALEZIONY",
        "",
        f"Adres: {addr}",
        f"Klucz (hex): {priv}",
    ]
    if wif:
        lines.append(f"WIF: {wif}")
    if hash160:
        lines.append(f"Hash160: {hash160}")
    if source:
        lines.append(f"Zrodlo: {source}")
    return "\n".join(lines)


def telegram_send(text: str) -> None:
    token, chat = creds()
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    body = urllib.parse.urlencode({
        "chat_id": chat,
        "text": text,
        "disable_web_page_preview": "true",
    }).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if not data.get("ok"):
            raise SystemExit(f"Telegram odrzucil: {data}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="ignore")
        raise SystemExit(f"Telegram HTTP {e.code}: {detail}") from e


def parse_hit(text: str) -> tuple[str, str] | None:
    if not HIT_RE.search(text) and "Klucz:" not in text:
        return None
    km = KEY_RE.search(text)
    if not km:
        return None
    hm = H160_RE.search(text)
    return km.group(1), (hm.group(1) if hm else "")


def write_found(priv: str, hash160: str) -> None:
    msg = format_message(priv, hash160)
    DEFAULT_LOGS.mkdir(parents=True, exist_ok=True)
    for path in FOUND_FILES:
        path.write_text(msg + "\n", encoding="utf-8")


def cmd_test() -> None:
    telegram_send("puzzle71-cuda: test OK — Telegram dziala.")
    print("Wyslano test na Telegram.")


def cmd_send(priv: str, hash160: str, source: str) -> None:
    write_found(priv, hash160)
    telegram_send(format_message(priv, hash160, source))
    print("Wyslano trafienie na Telegram.")


def cmd_watch(logs_dir: Path) -> None:
    creds()
    logs_dir.mkdir(parents=True, exist_ok=True)
    sent: set[str] = set()
    offsets: dict[Path, int] = {}
    print(f"Czekam na ZNALEZIONO w {logs_dir}/gpu*.log  (Ctrl+C = stop)")
    print("Szukanie GPU moze isc osobno — ten proces tylko nasluchuje.")

    while True:
        files = list(logs_dir.glob("gpu*.log")) + [p for p in FOUND_FILES if p.exists()]
        for path in files:
            try:
                size = path.stat().st_size
            except OSError:
                continue
            pos = offsets.get(path, 0)
            if size < pos:
                pos = 0
            if size == pos:
                continue
            try:
                with path.open("r", encoding="utf-8", errors="ignore") as f:
                    f.seek(pos)
                    chunk = f.read()
                    offsets[path] = f.tell()
            except OSError:
                continue
            hit = parse_hit(chunk)
            if not hit:
                continue
            priv, h160 = hit
            if priv in sent:
                continue
            sent.add(priv)
            print(f"\n*** TRAFIENIE z {path.name} — wysylam Telegram ***")
            try:
                cmd_send(priv, h160, path.name)
            except SystemExit as e:
                print(e, file=sys.stderr)
        time.sleep(1.0)


def main() -> None:
    ap = argparse.ArgumentParser(description="Telegram alert Puzzle #71")
    ap.add_argument("--test", action="store_true", help="wyslij wiadomosc testowa")
    ap.add_argument("--send", nargs=2, metavar=("KLUCZ", "HASH160"), help="wyslij konkretne trafienie")
    ap.add_argument("--watch", action="store_true", help="sluchaj logs/gpu*.log")
    ap.add_argument("--logs", type=Path, default=DEFAULT_LOGS)
    args = ap.parse_args()
    if args.test:
        cmd_test()
    elif args.send:
        cmd_send(args.send[0], args.send[1], "manual")
    else:
        cmd_watch(args.logs)


if __name__ == "__main__":
    main()
