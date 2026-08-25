# vast.ai — puzzle71-cuda RANDOM + HTML + Telegram (prefiks **74**)

Repo: https://github.com/rheiCEO/puzzle71-cuda

**Zakres:** `740000000000000000` … `74ffffffffffffffff`  
(pełny hex256: `…000000000000000000000000000000000000000000000740000000000000000`)

## 0. Wynajem

1. https://cloud.vast.ai/create/
2. Image: **CUDA devel**, np. `nvidia/cuda:12.8.0-devel-ubuntu22.04` (musi być `nvcc`)
3. Rent → Connect (SSH) / Jupyter terminal

## 1. Jedna wklejka (setup + start)

```bash
curl -fsSL https://raw.githubusercontent.com/rheiCEO/puzzle71-cuda/master/vast-setup.sh | bash

cd /workspace/puzzle71-cuda

export TELEGRAM_BOT_TOKEN='TWÓJ_TOKEN'
export TELEGRAM_CHAT_ID='-1004333221508'
export TELEGRAM_PROGRESS_EVERY_MLD=10000
export WORK_SCALE=16

chmod +x vast-start.sh scripts/*.sh
bash vast-start.sh
```

To robi:
- build CUDA
- **losowe** szukanie na **wszystkich GPU** (`7400…` → `74ff…`)
- HTML dashboard na porcie **8768** (ilość sprawdzonych kluczy + M/s)
- Telegram: powitanie + **HIT** + postęp **co 10000 mld**
- przy trafieniu: `FOUND.txt` + `logs/FOUND.txt` + wiadomość z kluczem

Token ustawiasz w `export` / `telegram.env` — **nie wrzucaj go do publicznego repo**.

## 2. HTML — Cloudflare (zalecane)

`vast-start.sh` sam odpala tunel i **wysyła link na Telegram**.

Ręcznie (jeśli dashboard już działa):
```bash
cd /workspace/puzzle71-cuda
BACKGROUND=1 bash cloudflare-tunnel.sh
cat logs/cloudflare.url
```

Albo na żywo w terminalu (URL wypisze cloudflared):
```bash
bash cloudflare-tunnel.sh
```

Bez Cloudflare (portal Vast):
```
Instance Portal → Tunnels → http://localhost:8768
```

## 3. Podgląd w SSH

```bash
tail -f /workspace/puzzle71-cuda/logs/gpu0.log
nvidia-smi
```

## 4. Stop

```bash
killall puzzle71-cuda
pkill -f watch_multi.py
pkill -f telegram_notify.py
pkill -f cloudflared
```

## 5. Samo Telegram (test)

```bash
cd /workspace/puzzle71-cuda
python3 telegram_notify.py --test
```

## Uwagi

- Token bota trzymaj w `telegram.env` (jest w `.gitignore`) — nie commituj do publicznego repo.
- 1× RTX ~3–4 mld kluczy/s → 10000 mld ≈ kilka godzin na 1 GPU (zależnie od karty).
- Tryb losowy może teoretycznie powtórzyć klucz — przy prefiksie 74 (2^64) to praktycznie bez znaczenia.
