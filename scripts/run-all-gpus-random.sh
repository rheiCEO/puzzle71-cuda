#!/usr/bin/env bash
# Odpal 1 proces na kazde GPU — tryb LOSOWY (caly zakres Puzzle #71).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/bin/puzzle71-cuda}"
cd "$ROOT"
mkdir -p logs

if [[ ! -x "$BIN" ]]; then
  echo "Brak $BIN — bash scripts/build.sh"
  exit 1
fi

N="$(nvidia-smi -L | wc -l)"
if [[ "$N" -lt 1 ]]; then
  echo "Brak GPU"
  exit 1
fi

SCALE="${WORK_SCALE:-16}"
START="${START_HEX:-740000000000000000}"
END="${END_HEX:-74ffffffffffffffff}"
SNAP="${SNAPSHOT_FILE:-}"

echo "==> $N GPU — RANDOM Puzzle #71 (prefiks 74)"
if [[ -n "$SNAP" ]]; then
  echo "    SNAPSHOT VRAM: $SNAP"
fi
echo "    zakres: $START .. $END"
echo "    work_scale=$SCALE"
echo "    logi: $ROOT/logs/gpu*.log"
echo

pkill -f "$BIN" 2>/dev/null || true
sleep 1

for ((i=0; i<N; i++)); do
  log="$ROOT/logs/gpu${i}.log"
  ckpt="$ROOT/logs/gpu${i}.progress"
  echo "GPU $i -> $log"
  EXTRA=()
  if [[ -n "$SNAP" && -f "$SNAP" ]]; then
    EXTRA=(--snapshot "$SNAP")
  fi
  CUDA_VISIBLE_DEVICES="$i" nohup stdbuf -oL -eL "$BIN" \
    --mode random \
    --start "$START" \
    --end "$END" \
    "${EXTRA[@]}" \
    --checkpoint "$ckpt" \
    --work-scale "$SCALE" \
    > "$log" 2>&1 &
  echo $! > "$ROOT/logs/gpu${i}.pid"
done

echo
echo "Tail:  tail -f logs/gpu0.log"
echo "Stop:  killall puzzle71-cuda"
