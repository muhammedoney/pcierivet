# Copyright 2026 Rivet contributors
# Verilator: DLL TLP + ACK through MAC STP/SDP

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT"
$Sources = "-f rtl/filelist_core.f tb/smoke/rivet_dll_mac_tlp_tb.sv --top-module rivet_dll_mac_tlp_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/dll_mac_tlp"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o dll_mac_tlp
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "dll_mac_tlp")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_dll_mac_tlp"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o dll_mac_tlp && $Out/dll_mac_tlp"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dll_mac_tlp_tb" }
Write-Host "PASS: dll_mac_tlp_tb"
