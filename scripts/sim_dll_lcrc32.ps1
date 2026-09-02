# Copyright 2026 Rivet contributors
# Verilator: LCRC-32 smoke

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD"
$Sources = @"
rtl/pcie_ctrl/rivet_pkg.sv
rtl/pcie_ctrl/dll/rivet_dll_lcrc32.sv
tb/smoke/rivet_dll_lcrc32_tb.sv
--top-module rivet_dll_lcrc32_tb
"@ -replace "`r`n"," " -replace "`n"," "

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/lcrc32"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o lcrc32
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "lcrc32")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_lcrc32"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o lcrc32 && $Out/lcrc32"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dll_lcrc32_tb" }
Write-Host "PASS: dll_lcrc32_tb"
