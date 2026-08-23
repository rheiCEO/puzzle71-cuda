#!/usr/bin/env bash
# 1 GPU — Puzzle #71 prefiks 63
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/bin/puzzle71-cuda}"
MODE="${1:-random}"
START="${START_HEX:-630000000000000000}"
END="${END_HEX:-63ffffffffffffffff}"

if [[ ! -x "$BIN" ]]; then
  echo "Brak $BIN — najpierw: bash scripts/build.sh"
  exit 1
fi

cd "$ROOT"
echo "==> nvidia-smi"
nvidia-smi || true
echo "==> zakres: $START .. $END"

if [[ "$MODE" == "sequential" ]]; then
  exec "$BIN" --mode sequential --start "$START" --end "$END" --work-scale "${WORK_SCALE:-16}"
else
  exec "$BIN" --mode random --start "$START" --end "$END" --work-scale "${WORK_SCALE:-16}"
fi
