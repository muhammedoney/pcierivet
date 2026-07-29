# Copyright 2026 Rivet contributors
# Verilator smoke: rivet_pcie_ctrl LTSSM must reach L0 against a PIPE peer.
# Uses a native verilator when present, otherwise the WSL one.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Lanes = if ($args.Count -ge 1) { $args[0] } else { 1 }
$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD"
$Sources = "-f rtl/filelist_core.f tb/smoke/rivet_ltssm_smoke_tb.sv --top-module rivet_ltssm_smoke_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/ltssm_smoke"
  & verilator --binary $Warn.Split(" ") $Sources.Split(" ") `
    "-DRIVET_SMOKE_LANES=$Lanes" -Mdir $Out -o ltssm_smoke
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "ltssm_smoke")
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: LANES=$Lanes did not reach L0" }
} else {
  # Build inside the WSL filesystem; /mnt/c cannot host the generated objects.
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_ltssm_smoke_x$Lanes"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Sources -DRIVET_SMOKE_LANES=$Lanes -Mdir $Out -o ltssm_smoke && $Out/ltssm_smoke"
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: LANES=$Lanes did not reach L0" }
}

Write-Host "PASS: LTSSM smoke (LANES=$Lanes)"
