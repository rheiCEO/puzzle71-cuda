# BTC CUDA v2 (puzzle71-cuda)

To nie jest „nowy algorytm magiczny 10×” — to **ulepszenie tego samego CUDA pipeline** co Synapse/ETH vanity, pod BTC hash160.

## Co zmieniło się w v2

| Zmiana | Po co |
|--------|--------|
| **Fused SHA256** z limbów `x` (bez bufora 33/64 B) | mniej store/load w hot path |
| **RIPEMD160** z wordów SHA (bswap, bez bajtów) | mniej ruchu pamięci |
| **`__constant__` K** SHA256 | szybszy dostęp do stałych |
| **`__funnelshift`** rotacje | natywne instrukcje GPU |
| **CUDA streams** | async kopiowanie wyników / symboli |

## Czego v2 **nie** robi

- Nie omija hash160 (Puzzle #71 wymaga adresu)
- Nie daje XPOINT (brak pubkey)
- Nie obiecuje 10–100× na 1 karcie

Realny zysk: zwykle **+10–40%** vs v1 (zależnie od GPU) — mierz `--bench 10`.

## Build / test

```bat
build.bat
bin\puzzle71-cuda.exe --test
bin\puzzle71-cuda.exe --bench 10
```

Panel lokalny: `WATCH-LOCAL.bat`

## Vast

Jak wcześniej — `puzzle71-cuda` + `watch_multi` / lokalny panel. Po `git pull` przebuduj:

```bash
bash scripts/build.sh
./bin/puzzle71-cuda --bench 10
```
