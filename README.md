# puzzle71-cuda

GPU solver for **Bitcoin Puzzle #71** — fork architektury [eth-vanity-cuda](https://github.com/manuelinfosec/eth-vanity-cuda) z Keccak zastąpionym pipeline **SHA256 + RIPEMD160** (hash160).

## Puzzle #71

| Parametr | Wartość |
|----------|---------|
| Prefiks klucza | **`74`** (hex) |
| Start | `740000000000000000` |
| End | `74ffffffffffffffff` |
| Przestrzeń | 2⁶⁴ kluczy (64× mniej niż pełne Puzzle #71) |
| Adres | `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU` |
| Hash160 | `f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8` |

Algorytm: `priv → secp256k1 (compressed) → SHA256 → RIPEMD160 → porównanie hash160`

## Wymagania

- NVIDIA GPU + CUDA Toolkit (nvcc)
- Windows: Visual Studio Build Tools (MSVC)
- Linux: g++ + nvcc

## Build

**Windows:**
```bat
build.bat
```

**Linux / Brev:**
```bash
bash scripts/build.sh
```

## Tryby szukania

| Tryb | Flaga | Opis |
|------|-------|------|
| Sekwencyjny | `--mode sequential` (domyślnie) | Po kolei od `--start`, zapisuje `puzzle71.progress` co batch |
| Losowy w zakresie | `--mode random` | Losowy start batcha w `--start`…`--end`, w nieskończoność |
| Wznowienie | `--resume` | Kontynuacja sekwencyjna od ostatniego checkpointu |

```bat
bin\puzzle71-cuda.exe --mode sequential --start 740000000000000000 --end 74ffffffffffffffff
bin\puzzle71-cuda.exe --mode random --start 740000000000000000 --end 74ffffffffffffffff
bin\puzzle71-cuda.exe --resume
bin\puzzle71-cuda.exe --checkpoint moj.postep --resume
```

## Użycie

```bat
bin\puzzle71-cuda.exe --test          REM self-test + krótki benchmark
bin\puzzle71-cuda.exe --bench 10      REM benchmark 10 s
bin\puzzle71-cuda.exe                 REM skan Puzzle #71 (domyślny zakres)
bin\puzzle71-cuda.exe --work-scale 16 REM siatka GPU (2^16 bloków)
```

Opcje: `--start HEX`, `--end HEX`, `--target HASH160_HEX`

Zmienna środowiskowa: `PUZZLE71_WORK_SCALE` (10–20, domyślnie 16).

## Wydajność (orientacyjnie)

| Platforma | ~kluczy/s |
|-----------|-----------|
| CPU (puzzle71-solver, 8 wątków) | ~10⁵ |
| RTX 5070 Ti (ten projekt) | ~2×10⁹ |
| RTX 4090 (ETH vanity) | ~4×10⁹ |

Przy ~10⁹/s i przestrzeni 2⁷⁰ (~1.2×10²¹) — **~37 lat na 1 GPU** (statystycznie).

## Powiązane projekty

- [puzzle71-solver](https://github.com/rheiCEO/puzzle71-solver) — CPU referencja
- [eth-vanity-brev](https://github.com/rheiCEO/eth-vanity-brev) — deploy ETH vanity na GPU w chmurze

## Licencja

Kod bazowy eth-vanity-cuda: **AGPL-3.0** (Manuel). Zmiany i rozszerzenia BTC: rheiCEO.
