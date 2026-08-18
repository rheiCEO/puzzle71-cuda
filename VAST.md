# vast.ai — puzzle71-cuda

Repo: https://github.com/rheiCEO/puzzle71-cuda

## 1. Wynajmij GPU

1. Wejdź na https://cloud.vast.ai/create/
2. Weź **8× RTX 5090** (~$3.20/h) albo **8× RTX 5080** (~$1.29/h) — nie 5060 Ti
3. **Template / Image:** CUDA **devel** z `nvcc`, np.
   - `nvidia/cuda:12.8.0-devel-ubuntu22.04`
   - albo `nvidia/cuda:12.4.1-devel-ubuntu22.04`
   - **NIE** sam PyTorch / runtime (bez nvcc nie skompilujesz)
4. Disk: 32–64 GB wystarczy
5. **Rent** → poczekaj aż status = running
6. **Connect** / skopiuj SSH (OpenSSH)

## 2. SSH i jedna komenda

```bash
curl -fsSL https://raw.githubusercontent.com/rheiCEO/puzzle71-cuda/master/vast-setup.sh | bash
```

Albo ręcznie:

```bash
cd /workspace || cd /root
git clone https://github.com/rheiCEO/puzzle71-cuda.git
cd puzzle71-cuda
bash scripts/build.sh
./bin/puzzle71-cuda --test
```

## 3. Szukanie

**Jedna karta:**
```bash
./scripts/run.sh random
```

**Wszystkie 8 GPU (każda inny zakres Puzzle #71):**
```bash
bash scripts/run-all-gpus.sh
tail -f logs/gpu0.log
```

**Podgląd HTML — suma wszystkich GPU (jak WATCH.bat lokalnie):**
```bash
# w osobnym terminalu / tmux pane:
python3 watch_multi.py --bind 0.0.0.0 --port 8768 --no-browser
```
Otwórz w przeglądarce przez **Instance Portal → Tunnels → Create new tunnel**:
```
http://localhost:8768
```
Na stronie jest przycisk **Pobierz wszystkie .progress (ZIP)** — albo:
`https://<adres-tunelu>/download/progress.zip`

Pokazuje: łączne klucze, prędkość, pasek Puzzle #71, karty GPU i pobieranie checkpointów.

**Telegram — gdy znajdzie, wyśle adres + klucz:**

1. Telegram → [@BotFather](https://t.me/BotFather) → `/newbot` → skopiuj token
2. Napisz do swojego bota dowolną wiadomość
3. Na vast:
```bash
curl -s "https://api.telegram.org/botTOKEN/getUpdates"
```
W JSON szukaj `"chat":{"id": 123456789}` — to jest `TELEGRAM_CHAT_ID`.

4. Zapisz i przetestuj (osobny terminal, GPU zostaw w spokoju):
```bash
cd /workspace/puzzle71-cuda
cat > telegram.env << 'EOF'
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_CHAT_ID=123456789
EOF
python3 telegram_notify.py --test
python3 telegram_notify.py --watch
```

`--watch` czyta `logs/gpu*.log` — **nie trzeba przebudowywać** binarki, która już liczy.

Stop:
```bash
killall puzzle71-cuda
```

## 4. Sprawdź czy 8 kart liczy

```bash
nvidia-smi
```

Każda karta powinna mieć ~100% GPU-Util i proces `puzzle71-cuda`.

## 5. Zostaw w screen/tmux

```bash
apt-get install -y tmux
tmux new -s p71
bash scripts/run-all-gpus.sh
# Ctrl+B, D  — odłącz, SSH możesz zamknąć
# tmux attach -t p71
```
