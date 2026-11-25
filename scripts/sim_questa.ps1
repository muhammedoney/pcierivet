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
$Mode = if ($args.Count -ge 3) { $args[2] } else { "0" }
# Gen3 tests elaborate a 32-bit pipe. Gen4 tests elaborate a 64-bit pipe.
# Gen2 stays 16-bit.
$Gen = 2
$PipeW = 16
if ($TestName -match 'gen4') {
  $Gen = 4
  $PipeW = 64
} elseif ($TestName -match 'gen3') {
  $Gen = 3
  $PipeW = 32
}

$UvmInc = @()
if ($env:UVM_HOME -and (Test-Path (Join-Path $env:UVM_HOME "src"))) {
  $UvmInc += "+incdir+$env:UVM_HOME\src"
}

Write-Host "Compiling Rivet UVM (test=$TestName lanes=$Lanes mode=$Mode)..."
& vlog -sv -work work `
  "+define+RIVET_TB_LANES=$Lanes" `
  "+define+RIVET_TB_MODE=$Mode" `
  "+define+RIVET_TB_GEN=$Gen" `
  "+define+RIVET_TB_PIPE_W=$PipeW" `
  $(if ($Gen -ge 4) { "+define+RIVET_RQ_G4" } elseif ($Gen -ge 3) { "+define+RIVET_RQ_WIDE" }) `
  "+incdir+tb/uvm" `
  "+incdir+rtl/interfaces" `
  "+incdir+rtl/pcie_ctrl" `
  "+incdir+third_party/ref/common_cells/include" `
  @UvmInc `
  -f tb/uvm/filelist_uvm.f
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Running vsim $TestName..."
& vsim -c work.rivet_tb_top `
  -L mtiUvm `
  -suppress 7061 `
  "+UVM_TESTNAME=$TestName" `
  -do "run -all; quit -f"
exit $LASTEXITCODE
