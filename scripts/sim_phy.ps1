# Copyright 2026 Rivet contributors
# Verilator unit bench for the soft PHY PCS.
param(
  [ValidateSet("reset", "8b10b", "eb", "cmd", "gen3", "gen4", "eq", "x4", "all")]
  [string]$Case = "reset",
  [int]$Width = 0
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Invoke-PhyCase([string]$Name, [int]$W) {
  $Define = switch ($Name) {
    "reset" { "CASE_RESET" }
    "8b10b" { "CASE_8B10B" }
    "eb"    { "CASE_EB" }
    "cmd"   { "CASE_CMD" }
    "gen3"  { "CASE_GEN3" }
    "gen4"  { "CASE_GEN4" }
    "eq"    { "CASE_EQ" }
    "x4"    { "CASE_X4" }
    default { throw "unknown case $Name" }
  }
  $Out = Join-Path $Root "build\phy\$Name"
  if ($W -gt 0) { $Out = Join-Path $Root "build\phy\${Name}_w$W" }
  New-Item -ItemType Directory -Force -Path $Out | Out-Null

  $WidthDef = ""
  if ($W -gt 0) { $WidthDef = "+define+PHY_WIDTH=$W" }

  $Warn = "-Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-SYNCASYNCNET"
  $Lint = "verilator --binary --timing $Warn +define+$Define $WidthDef -f rtl/phy/filelist_phy.f rtl/pcie_ctrl/rivet_pkg.sv tb/phy/rivet_phy_pcs_tb.sv --top-module rivet_phy_pcs_tb --Mdir '$($Out -replace '\\','/')'"

  $WslRoot = $Root
  if ($WslRoot -match '^([A-Za-z]):\\(.*)$') {
    $WslRoot = "/mnt/$($Matches[1].ToLower())/$($Matches[2] -replace '\\','/')"
  }
  $Mdir = $Out
  if ($Mdir -match '^([A-Za-z]):\\(.*)$') {
    $Mdir = "/mnt/$($Matches[1].ToLower())/$($Matches[2] -replace '\\','/')"
  }
  $Inc = "+incdir+rtl/pcie_ctrl"
  $Cmd = "cd '$WslRoot' && verilator --binary --timing $Warn +define+$Define $WidthDef $Inc -f rtl/phy/filelist_phy.f rtl/pcie_ctrl/rivet_pkg.sv tb/phy/rivet_phy_pcs_tb.sv --top-module rivet_phy_pcs_tb --Mdir '$Mdir' && '$Mdir/Vrivet_phy_pcs_tb'"

  if (Get-Command verilator -ErrorAction SilentlyContinue) {
    & verilator --binary --timing $Warn.Split(" ") "+define+$Define" "+incdir+rtl/pcie_ctrl" $(if ($W -gt 0) { "+define+PHY_WIDTH=$W" }) `
      -f rtl/phy/filelist_phy.f rtl/pcie_ctrl/rivet_pkg.sv tb/phy/rivet_phy_pcs_tb.sv `
      --top-module rivet_phy_pcs_tb --Mdir $Out
    if ($LASTEXITCODE -ne 0) { throw "FAIL: build $Name" }
    & (Join-Path $Out "Vrivet_phy_pcs_tb.exe")
    if ($LASTEXITCODE -ne 0) { throw "FAIL: run $Name" }
  } else {
    wsl.exe -e bash -lc $Cmd
    if ($LASTEXITCODE -ne 0) { throw "FAIL: $Name" }
  }
  Write-Host "PASS: sim_phy $Name"
}

if ($Case -eq "all") {
  foreach ($c in @("reset", "8b10b", "eb", "cmd", "gen3", "gen4", "eq", "x4")) {
    Invoke-PhyCase $c 0
  }
  Invoke-PhyCase "8b10b" 32
  Invoke-PhyCase "8b10b" 64
  Invoke-PhyCase "gen3" 64
} else {
  Invoke-PhyCase $Case $Width
}
