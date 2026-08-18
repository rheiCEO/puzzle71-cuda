@echo off
cd /d "%~dp0"
title puzzle71-coop SERWER
echo Uruchamiam serwer koordynacji na porcie 8765...
echo.
echo Koledzy lacza sie:
echo   COOP.bat http://TWOJE_IP:8765 Imie
echo.
echo Status w przegladarce:
echo   http://127.0.0.1:8765/status
echo.
python coop\server.py --host 0.0.0.0 --port 8765
pause
