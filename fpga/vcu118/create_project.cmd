@echo off
setlocal EnableExtensions
rem Create the local VCU118 Vivado project by running create_project.tcl.
rem   fpga\vcu118\create_project.cmd
rem   fpga\vcu118\create_project.cmd synth
rem Optional: set VIVADO_PATH to the Vivado install root (the folder that contains bin\vivado.bat).

cd /d "%~dp0..\.."
if errorlevel 1 (
  echo ERROR: cannot cd to the repo root.
  exit /b 1
)

if /I not "%~1"=="" if /I not "%~1"=="synth" (
  echo Usage: %~nx0 [synth]
  exit /b 1
)

set "VIVADO_BAT="
if defined VIVADO_PATH if exist "%VIVADO_PATH%\bin\vivado.bat" (
  set "VIVADO_BAT=%VIVADO_PATH%\bin\vivado.bat"
)
if not defined VIVADO_BAT (
  where vivado.bat >nul 2>&1 && set "VIVADO_BAT=vivado.bat"
)
if not defined VIVADO_BAT (
  where vivado >nul 2>&1 && set "VIVADO_BAT=vivado"
)
if not defined VIVADO_BAT (
  for /d %%D in ("%ProgramFiles%\Xilinx\Vivado\*") do (
    if exist "%%~D\bin\vivado.bat" set "VIVADO_BAT=%%~D\bin\vivado.bat"
  )
)
if not defined VIVADO_BAT (
  echo ERROR: vivado.bat not found. Add Vivado to PATH or set VIVADO_PATH.
  exit /b 1
)

echo Using %VIVADO_BAT%
if /I "%~1"=="synth" (
  call "%VIVADO_BAT%" -mode batch -source "fpga\vcu118\create_project.tcl" -tclargs synth
) else (
  call "%VIVADO_BAT%" -mode batch -source "fpga\vcu118\create_project.tcl"
)
exit /b %ERRORLEVEL%
