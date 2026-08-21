# BTC CUDA MAGIC (puzzle71-cuda)

To nie jest „nowy algorytm 10×” — to **maksymalnie wyciśnięty CUDA pipeline** pod hash160 Puzzle #71.

## Co jest w MAGIC

| Zmiana | Po co |
|--------|--------|
| **Fused SHA256** z limbów `x` | mniej store/load w hot path |
| **RIPEMD160** z wordów SHA | mniej ruchu pamięci |
| **`gpu_puzzle_work`** | kernel tylko pod target hash160 (bez gałęzi score) |
| **Wczesny exit** na pierwszym limbie | większość kluczy odpada od razu |
| **Ping-pong offsets[2]** | work ∥ init następnego batcha (streams) |
| **`--magic`** | auto-dobór `work-scale` pod Twoją kartę |

## Czego MAGIC **nie** robi

- Nie omija hash160 (Puzzle #71 wymaga adresu)
- Nie daje XPOINT (brak pubkey)
- Nie obiecuje 10–100× na 1 karcie

Realny zysk vs naiwny port: zwykle **+10–40%** — mierz lokalnie.

## Build / test

```bat
build.bat
bin\puzzle71-cuda.exe --test
bin\puzzle71-cuda.exe --magic
bin\puzzle71-cuda.exe --bench 10
```

Panel lokalny: `WATCH-LOCAL.bat`

## Vast

Jak wcześniej — `puzzle71-cuda` + `watch_multi` / lokalny panel. Po `git pull` przebuduj:

```bash
bash scripts/build.sh
./bin/puzzle71-cuda --bench 10
```
