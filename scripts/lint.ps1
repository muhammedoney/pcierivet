# Copyright 2026 Rivet contributors
# Verilator lint of rivet_pcie_ctrl (Windows PowerShell)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-GENUNNAMED -Wno-PROCASSINIT -Wno-INITIALDLY"
$Inc = "+incdir+third_party/ref/common_cells/include"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  & verilator --lint-only $Warn.Split(" ") $Inc -f rtl/filelist_core.f --top-module rivet_pcie_ctrl
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: lint" }
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  wsl -e bash -lc "cd '$WslRoot' && verilator --lint-only $Warn $Inc -f rtl/filelist_core.f --top-module rivet_pcie_ctrl"
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: lint" }
}
Write-Host "PASS: Verilator lint (controller)"
