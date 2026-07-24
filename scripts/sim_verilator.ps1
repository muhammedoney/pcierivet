# Copyright 2026 Rivet contributors

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Out = Join-Path $Root "build\verilator_smoke"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

if (-not (Get-Command verilator -ErrorAction SilentlyContinue)) {
  Write-Error "verilator not found in PATH"
}

& verilator --cc --exe --build -Wall -Wno-DECLFILENAME -Wno-UNUSED `
  -f rtl/filelist_core.f `
  --top-module rivet_pcie_ctrl `
  -Mdir $Out `
  tb/smoke/verilator_smoke_main.cpp

Write-Host "PASS: Verilator smoke build"
