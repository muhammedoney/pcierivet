#Requires -Version 5.1
<#
.SYNOPSIS
  Run the PG239 PHY example board sim (Questa) - Rivet BFM side-path stage 1.

.DESCRIPTION
  Compiles / elaborates / simulates the Vivado pcie_phy_0 example design
  (real PG239 + phy_ctrl pattern vs xilinx_pcie_phy_model over serial lanes).

  Requires local proprietary Vivado example + compile_simlib (not in git).
  See tb/bfm/pg239_phy/README.md.

.PARAMETER Step
  compile | elaborate | simulate | all (default)

.PARAMETER Gui
  If set, launch vsim GUI instead of batch (run -all still applies via do file).

.PARAMETER ResetRun
  Delete work/questa_lib and logs, then exit.
#>
param(
  [ValidateSet("all", "compile", "elaborate", "simulate")]
  [string]$Step = "all",
  [switch]$Gui,
  [switch]$ResetRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$LocalPaths = Join-Path $RepoRoot "scripts\local_paths.ps1"
if (Test-Path $LocalPaths) {
  . $LocalPaths
} else {
  Write-Warning "scripts/local_paths.ps1 not found - using environment / defaults."
}

if (-not $env:QUESTA_HOME) {
  $env:QUESTA_HOME = "C:\questasim64_2024.1"
}
$QuestaWin64 = Join-Path $env:QUESTA_HOME "win64"
$env:PATH = "$QuestaWin64;$env:PATH"

if (-not $env:RIVET_PG239_EX) {
  $env:RIVET_PG239_EX = "C:\Users\tosba\vivado\pcie_phy_0_ex"
}
if (-not $env:RIVET_QUESTA_SIMLIB) {
  $env:RIVET_QUESTA_SIMLIB = Join-Path $env:RIVET_PG239_EX "pcie_phy_0_ex.cache\compile_simlib\questa"
}

$ExRoot = $env:RIVET_PG239_EX
$SimLib = $env:RIVET_QUESTA_SIMLIB
$BfmRoot = Join-Path $RepoRoot "tb\bfm\pg239_phy"
$WorkDir = Join-Path $BfmRoot "work"
$QuestaTpl = Join-Path $BfmRoot "questa"

function Fail([string]$Msg) {
  Write-Error $Msg
  exit 1
}

function Require-Path([string]$Path, [string]$Hint) {
  if (-not (Test-Path $Path)) {
    Fail ("Missing: {0}`n{1}" -f $Path, $Hint)
  }
}

Require-Path $ExRoot "Set RIVET_PG239_EX in scripts/local_paths.ps1 to your Vivado pcie_phy_0_ex project."
Require-Path (Join-Path $ExRoot "imports\board.v") "Example imports/ missing - open/generate the Vivado example design."
Require-Path (Join-Path $SimLib "modelsim.ini") "Questa compile_simlib missing. Run: .\scripts\compile_simlib_pg239.ps1"

$vsim = Get-Command vsim -ErrorAction SilentlyContinue
if (-not $vsim) {
  Fail "vsim not on PATH. Set QUESTA_HOME in scripts/local_paths.ps1"
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

if ($ResetRun) {
  Write-Host "Resetting work dir: $WorkDir"
  Remove-Item -Recurse -Force (Join-Path $WorkDir "questa_lib") -ErrorAction SilentlyContinue
  Remove-Item -Force (Join-Path $WorkDir "compile.log"),
    (Join-Path $WorkDir "elaborate.log"),
    (Join-Path $WorkDir "simulate.log"),
    (Join-Path $WorkDir "vsim.wlf"),
    (Join-Path $WorkDir "transcript") -ErrorAction SilentlyContinue
  Write-Host "Done."
  exit 0
}

# Junction under third_party for a stable in-repo path (gitignored contents).
$LinkDir = Join-Path $RepoRoot "third_party\xilinx_ip\pcie_phy_0_ex"
$LinkParent = Split-Path $LinkDir -Parent
New-Item -ItemType Directory -Force -Path $LinkParent | Out-Null
if (-not (Test-Path $LinkDir)) {
  Write-Host "Creating junction: $LinkDir -> $ExRoot"
  cmd /c "mklink /J `"$LinkDir`" `"$ExRoot`"" 2>&1 | Out-Host
  if (-not (Test-Path $LinkDir)) {
    Write-Warning "Junction failed (need Developer Mode or admin). Using RIVET_PG239_EX directly."
  }
}

$ExForCompile = if (Test-Path $LinkDir) { (Resolve-Path $LinkDir).Path } else { $ExRoot }
$ExUnix = ($ExForCompile -replace '\\', '/')
$ImportsUnix = "$ExUnix/imports"

function New-CompileDo {
  $gtStatic = @(
    "gtwizard_ultrascale_v1_7_bit_sync.v",
    "gtwizard_ultrascale_v1_7_gte4_drp_arb.v",
    "gtwizard_ultrascale_v1_7_gthe4_delay_powergood.v",
    "gtwizard_ultrascale_v1_7_gtye4_delay_powergood.v",
    "gtwizard_ultrascale_v1_7_gthe3_cpll_cal.v",
    "gtwizard_ultrascale_v1_7_gthe3_cal_freqcnt.v",
    "gtwizard_ultrascale_v1_7_gthe4_cpll_cal.v",
    "gtwizard_ultrascale_v1_7_gthe4_cpll_cal_rx.v",
    "gtwizard_ultrascale_v1_7_gthe4_cpll_cal_tx.v",
    "gtwizard_ultrascale_v1_7_gthe4_cal_freqcnt.v",
    "gtwizard_ultrascale_v1_7_gtye4_cpll_cal.v",
    "gtwizard_ultrascale_v1_7_gtye4_cpll_cal_rx.v",
    "gtwizard_ultrascale_v1_7_gtye4_cpll_cal_tx.v",
    "gtwizard_ultrascale_v1_7_gtye4_cal_freqcnt.v",
    "gtwizard_ultrascale_v1_7_gtwiz_buffbypass_rx.v",
    "gtwizard_ultrascale_v1_7_gtwiz_buffbypass_tx.v",
    "gtwizard_ultrascale_v1_7_gtwiz_reset.v",
    "gtwizard_ultrascale_v1_7_gtwiz_userclk_rx.v",
    "gtwizard_ultrascale_v1_7_gtwiz_userclk_tx.v",
    "gtwizard_ultrascale_v1_7_gtwiz_userdata_rx.v",
    "gtwizard_ultrascale_v1_7_gtwiz_userdata_tx.v",
    "gtwizard_ultrascale_v1_7_reset_sync.v",
    "gtwizard_ultrascale_v1_7_reset_inv_sync.v"
  ) | ForEach-Object { ('"{0}/pcie_phy_0_ex.ip_user_files/ipstatic/hdl/{1}"' -f $ExUnix, $_) }

  $phy = @(
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/ip_0/sim/gtwizard_ultrascale_v1_7_gtye4_channel.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/ip_0/sim/pcie_phy_0_gt_gtye4_channel_wrapper.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/ip_0/sim/gtwizard_ultrascale_v1_7_gtye4_common.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/ip_0/sim/pcie_phy_0_gt_gtye4_common_wrapper.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/ip_0/sim/pcie_phy_0_gt_gtwizard_gtye4.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/ip_0/sim/pcie_phy_0_gt_gtwizard_top.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/ip_0/sim/pcie_phy_0_gt.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gtwizard_top.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gt_cdr_ctrl_on_eidle.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gt_phy_clk.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gt_phy_rst.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gt_phy_rxeq.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gt_phy_txeq.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gt_phy_wrapper.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_gt_receiver_detect_rxterm.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_sync_cell.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_sync.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_phy_ff_chain.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_phy_pipeline.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/pcie_phy_0_core_top.v",
    "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/sim/pcie_phy_0.v",
    "imports/phy_ctrl.v",
    "imports/phy_ctrl_pat_gen.v",
    "imports/phy_ctrl_pat_gen_lane.v",
    "imports/sys_clk_gen.v",
    "imports/sys_clk_gen_ds.v",
    "imports/xilinx_pcie_phy_model.v",
    "imports/xilinx_pcie_phy_top.v",
    "imports/board.v"
  ) | ForEach-Object { ('"{0}/{1}"' -f $ExUnix, $_) }

  $glblSrc = Join-Path $ExRoot "sim\questa\glbl.v"
  Require-Path $glblSrc "Missing sim/questa/glbl.v in example project."
  Copy-Item -Force $glblSrc (Join-Path $WorkDir "glbl.v")

  $workUnix = ($WorkDir -replace '\\', '/')
  $sb = New-Object System.Text.StringBuilder
  # Parent dir must exist before nested vlib paths (Windows Questa).
  [void]$sb.AppendLine("vlib questa_lib")
  [void]$sb.AppendLine("vlib questa_lib/work")
  [void]$sb.AppendLine("vlib questa_lib/msim")
  [void]$sb.AppendLine("vlib questa_lib/msim/gtwizard_ultrascale_v1_7_19")
  [void]$sb.AppendLine("vlib questa_lib/msim/xil_defaultlib")
  [void]$sb.AppendLine("vmap gtwizard_ultrascale_v1_7_19 questa_lib/msim/gtwizard_ultrascale_v1_7_19")
  [void]$sb.AppendLine("vmap xil_defaultlib questa_lib/msim/xil_defaultlib")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine(('vlog -work gtwizard_ultrascale_v1_7_19 -incr -mfcu "+incdir+{0}" \' -f $ImportsUnix))
  for ($i = 0; $i -lt $gtStatic.Count; $i++) {
    $suffix = if ($i -lt $gtStatic.Count - 1) { " \" } else { "" }
    [void]$sb.AppendLine("$($gtStatic[$i])$suffix")
  }
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine(('vlog -work xil_defaultlib -incr -mfcu "+incdir+{0}" \' -f $ImportsUnix))
  for ($i = 0; $i -lt $phy.Count; $i++) {
    $suffix = if ($i -lt $phy.Count - 1) { " \" } else { "" }
    [void]$sb.AppendLine("$($phy[$i])$suffix")
  }
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("vlog -work xil_defaultlib \")
  [void]$sb.AppendLine(('"{0}/glbl.v"' -f $workUnix))
  Set-Content -Path (Join-Path $WorkDir "compile.do") -Value $sb.ToString() -Encoding ASCII
}

Write-Host "PG239 EX : $ExRoot"
Write-Host "Simlib   : $SimLib"
Write-Host "Work     : $WorkDir"

Copy-Item -Force (Join-Path $SimLib "modelsim.ini") (Join-Path $WorkDir "modelsim.ini")
Copy-Item -Force (Join-Path $QuestaTpl "elaborate.do") (Join-Path $WorkDir "elaborate.do")
Copy-Item -Force (Join-Path $QuestaTpl "simulate.do") (Join-Path $WorkDir "simulate.do")
Copy-Item -Force (Join-Path $QuestaTpl "wave.do") (Join-Path $WorkDir "wave.do") -ErrorAction SilentlyContinue

function Invoke-VsimDo([string]$DoFile, [string]$LogFile) {
  # vsim writes warnings to stderr; do not treat as terminating under Stop.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & vsim -c -do "do {$DoFile}; quit -f" *> $LogFile
    Get-Content $LogFile | Write-Host
  } finally {
    $ErrorActionPreference = $prev
  }
}

if ($Step -eq "all" -or $Step -eq "compile") {
  Write-Host ""
  Write-Host "=== compile ==="
  if (Test-Path (Join-Path $WorkDir "questa_lib")) {
    Remove-Item -Recurse -Force (Join-Path $WorkDir "questa_lib")
  }
  New-CompileDo
  Push-Location $WorkDir
  try {
    Invoke-VsimDo "compile.do" "compile.log"
    if (Select-String -Path "compile.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "compile failed - see $WorkDir\compile.log"
    }
  } finally { Pop-Location }
}

if ($Step -eq "all" -or $Step -eq "elaborate") {
  Write-Host ""
  Write-Host "=== elaborate ==="
  Push-Location $WorkDir
  try {
    Invoke-VsimDo "elaborate.do" "elaborate.log"
    if ($LASTEXITCODE -ne 0) { Fail "elaborate failed - see $WorkDir\elaborate.log" }
    if (Select-String -Path "elaborate.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "elaborate failed - see $WorkDir\elaborate.log"
    }
  } finally { Pop-Location }
}

if ($Step -eq "all" -or $Step -eq "simulate") {
  Write-Host ""
  Write-Host "=== simulate ==="
  Push-Location $WorkDir
  try {
    if ($Gui) {
      & vsim -do "do {simulate.do}"
    } else {
      Invoke-VsimDo "simulate.do" "simulate.log"
      if ($LASTEXITCODE -ne 0) { Fail "simulate failed - see $WorkDir\simulate.log" }
    }
  } finally { Pop-Location }

  $log = Join-Path $WorkDir "simulate.log"
  if ((Test-Path $log) -and -not $Gui) {
    $text = Get-Content $log -Raw
    if ($text -match "Test Completed Successfully") {
      Write-Host ""
      Write-Host "PASS: Test Completed Successfully"
      exit 0
    }
    Write-Warning "Did not find 'Test Completed Successfully' in simulate.log - inspect log."
    exit 2
  }
}

Write-Host ""
Write-Host "Done (step=$Step)."
