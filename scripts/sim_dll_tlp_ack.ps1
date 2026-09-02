# Copyright 2026 Rivet contributors
# Verilator: dual-DLL TLP + ACK / NAK replay

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-MULTIDRIVEN"
$Sources = @"
rtl/pcie_ctrl/rivet_pkg.sv
rtl/pcie_ctrl/dll/rivet_dll_crc16.sv
rtl/pcie_ctrl/dll/rivet_dll_lcrc32.sv
rtl/pcie_ctrl/dll/rivet_dllp_tx.sv
rtl/pcie_ctrl/dll/rivet_dllp_rx.sv
rtl/pcie_ctrl/dll/rivet_dll_fc.sv
rtl/pcie_ctrl/dll/rivet_dll_sm.sv
rtl/pcie_ctrl/dll/rivet_dll_replay.sv
rtl/pcie_ctrl/dll/rivet_dll_tlp_tx.sv
rtl/pcie_ctrl/dll/rivet_dll_tlp_rx.sv
rtl/pcie_ctrl/dll/rivet_dll.sv
rtl/pcie_ctrl/tl/rivet_tl_fc_stub.sv
tb/smoke/rivet_dll_tlp_ack_tb.sv
--top-module rivet_dll_tlp_ack_tb
"@ -replace "`r`n"," " -replace "`n"," "

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/tlp_ack"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o tlp_ack
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "tlp_ack")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_tlp_ack"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o tlp_ack && $Out/tlp_ack"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dll_tlp_ack_tb" }
Write-Host "PASS: dll_tlp_ack_tb"
