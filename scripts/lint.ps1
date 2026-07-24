# Copyright 2026 Rivet contributors
# Verilator lint of rivet_pcie_ctrl (Windows PowerShell)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if (-not (Get-Command verilator -ErrorAction SilentlyContinue)) {
  Write-Error "verilator not found in PATH"
}

& verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSED `
  -f rtl/filelist_core.f `
  --top-module rivet_pcie_ctrl

Write-Host "PASS: Verilator lint (controller)"
