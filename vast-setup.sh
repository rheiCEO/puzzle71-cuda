#!/usr/bin/env bash
# vast.ai Linux GPU — clone + build puzzle71-cuda
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/rheiCEO/puzzle71-cuda.git}"

if [[ -n "${WORKSPACE:-}" ]]; then
  :
elif [[ -d /workspace ]]; then
  WORKSPACE=/workspace
elif [[ -d /root ]]; then
  WORKSPACE=/root
else
  WORKSPACE="$HOME"
fi

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

echo "==> puzzle71-cuda vast setup  workspace=$WORKSPACE"

export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
    sudo apt-get update -y
    sudo apt-get install -y build-essential git ca-certificates
  else
    apt-get update -y
    apt-get install -y build-essential git ca-certificates
  fi
fi

if ! command -v nvcc >/dev/null 2>&1; then
  echo "ERROR: nvcc not found."
  echo "On vast.ai pick CUDA *devel* image, e.g. nvidia/cuda:12.8.0-devel-ubuntu22.04"
  echo "Runtime / PyTorch-only images will not compile."
  exit 1
fi

if [[ -f "$WORKSPACE/puzzle71-cuda/scripts/build.sh" ]]; then
  ROOT="$WORKSPACE/puzzle71-cuda"
else
  echo "==> Cloning $REPO_URL"
  rm -rf puzzle71-cuda
  git clone --depth 1 "$REPO_URL" puzzle71-cuda
  ROOT="$WORKSPACE/puzzle71-cuda"
fi

cd "$ROOT"
chmod +x scripts/*.sh vast-setup.sh 2>/dev/null || true
bash scripts/build.sh

echo
nvidia-smi --query-gpu=index,name,memory.total --format=csv || nvidia-smi

cat <<EOF

--------------------------------------------
Gotowe. Test:
  cd $ROOT
  ./bin/puzzle71-cuda --test
  ./bin/puzzle71-cuda --bench 10

1 GPU:
  ./scripts/run.sh random

Wszystkie GPU (8x itd.) — sequential kawalki:
  ./scripts/run-all-gpus.sh

Wszystkie GPU — RANDOM caly zakres + HTML + Telegram:
  export TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=...
  bash vast-start.sh
--------------------------------------------
EOF
