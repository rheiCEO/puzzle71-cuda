#!/usr/bin/env bash
# 1 GPU — Puzzle #71
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${BIN:-$ROOT/bin/puzzle71-cuda}"
MODE="${1:-random}"

if [[ ! -x "$BIN" ]]; then
  echo "Brak $BIN — najpierw: bash scripts/build.sh"
  exit 1
fi

cd "$ROOT"
echo "==> nvidia-smi"
nvidia-smi || true

if [[ "$MODE" == "sequential" ]]; then
  exec "$BIN" --mode sequential --work-scale "${WORK_SCALE:-16}"
else
  exec "$BIN" --mode random --work-scale "${WORK_SCALE:-16}"
fi
