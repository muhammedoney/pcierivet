@echo off
setlocal EnableExtensions
rem Create the local Cyclone 10 GX Quartus project.
rem   fpga\c10gx\create_project.cmd
rem Finds quartus_sh via QUARTUS_ROOTDIR, PATH, then
rem C:\intelFPGA_pro\<version> and C:\altera_pro\<version>.

set "SELF=%~nx0"
cd /d "%~dp0..\.."
if errorlevel 1 (
  echo ERROR: cannot cd to the repo root.
  call :pause_if_explorer
  exit /b 1
)

set "QSH="
if defined QUARTUS_ROOTDIR if exist "%QUARTUS_ROOTDIR%\bin64\quartus_sh.exe" (
  set "QSH=%QUARTUS_ROOTDIR%\bin64\quartus_sh.exe"
)
if not defined QSH if defined QUARTUS_ROOTDIR if exist "%QUARTUS_ROOTDIR%\quartus\bin64\quartus_sh.exe" (
  set "QSH=%QUARTUS_ROOTDIR%\quartus\bin64\quartus_sh.exe"
)
if not defined QSH call :pick_where quartus_sh.exe
if not defined QSH call :pick_where quartus_sh
if not defined QSH call :pick_tree "C:\intelFPGA_pro"
if not defined QSH call :pick_tree "C:\altera_pro"
if not defined QSH call :pick_tree "%ProgramFiles%\intelFPGA_pro"
if not defined QSH (
  echo ERROR: quartus_sh.exe not found.
  echo Set QUARTUS_ROOTDIR to the Quartus Prime Pro root
  echo ^(the folder that contains bin64\quartus_sh.exe^), or add quartus_sh to PATH.
  echo Also checked C:\intelFPGA_pro and C:\altera_pro.
  call :pause_if_explorer
  exit /b 1
)

echo Using %QSH%
call "%QSH%" -t "fpga\c10gx\create_project.tcl"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" call :pause_if_explorer
exit /b %RC%

:pick_where
for /f "delims=" %%P in ('where %1 2^>nul') do (
  if not defined QSH set "QSH=%%P"
)
goto :eof

:pick_tree
if not exist "%~1\" goto :eof
for /f "delims=" %%D in ('dir /b /ad /o-n "%~1" 2^>nul') do (
  if not defined QSH if exist "%~1\%%D\quartus\bin64\quartus_sh.exe" (
    set "QSH=%~1\%%D\quartus\bin64\quartus_sh.exe"
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
