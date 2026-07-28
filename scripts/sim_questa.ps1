# Copyright 2026 Rivet contributors
# QuestaSim UVM smoke (Windows). Requires local Questa + UVM.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Local = Join-Path $Root "scripts\local_paths.ps1"
if (Test-Path $Local) { . $Local }

if (-not (Get-Command vsim -ErrorAction SilentlyContinue)) {
  Write-Error "vsim not found. Install QuestaSim and create scripts/local_paths.ps1 from the example."
}

$TestName = if ($args.Count -ge 1) { $args[0] } else { "smoke_gen2_x1" }
$Lanes = if ($args.Count -ge 2) { $args[1] } else { "1" }

$UvmInc = @()
if ($env:UVM_HOME -and (Test-Path (Join-Path $env:UVM_HOME "src"))) {
  $UvmInc += "+incdir+$env:UVM_HOME\src"
}

Write-Host "Compiling Rivet UVM (test=$TestName lanes=$Lanes)..."
& vlog -sv -work work `
  "+define+RIVET_TB_LANES=$Lanes" `
  "+incdir+tb/uvm" `
  "+incdir+rtl/interfaces" `
  @UvmInc `
  -f tb/uvm/filelist_uvm.f
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Running vsim $TestName..."
& vsim -c work.rivet_tb_top `
  -L mtiUvm `
  "+UVM_TESTNAME=$TestName" `
  -do "run -all; quit -f"
exit $LASTEXITCODE
