@echo off
cd /d "%~dp0"
title puzzle71 — dashboard postepu
python --version >nul 2>&1
if errorlevel 1 (
    echo Potrzebny Python 3 — tylko do podgladu HTML, nie do szukania.
    echo https://www.python.org/downloads/
    pause
    exit /b 1
)
echo Otwieram dashboard w przegladarce...
echo Szukanie odpal osobno: SZUKAJ.bat / WZNAWIJ.bat
echo.
python watch_progress.py
pause
