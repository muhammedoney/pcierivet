# Copyright 2026 Rivet contributors
# Verilator: replay buffer ACK purge / NAK replay

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD -Wno-UNOPTFLAT"
$Sources = @"
rtl/pcie_ctrl/rivet_pkg.sv
rtl/pcie_ctrl/dll/rivet_dll_replay.sv
tb/smoke/rivet_dll_replay_tb.sv
--top-module rivet_dll_replay_tb
"@ -replace "`r`n"," " -replace "`n"," "

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/dll_replay"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o dll_replay
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "dll_replay")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_dll_replay"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o dll_replay && $Out/dll_replay"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: dll_replay_tb" }
Write-Host "PASS: dll_replay_tb"
