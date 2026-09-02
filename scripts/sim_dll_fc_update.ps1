# Copyright 2026 Rivet contributors
# Verilator: dual-DLL UpdateFC after credit free

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY"
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
rtl/pcie_ctrl/dll/rivet_dll_tl_pack.sv
rtl/pcie_ctrl/dll/rivet_dll_tl_unpack.sv
rtl/pcie_ctrl/dll/rivet_dll.sv
rtl/pcie_ctrl/tl/rivet_tl_fc_stub.sv
tb/smoke/rivet_dll_fc_update_tb.sv
--top-module rivet_dll_fc_update_tb
"@ -replace "`r`n"," " -replace "`n"," "

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/fc_update"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o fc_update
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "fc_update")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_fc_update"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o fc_update && $Out/fc_update"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dll_fc_update_tb" }
Write-Host "PASS: dll_fc_update_tb"
