@echo off
setlocal
set ROOT=%~dp0
set OUT=%ROOT%bin
set SRC=%ROOT%src

if not exist "%OUT%" mkdir "%OUT%"

if "%CUDA_PATH%"=="" (
    if exist "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1" (
        set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1"
    ) else if exist "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6" (
        set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
    )
)
if "%CUDA_PATH%"=="" (
    echo BLAD: Brak CUDA Toolkit — potrzebny tylko TOBIE do kompilacji paczki.
    exit /b 1
)

set VCVARS=
if exist "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
    set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
    set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
    set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
)
if "%VCVARS%"=="" (
    echo BLAD: Brak MSVC
    exit /b 1
)

call "%VCVARS%"
if errorlevel 1 exit /b 1

REM RTX 20xx=sm_75, RTX 30xx=sm_86, RTX 40xx=sm_89, RTX 50xx=sm_120
set "ARCH=-gencode=arch=compute_75,code=sm_75 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_120,code=sm_120"

echo Kompilacja PORTABLE (%CUDA_PATH%)...
echo Architektury: sm_75 sm_86 sm_89 sm_120
"%CUDA_PATH%\bin\nvcc.exe" -o "%OUT%\puzzle71-cuda.exe" ^
    "%SRC%\puzzle_main.cu" -I"%SRC%" ^
    -std=c++17 -O3 %ARCH% ^
    --expt-relaxed-constexpr -allow-unsupported-compiler ^
    -Xcompiler "/EHsc /W3" bcrypt.lib

if errorlevel 1 exit /b 1
echo OK: %OUT%\puzzle71-cuda.exe  (portable, bez CUDA Toolkit u uzytkownika)
exit /b 0
