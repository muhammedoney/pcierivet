# Copyright 2026 Rivet contributors
# Verilator: CQ/CC Mem32 PIO loopback

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MULTIDRIVEN -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY"
$Sources = "rtl/pcie_ctrl/rivet_pkg.sv rtl/pcie_ctrl/tl/rivet_tl_cq.sv rtl/pcie_ctrl/tl/rivet_tl_cc.sv rtl/pcie_ctrl/tl/rivet_tl_pio_app.sv tb/smoke/rivet_tl_cq_cc_tb.sv --top-module rivet_tl_cq_cc_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/tl_cq_cc"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o tl_cq_cc
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "tl_cq_cc")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_tl_cq_cc"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o tl_cq_cc && $Out/tl_cq_cc"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: tl_cq_cc_tb" }
Write-Host "PASS: tl_cq_cc_tb"
