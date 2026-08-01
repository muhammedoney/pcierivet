#Requires -Version 5.1
<#
.SYNOPSIS
  Run PG213 EP example BFM (Questa) — stock Xilinx EP or Rivet+PG239 EP swap.

.PARAMETER Dut
  stock | rivet

.PARAMETER Step
  compile | elaborate | simulate | all
#>
param(
  [ValidateSet("all", "compile", "elaborate", "simulate")]
  [string]$Step = "all",
  [ValidateSet("stock", "rivet")]
  [string]$Dut = "stock",
  [switch]$Gui,
  [switch]$ResetRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$LocalPaths = Join-Path $RepoRoot "scripts\local_paths.ps1"
if (Test-Path $LocalPaths) { . $LocalPaths }

if (-not $env:QUESTA_HOME) { $env:QUESTA_HOME = "C:\questasim64_2024.1" }
$env:PATH = "$(Join-Path $env:QUESTA_HOME 'win64');$env:PATH"

if (-not $env:RIVET_PG213_EX) {
  $env:RIVET_PG213_EX = "C:\Users\tosba\vivado\pcie4_uscale_plus_0_ex"
}
if (-not $env:RIVET_QUESTA_SIMLIB) {
  # Prefer shared simlib from PG239 bring-up if present.
  $shared = "C:\Users\tosba\vivado\pcie_phy_0_ex\pcie_phy_0_ex.cache\compile_simlib\questa"
  $local  = Join-Path $env:RIVET_PG213_EX "pcie4_uscale_plus_0_ex.cache\compile_simlib\questa"
  if (Test-Path (Join-Path $shared "modelsim.ini")) {
    $env:RIVET_QUESTA_SIMLIB = $shared
  } else {
    $env:RIVET_QUESTA_SIMLIB = $local
  }
}

$ExRoot  = $env:RIVET_PG213_EX
$SimLib  = $env:RIVET_QUESTA_SIMLIB
$QuestaDir = Join-Path $ExRoot "questa"
$BfmRoot = Join-Path $RepoRoot "tb\bfm\pg213_ep"
$WorkDir = Join-Path $BfmRoot "work"

function Fail([string]$Msg) { Write-Error $Msg; exit 1 }
function Require-Path([string]$Path, [string]$Hint) {
  if (-not (Test-Path $Path)) { Fail ("Missing: {0}`n{1}" -f $Path, $Hint) }
}

Require-Path $ExRoot "Set RIVET_PG213_EX in scripts/local_paths.ps1"
Require-Path (Join-Path $ExRoot "imports\board.v") "PG213 example imports/ missing"
Require-Path $QuestaDir "Questa export missing (expect %RIVET_PG213_EX%\questa)"
Require-Path (Join-Path $SimLib "modelsim.ini") @"
compile_simlib missing. Reuse PG239 simlib or run:
  .\scripts\compile_simlib_pg239.ps1
  (or Vivado compile_simlib into RIVET_QUESTA_SIMLIB)
"@

if (-not (Get-Command vsim -ErrorAction SilentlyContinue)) {
  Fail "vsim not on PATH"
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# Junction for stable in-repo path
$LinkDir = Join-Path $RepoRoot "third_party\xilinx_ip\pcie4_uscale_plus_0_ex"
New-Item -ItemType Directory -Force -Path (Split-Path $LinkDir) | Out-Null
if (-not (Test-Path $LinkDir)) {
  Write-Host "Creating junction: $LinkDir -> $ExRoot"
  cmd /c "mklink /J `"$LinkDir`" `"$ExRoot`"" 2>&1 | Out-Host
}

if ($ResetRun) {
  Push-Location $QuestaDir
  Remove-Item -Recurse -Force questa_lib -ErrorAction SilentlyContinue
  Remove-Item -Force compile.log,elaborate.log,simulate.log,vsim.wlf,transcript -ErrorAction SilentlyContinue
  Pop-Location
  Remove-Item -Recurse -Force (Join-Path $WorkDir "*") -ErrorAction SilentlyContinue
  Write-Host "Reset done."
  exit 0
}

if ($Dut -eq "rivet") {
  Write-Warning @"
-Dut rivet is experimental: EP swap shell exists, but stock RP+PIO regression
will not PASS until Rivet LTSSM/TL are green. Prefer -Dut stock for now.
See tb/bfm/pg213_ep/README.md
"@
  Fail "rivet DUT compile path not fully wired yet — use -Dut stock; swap RTL is under tb/bfm/pg213_ep/rtl for next slice"
}

Write-Host "PG213 EX : $ExRoot"
Write-Host "Simlib   : $SimLib"
Write-Host "Questa   : $QuestaDir"
Write-Host "DUT      : $Dut (stock Xilinx EP)"

# Overlay Rivet simulate.do (run -all) into the export tree for this run.
$SimDoRepo = Join-Path $BfmRoot "questa\simulate.do"
Copy-Item -Force (Join-Path $SimLib "modelsim.ini") (Join-Path $QuestaDir "modelsim.ini")
Copy-Item -Force $SimDoRepo (Join-Path $QuestaDir "simulate.do")

function Invoke-VsimDo([string]$DoFile, [string]$LogFile) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & vsim -c -do "do {$DoFile}; quit -f" *> $LogFile
    Get-Content $LogFile | Write-Host
  } finally {
    $ErrorActionPreference = $prev
  }
}

Push-Location $QuestaDir
try {
  if ($Step -eq "all" -or $Step -eq "compile") {
    Write-Host ""
    Write-Host "=== compile (Vivado export compile.do) ==="
    if (Test-Path "questa_lib") { Remove-Item -Recurse -Force "questa_lib" }
    New-Item -ItemType Directory -Force -Path "questa_lib" | Out-Null
    # Parent dir for nested vlib paths
    $compile = Get-Content "compile.do" -Raw
    if ($compile -notmatch "(?m)^vlib questa_lib\s*$") {
      $compile = "vlib questa_lib`r`n" + $compile
      Set-Content "compile.do.rivet" -Value $compile -Encoding ASCII
      Invoke-VsimDo "compile.do.rivet" "compile.log"
    } else {
      Invoke-VsimDo "compile.do" "compile.log"
    }
    if (Select-String -Path "compile.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "compile failed — see $QuestaDir\compile.log"
    }
  }

  if ($Step -eq "all" -or $Step -eq "elaborate") {
    Write-Host ""
    Write-Host "=== elaborate ==="
    Invoke-VsimDo "elaborate.do" "elaborate.log"
    if (Select-String -Path "elaborate.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "elaborate failed — see $QuestaDir\elaborate.log"
    }
  }

  if ($Step -eq "all" -or $Step -eq "simulate") {
    Write-Host ""
    Write-Host "=== simulate ==="
    if ($Gui) {
      & vsim -do "do {simulate.do}"
    } else {
      Invoke-VsimDo "simulate.do" "simulate.log"
    }
    $log = Join-Path $QuestaDir "simulate.log"
    if ((Test-Path $log) -and -not $Gui) {
      $text = Get-Content $log -Raw
      # Stock PIO test prints vary; accept common PASS tokens.
      if ($text -match "TEST PASSED|Test Completed Successfully|passed") {
        Write-Host ""
        Write-Host "PASS: stock PG213 EP example"
        exit 0
      }
      if ($text -match "TEST FAILED|Simulation timeout") {
        Fail "simulate reported FAIL — see $log"
      }
      Write-Warning "No clear PASS token in simulate.log — inspect $log"
      exit 2
    }
  }
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "Done (step=$Step dut=$Dut)."
