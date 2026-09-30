# Copyright 2026 Rivet contributors
# Verilator smoke: rivet_pcie_ctrl LTSSM must reach L0 against a PIPE peer.
# Uses a native verilator when present, otherwise the WSL one.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Lanes = if ($args.Count -ge 1) { $args[0] } else { 1 }
$PeerLanes = if ($args.Count -ge 2) { $args[1] } else { $Lanes }
$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-fatal"
$Inc = "+incdir+third_party/ref/common_cells/include"
$Sources = "-f rtl/filelist_core.f tb/smoke/rivet_ltssm_smoke_tb.sv --top-module rivet_ltssm_smoke_tb"

if (Get-Command verilator -ErrorAction SilentlyContinue) {
  $Out = Join-Path $Root "build/ltssm_smoke"
  & verilator --binary $Warn.Split(" ") $Inc $Sources.Split(" ") `
    "-DRIVET_SMOKE_LANES=$Lanes" "-DRIVET_SMOKE_PEER_LANES=$PeerLanes" -Mdir $Out -o ltssm_smoke
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: build" }
  & (Join-Path $Out "ltssm_smoke")
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: LANES=$Lanes PEER=$PeerLanes did not reach L0" }
} else {
  $WslRoot = (wsl wslpath -a ($Root -replace '\\', '/'))
  $Out = "/tmp/rivet_ltssm_smoke_x${Lanes}_p${PeerLanes}"
  wsl -e bash -lc "cd '$WslRoot' && rm -rf $Out && verilator --binary $Warn $Inc $Sources -DRIVET_SMOKE_LANES=$Lanes -DRIVET_SMOKE_PEER_LANES=$PeerLanes -Mdir $Out -o ltssm_smoke && $Out/ltssm_smoke"
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: LANES=$Lanes PEER=$PeerLanes did not reach L0" }
}

Write-Host "PASS: LTSSM smoke (LANES=$Lanes PEER_LANES=$PeerLanes)"
