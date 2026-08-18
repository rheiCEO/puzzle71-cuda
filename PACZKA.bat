@echo off
setlocal
set ROOT=%~dp0
set DIST=%ROOT%dist\puzzle71-cuda-win64

echo === Budowa paczki portable ===
call "%ROOT%build_release.bat"
if errorlevel 1 exit /b 1

if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%"

copy /y "%ROOT%bin\puzzle71-cuda.exe" "%DIST%\"
copy /y "%ROOT%SZUKAJ.bat" "%DIST%\"
copy /y "%ROOT%WZNAWIJ.bat" "%DIST%\"
copy /y "%ROOT%LOSOWO.bat" "%DIST%\"
copy /y "%ROOT%CZYTAJ-MNIE.txt" "%DIST%\"
copy /y "%ROOT%COOP.bat" "%DIST%\"
xcopy /y /e /i "%ROOT%coop" "%DIST%\coop\"

set ZIP=%ROOT%dist\puzzle71-cuda-win64.zip
if exist "%ZIP%" del "%ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%DIST%\*' -DestinationPath '%ZIP%' -Force"

echo.
echo GOTOWE:
echo   Folder: %DIST%
echo   ZIP:    %ZIP%
echo.
echo Wyslij koledze ZIP — rozpakowac i kliknac SZUKAJ.bat
exit /b 0
