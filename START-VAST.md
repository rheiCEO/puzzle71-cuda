# Puzzle #71 — deploy na vast.ai (prefiks `63`)

Zakres skanowania:

```
630000000000000000 … 63ffffffffffffffff
```

(w pełnym zapisie 256-bit: `…000000000000000000000000000000000000000000000630000000000000000`)

Adres docelowy: `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU`

## Szybki start (vast.ai)

1. Wynajmij instancję: https://cloud.vast.ai/create/
2. Image: **CUDA devel**, np. `nvidia/cuda:12.8.0-devel-ubuntu22.04`
3. W terminalu instancji:

```bash
# opcja A — clone z GitHub
curl -fsSL https://raw.githubusercontent.com/rheiCEO/puzzle71-cuda/master/vast-setup.sh | bash
cd /workspace/puzzle71-cuda

# opcja B — wgraj folder projects/puzzle71-cuda z sejfu (scp/rsync)
# potem: cd /path/to/puzzle71-cuda && bash scripts/build.sh

export TELEGRAM_BOT_TOKEN='TWÓJ_TOKEN'
export TELEGRAM_CHAT_ID='TWÓJ_CHAT_ID'
export TELEGRAM_PROGRESS_EVERY_MLD=10000
export WORK_SCALE=16

# opcjonalnie nadpisz zakres (domyślnie już 63…)
export START_HEX=630000000000000000
export END_HEX=63ffffffffffffffff

chmod +x vast-start.sh scripts/*.sh
bash vast-start.sh
```

## Co robi `vast-start.sh`

- build CUDA (`scripts/build.sh`) jeśli brak binarki
- **losowe** szukanie na **wszystkich GPU** w zakresie `63…`
- dashboard HTML na porcie **8768**
- Telegram: test startu + **HIT** + postęp co **N mld** kluczy
- Cloudflare tunnel → link na Telegram

## Telegram lokalnie (test)

Skopiuj `telegram.env.example` → `telegram.env` i uzupełnij token/chat.

```bash
python3 telegram_notify.py --test
python3 telegram_notify.py --watch
```

## Windows (lokalnie, 1 GPU)

```bat
build.bat
LOSOWO.bat
```

Albo z Telegram + dashboard:

```powershell
.\local-start.ps1
```

## Stop

```bash
killall puzzle71-cuda
pkill -f watch_multi.py
pkill -f telegram_notify.py
pkill -f cloudflared
```

## Uwagi

- `telegram.env` jest w `.gitignore` — **nie commituj tokenu**
- Tryb losowy może teoretycznie powtórzyć klucz — przy 2^64 praktycznie bez znaczenia
- Pełne P71 to 2^70; prefiks `63` = 2^64 (64× mniejsza przestrzeń)
