#Requires -Version 5.1
<#
.SYNOPSIS
  Compile Vivado simulation libraries for Questa (needed by PG239 BFM sim).

.DESCRIPTION
  Runs compile_simlib for UltraScale+ into RIVET_QUESTA_SIMLIB (or default under
  the pcie_phy_0_ex cache). Can take a long time (tens of minutes).
#>
param(
  [string]$Family = "virtexuplus"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$LocalPaths = Join-Path $RepoRoot "scripts\local_paths.ps1"
if (Test-Path $LocalPaths) { . $LocalPaths }

if (-not $env:QUESTA_HOME) { $env:QUESTA_HOME = "C:\questasim64_2024.1" }
if (-not $env:RIVET_PG239_EX) { $env:RIVET_PG239_EX = "C:\Users\tosba\vivado\pcie_phy_0_ex" }
if (-not $env:RIVET_QUESTA_SIMLIB) {
  $env:RIVET_QUESTA_SIMLIB = Join-Path $env:RIVET_PG239_EX "pcie_phy_0_ex.cache\compile_simlib\questa"
}
if (-not $env:XILINX_VIVADO) {
  $env:XILINX_VIVADO = "C:\Xilinx\Vivado\2024.2"
}

$VivadoBat = Join-Path $env:XILINX_VIVADO "bin\vivado.bat"
if (-not (Test-Path $VivadoBat)) {
  Write-Error "vivado.bat not found at $VivadoBat — set XILINX_VIVADO in local_paths.ps1"
  exit 1
}

$SimLibUnix = ($env:RIVET_QUESTA_SIMLIB -replace '\\', '/')
$QuestaUnix = ("$env:QUESTA_HOME\win64" -replace '\\', '/')
$Tcl = Join-Path $env:RIVET_PG239_EX "compile_simlib_questa.tcl"
$Log = Join-Path $env:RIVET_PG239_EX "compile_simlib_questa.log"

New-Item -ItemType Directory -Force -Path $env:RIVET_QUESTA_SIMLIB | Out-Null

$tclBody = @"
set simlib_dir {$SimLibUnix}
set questa_exec {$QuestaUnix}
file mkdir `$simlib_dir
compile_simlib \
  -simulator questa \
  -simulator_exec_path `$questa_exec \
  -family $Family \
  -language verilog \
# Skip bloated IP-catalog compile; behavioral PG239 needs these only.
  -library unisim \
  -library unimacro \
  -library secureip \
  -dir `$simlib_dir \
  -force \
  -verbose
puts "RIVET: compile_simlib finished -> `$simlib_dir"
exit
"@
Set-Content -Path $Tcl -Value $tclBody -Encoding ASCII

Write-Host "Compiling simlib -> $($env:RIVET_QUESTA_SIMLIB)"
Write-Host "Log: $Log"
& $VivadoBat -mode batch -source $Tcl -log $Log -journal ($Log -replace '\.log$', '.jou')
if ($LASTEXITCODE -ne 0) {
  Write-Error "compile_simlib failed — see $Log"
  exit $LASTEXITCODE
}
if (-not (Test-Path (Join-Path $env:RIVET_QUESTA_SIMLIB "modelsim.ini"))) {
  Write-Error "modelsim.ini still missing after compile_simlib"
  exit 1
}
Write-Host "OK: modelsim.ini present."
