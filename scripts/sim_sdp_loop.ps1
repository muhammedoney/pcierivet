# Copyright 2026 Rivet contributors
# Verilator: MAC SDP ×1 framing loopback

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD"
$Sources = "-f rtl/filelist_core.f tb/smoke/rivet_mac_sdp_loop_tb.sv --top-module rivet_mac_sdp_loop_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/sdp_loop"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o sdp_loop
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "sdp_loop")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_sdp_loop"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o sdp_loop && $Out/sdp_loop"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: sdp_loop_tb" }
Write-Host "PASS: sdp_loop_tb"
