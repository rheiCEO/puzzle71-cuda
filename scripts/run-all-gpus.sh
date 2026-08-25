#!/usr/bin/env bash
# Odpal 1 proces na kazde GPU — rozne zakresy, bez nakladania.
# Domyślnie prefiks 74; nadpisz START_HEX / END_HEX (np. okno wokół wskazówki).
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

START="${START_HEX:-740000000000000000}"
END="${END_HEX:-74ffffffffffffffff}"

echo "==> $N GPU — SEQUENTIAL split"
echo "    zakres: $START .. $END"
echo "    logi: $ROOT/logs/gpu*.log"
echo "    podglad HTML:  python watch_multi.py --bind 0.0.0.0 --port 8768"
echo "    stop:  killall puzzle71-cuda"
echo

pkill -f "$BIN" 2>/dev/null || true
sleep 1

python3 - "$N" "$BIN" "$ROOT" "$START" "$END" <<'PY'
import os, subprocess, sys
n = int(sys.argv[1])
bin_path = sys.argv[2]
root = sys.argv[3]
start = int(sys.argv[4], 16)
end = int(sys.argv[5], 16)
span = end - start + 1
chunk = max(span // n, 1)
scale = os.environ.get("WORK_SCALE", "16")
for i in range(n):
    s = start + i * chunk
    e = start + (i + 1) * chunk - 1 if i < n - 1 else end
    if s > end:
        break
    log = os.path.join(root, "logs", f"gpu{i}.log")
    ckpt = os.path.join(root, "logs", f"gpu{i}.progress")
    cmd = [
        bin_path, "--mode", "sequential",
        "--start", format(s, "x"),
        "--end", format(e, "x"),
        "--checkpoint", ckpt,
        "--work-scale", scale,
    ]
    print(f"GPU {i}: {format(s,'x')} .. {format(e,'x')}  -> {log}")
    env = os.environ.copy()
    env["CUDA_VISIBLE_DEVICES"] = str(i)
    with open(log, "w") as f:
        subprocess.Popen(cmd, cwd=root, env=env, stdout=f, stderr=subprocess.STDOUT)
print("\nTail:\n  tail -f logs/gpu0.log")
PY
