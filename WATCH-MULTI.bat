@echo off

cd /d "%~dp0"

title puzzle71 — dashboard multi-GPU

python --version >nul 2>&1

if errorlevel 1 (

    echo Potrzebny Python 3 — tylko do podgladu HTML.

    pause

    exit /b 1

)

echo Dashboard sumy GPU — logs\gpu*.progress

echo Szukanie: run-all-gpus.sh / vast

echo.

python watch_multi.py --logs logs

pause

