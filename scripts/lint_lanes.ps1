# Copyright 2026 Rivet contributors
# Verilator lint of rivet_pcie_ctrl across the supported lane counts.
# Uses a native verilator when present, otherwise the WSL one.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Args = "--lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSED -f rtl/filelist_core.f --top-module rivet_pcie_ctrl"
$Native = Get-Command verilator -ErrorAction SilentlyContinue

foreach ($Lanes in 1, 2, 4) {
  Write-Host "=== LANES=$Lanes ==="
  if ($Native) {
    & verilator $Args.Split(" ") "-GLANES=$Lanes"
  } else {
    $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
    wsl -e bash -lc "cd '$WslRoot' && verilator $Args -GLANES=$Lanes"
  }
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: LANES=$Lanes" }
  Write-Host "PASS: LANES=$Lanes"
}

Write-Host "PASS: Verilator lint (controller, x1/x2/x4)"
