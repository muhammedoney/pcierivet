# Copyright 2026 Rivet contributors
# Verilator: Type 0 Cfg / Cpl

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MULTIDRIVEN -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY"
$Sources = "-f rtl/filelist_core.f tb/smoke/rivet_tl_cfg_tb.sv --top-module rivet_tl_cfg_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/tl_cfg"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o tl_cfg
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "tl_cfg")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_tl_cfg"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o tl_cfg && $Out/tl_cfg"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: tl_cfg_tb" }
Write-Host "PASS: tl_cfg_tb"
