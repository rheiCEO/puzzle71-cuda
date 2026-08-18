@echo off
cd /d "%~dp0"
title puzzle71-cuda — Puzzle #71 (sekwencyjnie)
if not exist "bin\puzzle71-cuda.exe" (
    echo Brak bin\puzzle71-cuda.exe — uruchom najpierw build.bat
    pause
    exit /b 1
)
echo.
echo === puzzle71-cuda — tryb SEKWENCYJNY ===
echo Zakres: 40000000000000000 .. 7ffffffffffffffff
echo Checkpoint: puzzle71.progress
echo.
bin\puzzle71-cuda.exe --mode sequential
pause
