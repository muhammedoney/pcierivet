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

& vlog -sv -work work `
  +incdir+tb/uvm `
  -f tb/uvm/filelist_uvm.f

& vsim -c work.rivet_tb_top `
  "+UVM_TESTNAME=$TestName" `
  -do "run -all; quit -f"
