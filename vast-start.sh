#!/usr/bin/env bash
# vast.ai — RANDOM Puzzle #71 + HTML dashboard + Telegram (HIT + co 10000 mld)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

WATCH_PORT="${WATCH_PORT:-8768}"
WORK_SCALE="${WORK_SCALE:-16}"
export TELEGRAM_PROGRESS_EVERY_MLD="${TELEGRAM_PROGRESS_EVERY_MLD:-10000}"

mkdir -p logs

if [[ ! -x "$ROOT/bin/puzzle71-cuda" ]]; then
  echo "==> Brak binarki — build..."
  bash "$ROOT/scripts/build.sh"
fi

# Telegram credentials (env albo telegram.env)
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  cat > "$ROOT/telegram.env" <<EOF
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
EOF
fi

if [[ ! -f "$ROOT/telegram.env" ]]; then
  echo "UWAGA: brak telegram.env — ustaw TELEGRAM_BOT_TOKEN i TELEGRAM_CHAT_ID"
fi

echo "============================================"
echo "  puzzle71-cuda vast — RANDOM START (prefiks 63)"
echo "  zakres: 6300… → 63ff…"
echo "  work_scale=$WORK_SCALE"
echo "  dashboard port=$WATCH_PORT"
echo "  telegram co ${TELEGRAM_PROGRESS_EVERY_MLD} mld"
echo "============================================"

# Dashboard
pkill -f "watch_multi.py" 2>/dev/null || true
sleep 1
nohup python3 "$ROOT/watch_multi.py" --bind 0.0.0.0 --port "$WATCH_PORT" --no-browser \
  > "$ROOT/logs/watch.log" 2>&1 &
echo $! > "$ROOT/logs/watch.pid"
sleep 2

# Telegram watcher
pkill -f "telegram_notify.py" 2>/dev/null || true
sleep 1
if [[ -f "$ROOT/telegram.env" ]] || [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  python3 "$ROOT/telegram_notify.py" --test || true
  nohup python3 "$ROOT/telegram_notify.py" --watch \
    > "$ROOT/logs/telegram.log" 2>&1 &
  echo $! > "$ROOT/logs/telegram.pid"
  echo "==> Telegram watch OK"
else
  echo "==> Telegram WYLACZONY (brak tokenu)"
fi

# GPU random
chmod +x "$ROOT/scripts/"*.sh "$ROOT/cloudflare-tunnel.sh" 2>/dev/null || true
export START_HEX="${START_HEX:-630000000000000000}"
export END_HEX="${END_HEX:-63ffffffffffffffff}"
WORK_SCALE="$WORK_SCALE" bash "$ROOT/scripts/run-all-gpus-random.sh"

# Cloudflare quick tunnel (publiczny URL) — jak przy ETH
if [[ "${CLOUDFLARE:-1}" != "0" ]]; then
  echo "==> Start Cloudflare tunnel..."
  BACKGROUND=1 WATCH_PORT="$WATCH_PORT" bash "$ROOT/cloudflare-tunnel.sh" || true
fi

CF_URL=""
if [[ -f "$ROOT/logs/cloudflare.url" ]]; then
  CF_URL="$(cat "$ROOT/logs/cloudflare.url")"
fi

cat <<EOF

GOTOWE.
  Lokalnie:   http://127.0.0.1:${WATCH_PORT}/
  Cloudflare: ${CF_URL:-'(jeszcze nie — tail -f logs/cloudflare.log)'}

  Log GPU0:   tail -f logs/gpu0.log
  Telegram:   tail -f logs/telegram.log
  CF log:     tail -f logs/cloudflare.log

  Stop:       killall puzzle71-cuda
              pkill -f watch_multi.py
              pkill -f telegram_notify.py
              pkill -f cloudflared

EOF
