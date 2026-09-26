# Copyright 2026 Rivet contributors
# Verilator: MAC STP ×4 framing loopback + EDB

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY"
$Sources = "-f rtl/filelist_core.f tb/smoke/rivet_mac_stp_loop_tb.sv --top-module rivet_mac_stp_loop_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/stp_loop"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o stp_loop
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "stp_loop")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_stp_loop"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o stp_loop && $Out/stp_loop"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: stp_loop_tb" }
Write-Host "PASS: stp_loop_tb"
