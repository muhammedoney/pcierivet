# Copyright 2026 Rivet contributors
# Verilator: DLLP TX/RX round-trip

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD"
$Sources = "rtl/pcie_ctrl/rivet_pkg.sv rtl/pcie_ctrl/dll/rivet_dll_crc16.sv rtl/pcie_ctrl/dll/rivet_dllp_tx.sv rtl/pcie_ctrl/dll/rivet_dllp_rx.sv tb/smoke/rivet_dllp_roundtrip_tb.sv --top-module rivet_dllp_roundtrip_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/dllp_rt"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o dllp_rt
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "dllp_rt")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_dllp_rt"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o dllp_rt && $Out/dllp_rt"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dllp_roundtrip_tb" }
Write-Host "PASS: dllp_roundtrip_tb"
