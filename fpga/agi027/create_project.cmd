@echo off
setlocal EnableExtensions
rem Create the local DK-DEV-AGI027-RA-B Quartus project.
rem   fpga\agi027\create_project.cmd
rem Finds quartus_sh.exe via QUARTUS_ROOTDIR, PATH, then
rem D:\altera_pro\<version>\quartus\bin64.

set "SELF=%~nx0"
cd /d "%~dp0..\.."
if errorlevel 1 (
  echo ERROR: cannot cd to the repo root.
  call :pause_if_explorer
  exit /b 1
)

if not "%~1"=="" (
  echo Usage: %SELF%
  call :pause_if_explorer
  exit /b 1
)

set "QUARTUS_SH="
if defined QUARTUS_ROOTDIR if exist "%QUARTUS_ROOTDIR%\bin64\quartus_sh.exe" (
  set "QUARTUS_SH=%QUARTUS_ROOTDIR%\bin64\quartus_sh.exe"
)
if not defined QUARTUS_SH call :pick_where quartus_sh.exe
if not defined QUARTUS_SH call :pick_where quartus_sh
if not defined QUARTUS_SH call :pick_tree "D:\altera_pro"
if not defined QUARTUS_SH (
  echo ERROR: quartus_sh.exe not found.
  echo Set QUARTUS_ROOTDIR to the Quartus install root
  echo ^(the folder that contains bin64\quartus_sh.exe^), or add it to PATH.
  call :pause_if_explorer
  exit /b 1
)

echo Using %QUARTUS_SH%
call "%QUARTUS_SH%" -t "fpga\agi027\create_project.tcl"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" call :pause_if_explorer
exit /b %RC%

:pick_where
for /f "delims=" %%P in ('where %1 2^>nul') do (
  if not defined QUARTUS_SH set "QUARTUS_SH=%%P"
)
goto :eof

:pick_tree
if not exist "%~1\" goto :eof
for /f "delims=" %%D in ('dir /b /ad /o-n "%~1" 2^>nul') do (
  if not defined QUARTUS_SH if exist "%~1\%%D\quartus\bin64\quartus_sh.exe" (
    set "QUARTUS_SH=%~1\%%D\quartus\bin64\quartus_sh.exe"
  )
)
goto :eof

:pause_if_explorer
if /I "%RIVET_NO_PAUSE%"=="1" goto :eof
echo %CMDCMDLINE% | findstr /i /c:"/c" | findstr /i /c:"%SELF%" >nul
if errorlevel 1 goto :eof
echo.
echo Press any key to close.
pause >nul
goto :eof
