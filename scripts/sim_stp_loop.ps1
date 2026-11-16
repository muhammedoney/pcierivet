# Copyright 2026 Rivet contributors
# Verilator: MAC STP ×4 framing loopback + EDB

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY -Wno-PINMISSING -Wno-GENUNNAMED -Wno-fatal"
$Inc = "+incdir+rtl/pcie_ctrl +incdir+third_party/ref/common_cells/include"
$Sources = "-f rtl/filelist_core.f tb/smoke/rivet_mac_stp_loop_tb.sv --top-module rivet_mac_stp_loop_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/stp_loop"
  & verilator --binary $Warn.Split(" ") $Inc.Split(" ") $Sources.Split(" ") -Mdir $Out -o stp_loop
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "stp_loop")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_stp_loop"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Inc $Sources -Mdir $Out -o stp_loop && $Out/stp_loop"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: stp_loop_tb" }
Write-Host "PASS: stp_loop_tb"
