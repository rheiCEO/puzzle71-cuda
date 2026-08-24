#!/usr/bin/env bash
# Hunt wokół wskazówki: 63aae5ee8189877712
# Domyślnie okno ±2^48 (~2.8e14 kluczy) — sekwencyjnie od środka w dół/górę przez multi-GPU split.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

WATCH_PORT="${WATCH_PORT:-8768}"
WORK_SCALE="${WORK_SCALE:-16}"
export TELEGRAM_PROGRESS_EVERY_MLD="${TELEGRAM_PROGRESS_EVERY_MLD:-1000}"

# Centrum wskazówki
HINT="${HINT_HEX:-63aae5ee8189877712}"
# Rozmiar połowy okna w bitach (48 = ±2^47 ≈ 1.4e14 każda strona → span ~2^48)
HALF_BITS="${HALF_BITS:-48}"

mkdir -p logs

python3 - "$HINT" "$HALF_BITS" <<'PY' > /tmp/puzzle71_hint_range.env
import sys
hint = int(sys.argv[1], 16)
half = 1 << (int(sys.argv[2]) - 1)
lo_floor = 0x630000000000000000
hi_ceil = 0x63FFFFFFFFFFFFFFFF
lo = max(hint - half, lo_floor)
hi = min(hint + half - 1, hi_ceil)
print(f"export START_HEX={lo:x}")
print(f"export END_HEX={hi:x}")
print(f"export HINT_HEX={hint:x}")
print(f"# span={hi-lo+1} (~2^{(hi-lo+1).bit_length()-1})")
PY
# shellcheck disable=SC1091
source /tmp/puzzle71_hint_range.env

if [[ ! -x "$ROOT/bin/puzzle71-cuda" ]]; then
  echo "==> Brak binarki — build..."
  bash "$ROOT/scripts/build.sh"
fi

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  cat > "$ROOT/telegram.env" <<EOF
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
EOF
fi

echo "============================================"
echo "  puzzle71-cuda — HUNT WOKÓŁ WSKAZÓWKI"
echo "  hint:  $HINT"
echo "  start: $START_HEX"
echo "  end:   $END_HEX"
echo "  half_bits=$HALF_BITS  work_scale=$WORK_SCALE"
echo "  tryb: SEQUENTIAL (split na GPU)"
echo "============================================"

pkill -f "watch_multi.py" 2>/dev/null || true
sleep 1
nohup python3 "$ROOT/watch_multi.py" --bind 0.0.0.0 --port "$WATCH_PORT" --no-browser \
  > "$ROOT/logs/watch.log" 2>&1 &
echo $! > "$ROOT/logs/watch.pid"
sleep 2

pkill -f "telegram_notify.py" 2>/dev/null || true
sleep 1
if [[ -f "$ROOT/telegram.env" ]] || [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  python3 "$ROOT/telegram_notify.py" --test || true
  nohup python3 "$ROOT/telegram_notify.py" --watch \
    > "$ROOT/logs/telegram.log" 2>&1 &
  echo $! > "$ROOT/logs/telegram.pid"
fi

chmod +x "$ROOT/scripts/"*.sh "$ROOT/cloudflare-tunnel.sh" 2>/dev/null || true
export START_HEX END_HEX
WORK_SCALE="$WORK_SCALE" bash "$ROOT/scripts/run-all-gpus.sh"

if [[ "${CLOUDFLARE:-1}" != "0" ]]; then
  BACKGROUND=1 WATCH_PORT="$WATCH_PORT" bash "$ROOT/cloudflare-tunnel.sh" || true
fi

cat <<EOF

GOTOWE — hunt wokół $HINT
  Zakres: $START_HEX .. $END_HEX
  Dashboard: http://127.0.0.1:${WATCH_PORT}/
  Log:       tail -f logs/gpu0.log

  Większe okno: HALF_BITS=56 bash vast-start-hint.sh
  Losowo w oknie: MODE=random (użyj vast-start.sh z START/END)

EOF
