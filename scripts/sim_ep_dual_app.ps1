# Copyright 2026 Rivet contributors
# Verilator: EP dual-app bus-master MemWr smoke

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MULTIDRIVEN -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY"
$Sources = "rtl/pcie_ctrl/rivet_pkg.sv rtl/pcie_ctrl/tl/rivet_tl_pio_app.sv rtl/pcie_ctrl/tl/rivet_tl_rq.sv tb/bfm/pg213_ep/rtl/rivet_ep_dual_app.sv tb/smoke/rivet_ep_dual_app_tb.sv --top-module rivet_ep_dual_app_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/ep_dual_app"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o ep_dual_app
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "ep_dual_app")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_ep_dual_app"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o ep_dual_app && $Out/ep_dual_app"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: ep_dual_app_tb" }
Write-Host "PASS: ep_dual_app_tb"
