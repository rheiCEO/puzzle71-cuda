@echo off

cd /d "%~dp0"

title puzzle71-cuda — Puzzle #71 prefiks 74 (sekwencyjnie)

if not exist "bin\puzzle71-cuda.exe" (

    echo Brak bin\puzzle71-cuda.exe — uruchom najpierw build.bat

    pause

    exit /b 1

)

set START=400000000000000000

set END=7fffffffffffffffff

echo.

echo === puzzle71-cuda — tryb SEKWENCYJNY, prefiks klucza 74 ===

echo Zakres: %START% .. %END%

echo Checkpoint: puzzle71.progress

echo.

bin\puzzle71-cuda.exe --mode sequential --start %START% --end %END%

pause

