@echo off
setlocal
cd /d "%~dp0"

if "%~1"=="" (
    echo.
    echo COOP — wspolne szukanie online (3+ GPU)
    echo.
    echo Uzycie:
    echo   COOP.bat URL TWOJA_NAZWA
    echo.
    echo Przyklad:
    echo   COOP.bat http://192.168.1.10:8765 Kuba
    echo   COOP.bat https://twoj-serwer.pl:8765 Ania
    echo.
    pause
    exit /b 1
)

if not exist "bin\puzzle71-cuda.exe" (
    echo Brak bin\puzzle71-cuda.exe
    pause
    exit /b 1
)

python --version >nul 2>&1
if errorlevel 1 (
    echo Python 3 wymagany dla COOP (python.org — tylko worker, nie CUDA)
    pause
    exit /b 1
)

title puzzle71-coop %~2
python coop\worker.py %1 %2
pause
