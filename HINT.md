# Wskazówka P71 — okolice `63aae5ee8189877712`

## Hipoteza

Klucz Puzzle #71 może leżeć **w sąsiedztwie**:

```
63aae5ee8189877712
```

Sam ten klucz **nie** rozwiązuje puzzle (adres z niego: `1DRKcxrGojszJqDKnncMeqNzLNxpbPZTn5` ≠ target).
To punkt odniesienia do zawężonego skanu, nie gotowa odpowiedź.

Target: `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU`

## Okna wokół wskazówki

| Okno | Zakres (hex) | Rozmiar | ~czas @ 3 GKey/s (1 GPU) |
|------|--------------|---------|---------------------------|
| ±2³¹ | `63aae5ee8109…` … `63aae5ee8209…` | ~4e9 | ~1 s |
| ±2⁴⁰ | `63aae5ed8189…` … `63aae5ef8189…` | ~2e12 | ~12 min |
| **±2⁴⁸ (domyślne)** | `63aae4ee8189…` … `63aae6ee8189…` | ~5.6e14 | ~2 dni |
| ±2⁵⁶ | `63aa65ee8189…` … `63ab65ee8189…` | ~7e16 | ~270 dni |

## Vast.ai — hunt wokół hint

```bash
curl -fsSL https://raw.githubusercontent.com/rheiCEO/puzzle71-cuda/master/vast-setup.sh | bash
cd /workspace/puzzle71-cuda

export TELEGRAM_BOT_TOKEN='...'
export TELEGRAM_CHAT_ID='...'
export HALF_BITS=48          # okno ±2^47 wokół hint
export WORK_SCALE=16

chmod +x vast-start-hint.sh
bash vast-start-hint.sh
```

Większe okno:

```bash
HALF_BITS=56 bash vast-start-hint.sh
```

Ręcznie (losowo w oknie ±2^40):

```bash
export START_HEX=63aae5ed8189877712
export END_HEX=63aae5ef8189877711
bash vast-start.sh
```

## Lokalnie (1 GPU)

```bat
bin\puzzle71-cuda.exe --mode sequential --start 63aae4ee8189877712 --end 63aae6ee8189877711
```

## Uwaga

To nadal **heurystyka**. Bez dowodu, że wskazówka jest prawdziwa, pełny prefiks `63…` (2⁶⁴) pozostaje bezpieczniejszym (i dużo większym) zakresem.
