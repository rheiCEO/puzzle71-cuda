#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v nvcc >/dev/null 2>&1; then
  echo "ERROR: nvcc not found"
  exit 1
fi

ARCH_FLAG="${CUDA_ARCH:--arch=native}"
OUT="${OUT:-$ROOT/bin/puzzle71-cuda}"
mkdir -p "$(dirname "$OUT")"

echo "==> nvcc $(nvcc --version | tail -n1)"
nvcc src/puzzle_main.cu -o "$OUT" \
  -Isrc \
  -std=c++17 \
  -O3 \
  $ARCH_FLAG \
  -Xcompiler -Wall

chmod +x "$OUT"
echo "==> OK: $OUT"
