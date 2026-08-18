# Współpraca 3+ GPU (coop)

Każdy szuka **innego zakresu** — serwer online rozdaje bloki, bez nakładania.

## Architektura

```
  [Serwer online]  ←── status /status (JSON)
        │
   ┌────┼────┐
   ▼    ▼    ▼
 GPU1 GPU2 GPU3   (COOP.bat → worker.py → puzzle71-cuda.exe)
```

## Krok 1 — postaw serwer (1 osoba)

**Lokalnie (LAN):**
```bat
COOP-SERWER.bat
```
Koledzy łączą się: `http://TWOJE_IP_LAN:8765`

**Online (Internet):**
- VPS (np. Hetzner, Oracle Free) — `python coop/server.py`
- Tunel: [ngrok](https://ngrok.com) `ngrok http 8765` → dostaniesz URL `https://xxxx.ngrok.io`
- Otwórz port **8765** w firewallu routera (jeśli serwer u Ciebie)

Status dla wszystkich:
```
http://SERWER:8765/status
```

## Krok 2 — każdy uruchamia worker

```bat
COOP.bat http://SERWER:8765 Kuba
COOP.bat http://SERWER:8765 Ania
COOP.bat http://SERWER:8765 Michal
```

Worker:
1. Pyta serwer o następny wolny zakres (`POST /claim`)
2. Odpala `puzzle71-cuda.exe --start ... --end ...`
3. Po skończeniu zgłasza `POST /complete`
4. Bierze kolejny blok — aż cały puzzle rozdany lub **ZNALEZIONO**

## Co jest online

| Endpoint | Opis |
|----------|------|
| `GET /status` | postęp globalny, lista workerów, czy znaleziono |
| `POST /claim` | przydziel następny blok |
| `POST /complete` | blok skończony |
| `POST /found` | zgłoszenie klucza |

Baza: `coop/coop.db` (SQLite na serwerze) — **tu jest „kto co przeszukał”**.

Domyślny rozmiar bloku: **2³⁸ kluczy** (~274 mld, ~1–2 min na GPU 3B/s).  
Zmiana: `set PUZZLE71_CHUNK_BITS=40` przed startem serwera (większe bloki = mniej requestów).

## Wymagania

| Rola | Potrzebuje |
|------|------------|
| Serwer | Python 3 (bez CUDA) |
| Worker | Python 3 + `puzzle71-cuda.exe` + NVIDIA |

## Portable + coop

Po `PACZKA.bat` do ZIP dodaj folder `coop\` i `COOP.bat` — kolega dostaje wszystko.

## Bezpieczeństwo

Serwer **nie ma hasła** — używaj tylko w zaufanej grupie lub postaw za VPN / ngrok z tokenem (TODO).  
Nie wystawiaj publicznie bez zabezpieczeń na dłuższą metę.
