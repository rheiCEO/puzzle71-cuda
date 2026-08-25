@echo off

cd /d "%~dp0"

title puzzle71-cuda — Puzzle #71 prefiks 74 (losowo)

if not exist "bin\puzzle71-cuda.exe" (

    echo Brak bin\puzzle71-cuda.exe — uruchom najpierw build.bat

    pause

    exit /b 1

)

set START=740000000000000000

set END=74ffffffffffffffff

echo.

echo === puzzle71-cuda — tryb LOSOWY, prefiks klucza 74 ===

echo Zakres: %START% .. %END%

echo.

bin\puzzle71-cuda.exe --mode random --start %START% --end %END%

pause

