@echo off
cd /d "%~dp0"
title puzzle71-cuda — Puzzle #71 (losowo)
if not exist "bin\puzzle71-cuda.exe" (
    echo Brak bin\puzzle71-cuda.exe — uruchom najpierw build.bat
    pause
    exit /b 1
)
echo.
echo === puzzle71-cuda — tryb LOSOWY w zakresie Puzzle #71 ===
echo.
bin\puzzle71-cuda.exe --mode random
pause
