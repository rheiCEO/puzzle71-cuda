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
    echo BLAD: Ustaw CUDA_PATH lub zainstaluj CUDA Toolkit
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
    echo BLAD: Brak MSVC (Visual Studio Build Tools)
    exit /b 1
)

call "%VCVARS%"
if errorlevel 1 exit /b 1

echo Kompilacja puzzle71-cuda (%CUDA_PATH%)...
"%CUDA_PATH%\bin\nvcc.exe" -o "%OUT%\puzzle71-cuda.exe" ^
    "%SRC%\puzzle_main.cu" -I"%SRC%" ^
    -std=c++17 -O3 -arch=native ^
    --expt-relaxed-constexpr -allow-unsupported-compiler ^
    -Xcompiler "/EHsc /W3"

if errorlevel 1 exit /b 1
echo Gotowe: %OUT%\puzzle71-cuda.exe
exit /b 0
