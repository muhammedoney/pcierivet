@echo off
REM Pack Rivet sources for copy to a machine with a Vivado license.
REM Does not create a project and does not run synthesis.
REM   fpga\vcu118\pack_transfer.cmd
REM   fpga\vcu118\pack_transfer.cmd -OutDir D:\bags
REM Double-click safe: pause so the zip path stays visible.
setlocal
cd /d "%~dp0"
set "SCRIPT=%~dp0pack_transfer.ps1"
if not exist "%SCRIPT%" (
  echo ERROR: missing %SCRIPT%
  pause
  exit /b 1
)
echo Running pack_transfer.ps1 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" (
  echo FAILED with exit code %ERR%
) else (
  echo Done.
)
pause
exit /b %ERR%
