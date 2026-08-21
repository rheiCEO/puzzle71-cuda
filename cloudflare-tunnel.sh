#!/usr/bin/env bash
# Cloudflare quick tunnel -> dashboard Puzzle #71 (port 8768)
# Wypisze publiczny URL: https://xxx.trycloudflare.com
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${WATCH_PORT:-8768}"
LOG="${ROOT}/logs/cloudflare.log"

mkdir -p "$ROOT/logs"

if ! curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null \
   && ! curl -sf "http://127.0.0.1:${PORT}/api" >/dev/null; then
  echo "BLAD: dashboard nie dziala na :${PORT}"
  echo "Uruchom najpierw: bash $ROOT/vast-start.sh"
  exit 1
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "==> Instalacja cloudflared..."
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) CF=cloudflared-linux-amd64 ;;
    aarch64|arm64) CF=cloudflared-linux-arm64 ;;
    *) echo "Nieznany arch: $ARCH"; exit 1 ;;
  esac
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/${CF}" \
    -o /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

pkill -f "cloudflared tunnel --url http://127.0.0.1:${PORT}" 2>/dev/null || true
sleep 1

# Tryb FOREGROUND (domyslnie) albo BACKGROUND=1
if [[ "${BACKGROUND:-0}" == "1" ]]; then
  echo "==> Cloudflare tunnel (tlo) -> http://127.0.0.1:${PORT}"
  : > "$LOG"
  nohup cloudflared tunnel --url "http://127.0.0.1:${PORT}" > "$LOG" 2>&1 &
  echo $! > "$ROOT/logs/cloudflare.pid"
  URL=""
  for _ in $(seq 1 40); do
    sleep 1
    URL="$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG" | tail -1 || true)"
    if [[ -n "$URL" ]]; then
      break
    fi
  done
  if [[ -n "$URL" ]]; then
    echo "$URL" > "$ROOT/logs/cloudflare.url"
    echo "==> PUBLICZNY URL: $URL"
    # wyslij na Telegram jesli skonfigurowany
    if [[ -f "$ROOT/telegram.env" ]] || [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
      python3 - <<PY || true
import os, urllib.parse, urllib.request
from pathlib import Path
root = Path(r"$ROOT")
envp = root / "telegram.env"
if envp.exists():
    for line in envp.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k,v = line.split("=",1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
token = os.environ.get("TELEGRAM_BOT_TOKEN","").strip()
chat = os.environ.get("TELEGRAM_CHAT_ID","").strip()
url = "$URL"
if token and chat and url:
    body = urllib.parse.urlencode({
        "chat_id": chat,
        "text": f"🌐 Puzzle #71 dashboard ONLINE\\n\\n{url}\\n\\nAPI: {url}/api",
        "disable_web_page_preview": "true",
    }).encode()
    urllib.request.urlopen(
        urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", data=body, method="POST"),
        timeout=20,
    )
    print("Telegram: URL wyslany")
PY
    fi
  else
    echo "UWAGA: nie udalo sie wyciagnac URL — tail -f $LOG"
  fi
  exit 0
fi

echo "==> Cloudflare tunnel -> http://127.0.0.1:${PORT}"
echo "    Szukaj linii: https://....trycloudflare.com"
echo
exec cloudflared tunnel --url "http://127.0.0.1:${PORT}"
