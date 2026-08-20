@echo off

cd /d "%~dp0"

title puzzle71 — panel lokalny 1 GPU

python --version >nul 2>&1

if errorlevel 1 (

    echo Potrzebny Python 3 — tylko do panelu HTML.

    echo https://www.python.org/downloads/

    pause

    exit /b 1

)

echo.

echo === Panel lokalny Puzzle #71 (1 GPU) ===

echo   http://127.0.0.1:8769/

echo.

echo Checkpointy z vast: logs\gpu0.progress .. gpu7.progress

echo Start / Stop z przegladarki.

echo.

python watch_local.py

pause

