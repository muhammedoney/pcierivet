@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Synthesize the existing VCU118 project. Does not create it.
rem   fpga\vcu118\synth.cmd
rem Run fpga\vcu118\create_project.cmd first.
rem Finds vivado.bat via VIVADO_PATH, XILINX_VIVADO, PATH, then
rem C:\Xilinx\Vivado\<version> and Program Files\Xilinx\Vivado\<version>.

set "SELF=%~nx0"
cd /d "%~dp0..\.."
if errorlevel 1 (
  echo ERROR: cannot cd to the repo root.
  call :pause_if_explorer
  exit /b 1
)

set "RIVET_TCLARGS="
if "%~1"=="" goto :args_ok
if /I "%~1"=="4" if /I "%~2"=="ep" if "%~3"=="" (
  set "RIVET_TCLARGS=4 ep"
  goto :args_ok
)
echo Usage: %SELF% [4 ep]
call :pause_if_explorer
exit /b 1
:args_ok

set "LOG=fpga\vcu118\synth.log"
set "VIVADO_BAT="
if defined VIVADO_PATH if exist "%VIVADO_PATH%\bin\vivado.bat" (
  set "VIVADO_BAT=%VIVADO_PATH%\bin\vivado.bat"
)
if not defined VIVADO_BAT if defined XILINX_VIVADO if exist "%XILINX_VIVADO%\bin\vivado.bat" (
  set "VIVADO_BAT=%XILINX_VIVADO%\bin\vivado.bat"
)
if not defined VIVADO_BAT call :pick_where vivado.bat
if not defined VIVADO_BAT call :pick_where vivado
if not defined VIVADO_BAT call :pick_tree "C:\Xilinx\Vivado"
if not defined VIVADO_BAT call :pick_tree "D:\Xilinx\Vivado"
if not defined VIVADO_BAT call :pick_tree "%ProgramFiles%\Xilinx\Vivado"
if not defined VIVADO_BAT call :pick_tree "%ProgramFiles(x86)%\Xilinx\Vivado"
if not defined VIVADO_BAT (
  echo ERROR: vivado.bat not found.
  echo Set VIVADO_PATH or XILINX_VIVADO to the Vivado install root
  echo ^(the folder that contains bin\vivado.bat^), or add vivado.bat to PATH.
  echo Also checked C:\Xilinx\Vivado and Program Files\Xilinx\Vivado.
  call :pause_if_explorer
  exit /b 1
)

if defined RIVET_TCLARGS (
  set "XPR=fpga\vcu118\build\gen4_ep\rivet_vcu118.xpr"
) else (
  set "XPR=fpga\vcu118\build\rivet_vcu118.xpr"
)
if not exist "%XPR%" (
  echo ERROR: missing %XPR%
  echo Run create_project.cmd first. Synthesis is a separate script.
  call :pause_if_explorer
  exit /b 1
)

echo Using %VIVADO_BAT%
echo Log:   %LOG%
if defined RIVET_TCLARGS (
  call "%VIVADO_BAT%" -mode batch -source "fpga\vcu118\synth.tcl" -nojournal -log "%LOG%" -tclargs %RIVET_TCLARGS%
) else (
  call "%VIVADO_BAT%" -mode batch -source "fpga\vcu118\synth.tcl" -nojournal -log "%LOG%"
)
set "RC=!ERRORLEVEL!"
echo.
if not "%RC%"=="0" (
  echo FAILED with exit code %RC% - see %LOG%
  call :pause_if_explorer
) else (
  echo PASS: synth_1 complete. See %LOG%
)
exit /b %RC%

:pick_where
for /f "delims=" %%P in ('where %1 2^>nul') do (
  if not defined VIVADO_BAT set "VIVADO_BAT=%%P"
)
goto :eof

:pick_tree
if not exist "%~1\" goto :eof
for /f "delims=" %%D in ('dir /b /ad /o-n "%~1" 2^>nul') do (
  if not defined VIVADO_BAT if exist "%~1\%%D\bin\vivado.bat" (
    set "VIVADO_BAT=%~1\%%D\bin\vivado.bat"
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
