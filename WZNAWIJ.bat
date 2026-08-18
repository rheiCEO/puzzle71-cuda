@echo off
cd /d "%~dp0"
title puzzle71-cuda — WZNOW od checkpointu
if not exist "bin\puzzle71-cuda.exe" (
    echo Brak bin\puzzle71-cuda.exe — uruchom najpierw build.bat
    pause
    exit /b 1
)
if not exist "puzzle71.progress" (
    echo Brak puzzle71.progress — uruchom najpierw SZUKAJ.bat
    pause
    exit /b 1
)
echo.
echo === WZNOWIENIE od puzzle71.progress ===
type puzzle71.progress
echo.
bin\puzzle71-cuda.exe --resume
pause
