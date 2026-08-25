#!/usr/bin/env python3
"""Telegram: HIT Puzzle #71 + postęp co N mld kluczy. Nie wymaga przebudowy CUDA."""
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

# 10000 mld = 10_000 * 10^9 = 10^13 kluczy
PROGRESS_EVERY = int(os.environ.get("TELEGRAM_PROGRESS_EVERY_MLD", "10000")) * 1_000_000_000

KEY_RE = re.compile(r"Klucz:\s*([0-9a-fA-F]+)")
H160_RE = re.compile(r"Hash160:\s*([0-9a-fA-F]+)")
HIT_RE = re.compile(r"\*\*\*\s*ZNALEZIONO\s*\*\*\*")
SPEED_RE = re.compile(r"~(\d+(?:\.\d+)?)\s*M/s")
TOTAL_MLD_RE = re.compile(r"lacznie\s+(\d+(?:\.\d+)?)\s*mld", re.I)
TOTAL_KEYS_RE = re.compile(r"^total_keys=(\d+)", re.M)


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
            "Zapisz w telegram.env albo export na vast."
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
        "🚨 Puzzle #71 ZNALEZIONY",
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


def fmt_keys(n: int) -> str:
    mld = n / 1e9
    if mld >= 1000:
        return f"{mld/1000:.2f} bln ({n:,} kluczy)".replace(",", " ")
    return f"{mld:.2f} mld ({n:,} kluczy)".replace(",", " ")


def sum_checked(logs_dir: Path) -> tuple[int, int | None]:
    """Suma total_keys z progress + fallback z logow. Zwraca (keys, speed_sum_or_None)."""
    total = 0
    speed_sum = 0
    seen_logs: set[Path] = set()
    for prog in sorted(logs_dir.glob("gpu*.progress")):
        try:
            text = prog.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        m = TOTAL_KEYS_RE.search(text)
        keys = int(m.group(1)) if m else 0
        log = prog.with_suffix(".log")
        seen_logs.add(log)
        if log.is_file():
            try:
                with log.open("rb") as f:
                    f.seek(0, 2)
                    size = f.tell()
                    f.seek(max(0, size - 65536))
                    chunk = f.read().decode("utf-8", errors="ignore")
                lm = TOTAL_MLD_RE.findall(chunk)
                if lm:
                    keys = max(keys, int(float(lm[-1]) * 1e9))
                sm = SPEED_RE.findall(chunk)
                if sm:
                    speed_sum += int(float(sm[-1]) * 1_000_000)
            except OSError:
                pass
        total += keys
    # logi bez progress
    for log in logs_dir.glob("gpu*.log"):
        if log in seen_logs:
            continue
        try:
            with log.open("rb") as f:
                f.seek(0, 2)
                size = f.tell()
                f.seek(max(0, size - 65536))
                chunk = f.read().decode("utf-8", errors="ignore")
            lm = TOTAL_MLD_RE.findall(chunk)
            if lm:
                total += int(float(lm[-1]) * 1e9)
            sm = SPEED_RE.findall(chunk)
            if sm:
                speed_sum += int(float(sm[-1]) * 1_000_000)
        except OSError:
            pass
    return total, (speed_sum or None)


def cmd_test() -> None:
    telegram_send(
        "🟢 puzzle71-cuda ONLINE\n\n"
        "Szukanie losowe Puzzle #71\n"
        "zakres: 7400… → 74ff… (prefiks 74)\n"
        f"Alerty: HIT + co {PROGRESS_EVERY // 1_000_000_000} mld kluczy\n"
        "— Telegram OK"
    )
    print("Wyslano test na Telegram.")


def cmd_send(priv: str, hash160: str, source: str) -> None:
    write_found(priv, hash160)
    telegram_send(format_message(priv, hash160, source))
    print("Wyslano trafienie na Telegram.")


def cmd_watch(logs_dir: Path) -> None:
    creds()
    logs_dir.mkdir(parents=True, exist_ok=True)
    state_path = logs_dir / ".telegram_state.json"
    sent: set[str] = set()
    last_milestone = 0
    if state_path.is_file():
        try:
            st = json.loads(state_path.read_text(encoding="utf-8"))
            sent = set(st.get("sent", []))
            last_milestone = int(st.get("last_milestone", 0))
        except (OSError, json.JSONDecodeError, ValueError, TypeError):
            pass

    offsets: dict[Path, int] = {}
    every_mld = PROGRESS_EVERY // 1_000_000_000
    print(f"Telegram watch: {logs_dir}")
    print(f"  HIT + progress co {every_mld} mld  (Ctrl+C = stop)")

    def save_state() -> None:
        try:
            state_path.write_text(
                json.dumps({"sent": sorted(sent), "last_milestone": last_milestone}),
                encoding="utf-8",
            )
        except OSError:
            pass

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
            save_state()

        total, speed = sum_checked(logs_dir)
        if PROGRESS_EVERY > 0 and total >= last_milestone + PROGRESS_EVERY:
            milestone = (total // PROGRESS_EVERY) * PROGRESS_EVERY
            if milestone > last_milestone:
                last_milestone = milestone
                spd = f"\nPredkosc: ~{speed/1e6:.0f} M/s" if speed else ""
                msg = (
                    f"📊 Puzzle #71 — postęp\n\n"
                    f"Sprawdzono: {fmt_keys(total)}\n"
                    f"Kamień milowy: {milestone // 1_000_000_000} mld"
                    f"{spd}\n"
                    f"Tryb: losowy 7400…→74ff…"
                )
                try:
                    telegram_send(msg)
                    print(f"\nTelegram progress: {fmt_keys(total)}")
                except SystemExit as e:
                    print(e, file=sys.stderr)
                save_state()

        time.sleep(2.0)


def main() -> None:
    ap = argparse.ArgumentParser(description="Telegram alert Puzzle #71")
    ap.add_argument("--test", action="store_true", help="wyslij wiadomosc testowa")
    ap.add_argument("--send", nargs=2, metavar=("KLUCZ", "HASH160"), help="wyslij konkretne trafienie")
    ap.add_argument("--watch", action="store_true", help="sluchaj logs/ + progress")
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
