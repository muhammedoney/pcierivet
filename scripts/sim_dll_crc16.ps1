# Copyright 2026 Rivet contributors
# Verilator: DLLP CRC16 directed TB

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD"
$Sources = "rtl/pcie_ctrl/rivet_pkg.sv rtl/pcie_ctrl/dll/rivet_dll_crc16.sv tb/smoke/rivet_dll_crc16_tb.sv --top-module rivet_dll_crc16_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/dll_crc16"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o dll_crc16
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "dll_crc16")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_dll_crc16"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o dll_crc16 && $Out/dll_crc16"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dll_crc16_tb" }
Write-Host "PASS: dll_crc16_tb"
