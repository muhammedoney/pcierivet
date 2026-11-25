# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
param([switch]$DryRun)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
$env:RIVET_NO_PAUSE = "1"
$steps = @(
  "fpga\vcu118\create_project.cmd 4 ep",
  "fpga\vcu118\impl.cmd 4 ep",
  "fpga\vmk180\create_project.cmd 4 ep",
  "fpga\vmk180\impl.cmd 4 ep"
)
foreach ($step in $steps) {
  Write-Output $step
  if (-not $DryRun) {
    cmd.exe /c $step
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
}
