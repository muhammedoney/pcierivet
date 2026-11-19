@echo off
setlocal EnableExtensions
rem Compile the existing Agilex project through assembly.
rem   fpga\agi027\impl.cmd
rem Run fpga\agi027\create_project.cmd first.
rem This script does not redirect Quartus stdout.
rem Messages print in this console. Quartus writes under fpga\agi027\build.

set "SELF=%~nx0"
cd /d "%~dp0..\.."
if errorlevel 1 (
  echo ERROR: cannot cd to the repo root.
  call :pause_if_explorer
  exit /b 1
)

if not "%~1"=="" (
  echo Usage: %SELF%
  echo Create the project first with create_project.cmd
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

if not exist "fpga\agi027\build\rivet_agi027.qpf" (
  echo ERROR: missing fpga\agi027\build\rivet_agi027.qpf
  echo Run create_project.cmd first.
  call :pause_if_explorer
  exit /b 1
)

echo Using %QUARTUS_SH%
call "%QUARTUS_SH%" -t "fpga\agi027\impl.tcl"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo FAILED with exit code %RC%
  call :pause_if_explorer
) else (
  echo PASS: Quartus compile. See fpga\agi027\build
)
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
