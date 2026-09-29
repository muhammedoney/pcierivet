# Copyright 2026 Rivet contributors
# Verilator: RQ pack + RC unpack smoke

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MULTIDRIVEN -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-PINCONNECTEMPTY"
$Sources = "rtl/pcie_ctrl/rivet_pkg.sv rtl/pcie_ctrl/tl/rivet_tl_rq.sv rtl/pcie_ctrl/tl/rivet_tl_rc.sv tb/smoke/rivet_tl_rq_rc_tb.sv --top-module rivet_tl_rq_rc_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/tl_rq_rc"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") -Mdir $Out -o tl_rq_rc
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "tl_rq_rc")
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_tl_rq_rc"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -Mdir $Out -o tl_rq_rc && $Out/tl_rq_rc"
}
if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: tl_rq_rc_tb" }
Write-Host "PASS: tl_rq_rc_tb"
