# Copyright 2026 Rivet contributors
# Verilator: DL SM smoke

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD"
$Sources = @"
rtl/pcie_ctrl/rivet_pkg.sv
rtl/pcie_ctrl/dll/rivet_dll_sm.sv
tb/smoke/rivet_dll_sm_tb.sv
--top-module rivet_dll_sm_tb
"@ -replace "`r`n"," " -replace "`n"," "

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/dll_sm"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o dll_sm
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "dll_sm")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_dll_sm"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o dll_sm && $Out/dll_sm"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dll_sm_tb" }
Write-Host "PASS: dll_sm_tb"
