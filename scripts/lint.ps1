# Copyright 2026 Rivet contributors
# Verilator lint of rivet_pcie_ctrl (Windows PowerShell)
param(
  [ValidateSet(2, 3)]
  [int]$Gen = 2
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Warn = "-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-GENUNNAMED -Wno-PROCASSINIT -Wno-INITIALDLY"
$Inc = "+incdir+rtl/pcie_ctrl +incdir+third_party/ref/common_cells/include"

# wslpath blocks when the VM is busy. Map the drive letter here instead.
$WslRoot = $Root
if ($WslRoot -match '^([A-Za-z]):\\(.*)$') {
  $WslRoot = "/mnt/$($Matches[1].ToLower())/$($Matches[2] -replace '\\','/')"
}

$Lint = "verilator --lint-only --replication-limit 65536 $Warn $Inc -f rtl/filelist_core.f"
$UseWsl = -not (Get-Command verilator -ErrorAction SilentlyContinue)

if ($UseWsl) {
  # One WSL process. A second wsl.exe right after the first has been killing the service.
  $Cmd = "cd '$WslRoot' && $Lint --top-module rivet_pcie_ctrl"
  if ($Gen -eq 3) {
    $Cmd += " && $Lint tb/lint/rivet_gen3_lint_top.sv --top-module rivet_gen3_lint_top"
  }
  wsl.exe -e bash -lc $Cmd
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: lint" }
} else {
  # 4 KB TLP slots are 33024 bits. The default replication limit is 8192.
  & verilator --lint-only --replication-limit 65536 $Warn.Split(" ") $Inc -f rtl/filelist_core.f --top-module rivet_pcie_ctrl
  if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: lint" }
  if ($Gen -eq 3) {
    & verilator --lint-only --replication-limit 65536 $Warn.Split(" ") $Inc -f rtl/filelist_core.f tb/lint/rivet_gen3_lint_top.sv --top-module rivet_gen3_lint_top
    if ($LASTEXITCODE -ne 0) { Write-Error "FAIL: Gen3 lint" }
  }
}
Write-Host "PASS: Verilator lint (controller)"
if ($Gen -eq 3) {
  Write-Host "PASS: Verilator lint (Gen3 x4 width 32)"
}
