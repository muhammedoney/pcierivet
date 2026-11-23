#Requires -Version 5.1
<#
.SYNOPSIS
  Questa: PG213 Endpoint model (xilinx_pcie4_uscale_ep) against Rivet Root Port + PG239.

.PARAMETER Step
  compile | elaborate | simulate | all
#>
param(
  [ValidateSet("all", "compile", "elaborate", "simulate")]
  [string]$Step = "all"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$LocalPaths = Join-Path $RepoRoot "scripts\local_paths.ps1"
if (Test-Path $LocalPaths) { . $LocalPaths }

if (-not $env:QUESTA_HOME) { $env:QUESTA_HOME = "C:\questasim64_2024.1" }
$env:PATH = "$(Join-Path $env:QUESTA_HOME 'win64');$env:PATH"

if (-not $env:RIVET_PG213_EX) {
  $env:RIVET_PG213_EX = Join-Path $RepoRoot "third_party\xilinx_ip\pcie4_uscale_plus_0_ex"
}
if (-not $env:RIVET_PG239_EX) {
  $env:RIVET_PG239_EX = Join-Path $RepoRoot "third_party\xilinx_ip\pcie_phy_0_ex"
}
if (-not $env:RIVET_QUESTA_SIMLIB) {
  $shared = "C:\Users\tosba\vivado\pcie_phy_0_ex\pcie_phy_0_ex.cache\compile_simlib\questa"
  if (Test-Path (Join-Path $shared "modelsim.ini")) {
    $env:RIVET_QUESTA_SIMLIB = $shared
  }
}

function Fail([string]$Msg) { Write-Error $Msg; exit 1 }
function Require-Path([string]$Path, [string]$Hint) {
  if (-not (Test-Path $Path)) { Fail ("Missing: {0}`n{1}" -f $Path, $Hint) }
}

$Ex213 = $env:RIVET_PG213_EX
$Ex239 = $env:RIVET_PG239_EX
$SimLib = $env:RIVET_QUESTA_SIMLIB
$BfmRoot = Join-Path $RepoRoot "tb\bfm\pg213_rc"
$WorkDir = Join-Path $BfmRoot "work"
$QuestaDo = Join-Path $Ex213 "questa\compile.do"

Require-Path $Ex213 "Set RIVET_PG213_EX"
Require-Path $Ex239 "Set RIVET_PG239_EX"
Require-Path $QuestaDo "PG213 questa/compile.do missing"
Require-Path (Join-Path $SimLib "modelsim.ini") "compile_simlib missing"
if (-not (Get-Command vsim -ErrorAction SilentlyContinue)) { Fail "vsim not on PATH" }

$Ex213Unix = ((Resolve-Path $Ex213).Path -replace '\\', '/')
$Ex239Unix = ((Resolve-Path $Ex239).Path -replace '\\', '/')
$RepoUnix  = ($RepoRoot.Path -replace '\\', '/')
$WorkUnix  = ((New-Item -ItemType Directory -Force -Path $WorkDir).FullName -replace '\\', '/')

function Add-VlogBlock($sb, $work, $prefix, $files) {
  [void]$sb.AppendLine(("vlog -work {0} -incr -mfcu {1} \" -f $work, $prefix))
  for ($i = 0; $i -lt $files.Count; $i++) {
    $slash = if ($i -lt $files.Count - 1) { " \" } else { "" }
    [void]$sb.AppendLine(('{0}{1}' -f $files[$i], $slash))
  }
  [void]$sb.AppendLine("")
}

# Vendor Endpoint IP + PIO. Skip the GT channel/common bodies (PG239 compiles those
# module names once) and skip the example Root Port model.
$skip = 'gtwizard_ultrascale_v1_7_gtye4_channel\.v|gtwizard_ultrascale_v1_7_gtye4_common\.v|ipstatic/hdl/gtwizard|board\.v$|xilinx_pcie_uscale_rp|pcie_4_0_rp\.v|xp4_usp|pci_exp_usrapp|glbl\.v'
$epFiles = @()
foreach ($m in [regex]::Matches((Get-Content $QuestaDo -Raw), '"(\.\./[^"]+)"')) {
  $rel = $m.Groups[1].Value
  if ($rel -notmatch 'pcie4_uscale_plus_0|clk_wiz_0|/pio|pcie_app_uscale|xilinx_pcie4_uscale_ep|sys_clk_gen') { continue }
  if ($rel -match $skip) { continue }
  $abs = Join-Path (Join-Path $Ex213 "questa") ($rel -replace '/', '\')
  Require-Path $abs "EP source listed in compile.do"
  $epFiles += ('"{0}"' -f (($abs | Resolve-Path).Path -replace '\\', '/'))
}

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
) | ForEach-Object { ('"{0}/pcie_phy_0_ex.ip_user_files/ipstatic/hdl/{1}"' -f $Ex239Unix, $_) }

$phyCore = @(
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
  "pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/sim/pcie_phy_0.v"
) | ForEach-Object { ('"{0}/{1}"' -f $Ex239Unix, $_) }

$rivetSv = @(
  "third_party/ref/tech_cells_generic/src/rtl/tc_sync.sv",
  "third_party/ref/tech_cells_generic/src/rtl/tc_clk.sv",
  "third_party/ref/common_cells/src/cc_rstgen_bypass.sv",
  "third_party/ref/common_cells/src/cc_rstgen.sv",
  "third_party/ref/common_cells/src/cc_cdc_2phase.sv",
  "third_party/ref/verilog-axis/rtl/axis_async_fifo.v",
  "rtl/pcie_ctrl/cdc/rivet_cdc_sync_bus.sv",
  "rtl/pcie_ctrl/cdc/rivet_cdc_axis.sv",
  "rtl/pcie_ctrl/cdc/rivet_cdc_cfg_mgmt.sv",
  "rtl/pcie_ctrl/rivet_pkg.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_mac_if.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_crc16.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_lcrc32.sv",
  "rtl/pcie_ctrl/dll/rivet_dllp_tx.sv",
  "rtl/pcie_ctrl/dll/rivet_dllp_rx.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_fc.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_sm.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_replay.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_tlp_tx.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_tlp_rx.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_tl_pack.sv",
  "rtl/pcie_ctrl/dll/rivet_dll_tl_unpack.sv",
  "rtl/pcie_ctrl/dll/rivet_dll.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_fc_stub.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_credit.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_cfg_space.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_cfg.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_rx_route.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_cq.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_cc.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_rq.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_rc.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_msi.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_aer.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_tx_mux.sv",
  "rtl/pcie_ctrl/tl/rivet_tl_pio_app.sv",
  "tb/bfm/pg213_ep/rtl/rivet_ep_dual_app.sv",
  "rtl/pcie_ctrl/mac/rivet_mac_timer.sv",
  "rtl/pcie_ctrl/mac/rivet_ltssm.sv",
  "rtl/pcie_ctrl/mac/rivet_mac_os_tx.sv",
  "rtl/pcie_ctrl/mac/rivet_mac_os_rx.sv",
  "rtl/pcie_ctrl/mac/rivet_mac_scrambler.sv",
  "rtl/pcie_ctrl/mac/rivet_mac_descrambler.sv",
  "rtl/pcie_ctrl/mac/rivet_mac_lane_map.sv",
  "rtl/pcie_ctrl/mac/rivet_mac_pipe_adapter.sv",
  "rtl/pcie_ctrl/mac/rivet_mac.sv",
  "rtl/pcie_ctrl/rivet_pcie_ctrl.sv",
  "rtl/phy/rivet_pipe_pg239_pad.sv",
  "tb/bfm/pg239_phy/rtl/rivet_pg239_ep.sv",
  "tb/bfm/pg213_rc/rtl/rivet_pg213_rc_board.sv"
) | ForEach-Object { ('"{0}/{1}"' -f $RepoUnix, $_) }

$glblSrc = Join-Path $Ex239 "sim\questa\glbl.v"
if (-not (Test-Path $glblSrc)) { $glblSrc = Join-Path $Ex213 "sim\questa\glbl.v" }
Require-Path $glblSrc "Missing glbl.v"
Copy-Item -Force $glblSrc (Join-Path $WorkDir "glbl.v")

$imp213 = "$Ex213Unix/imports"
$imp239 = "$Ex239Unix/imports"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("vlib questa_lib")
[void]$sb.AppendLine("vlib questa_lib/work")
[void]$sb.AppendLine("vlib questa_lib/msim")
[void]$sb.AppendLine("vlib questa_lib/msim/gtwizard_ultrascale_v1_7_19")
[void]$sb.AppendLine("vlib questa_lib/msim/xil_defaultlib")
[void]$sb.AppendLine("vmap gtwizard_ultrascale_v1_7_19 questa_lib/msim/gtwizard_ultrascale_v1_7_19")
[void]$sb.AppendLine("vmap xil_defaultlib questa_lib/msim/xil_defaultlib")
[void]$sb.AppendLine("")
Add-VlogBlock $sb "gtwizard_ultrascale_v1_7_19" ('"+incdir+{0}"' -f $imp239) $gtStatic
Add-VlogBlock $sb "xil_defaultlib" ('"+incdir+{0}"' -f $imp239) $phyCore
Add-VlogBlock $sb "xil_defaultlib" ('"+incdir+{0}/pcie4_uscale_plus_0_ex.gen/sources_1/ip/pcie4_uscale_plus_0/source" "+incdir+{0}/imports"' -f $Ex213Unix) $epFiles
[void]$sb.AppendLine("vlog -work xil_defaultlib \")
[void]$sb.AppendLine(('"{0}/glbl.v"' -f $WorkUnix))
[void]$sb.AppendLine("")
Add-VlogBlock $sb "xil_defaultlib" ('-sv "+incdir+{0}" "+incdir+{1}/rtl/pcie_ctrl" "+incdir+{1}/third_party/ref/common_cells/include"' -f $imp213, $RepoUnix) $rivetSv
Set-Content -Path (Join-Path $WorkDir "compile.do") -Value $sb.ToString() -Encoding ASCII
Copy-Item -Force (Join-Path $BfmRoot "questa\elaborate.do") (Join-Path $WorkDir "elaborate.do")
Copy-Item -Force (Join-Path $BfmRoot "questa\simulate.do") (Join-Path $WorkDir "simulate.do")

function Invoke-VsimDo([string]$DoFile, [string]$LogFile) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & vsim -c -do "do {$DoFile}; quit -f" *> $LogFile
  } finally { $ErrorActionPreference = $prev }
}

Write-Host "DUT    : Rivet RC + PG213 Endpoint model"
Write-Host "Work   : $WorkDir"
Write-Host "EP src : $($epFiles.Count) files"

if ($Step -eq "all" -or $Step -eq "compile") {
  if (Test-Path (Join-Path $WorkDir "questa_lib")) {
    Remove-Item -Recurse -Force (Join-Path $WorkDir "questa_lib")
  }
  Copy-Item -Force (Join-Path $SimLib "modelsim.ini") (Join-Path $WorkDir "modelsim.ini")
  Push-Location $WorkDir
  try {
    Invoke-VsimDo "compile.do" "compile.log"
    if (Select-String -Path "compile.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "compile failed - see $WorkDir\compile.log"
    }
  } finally { Pop-Location }
  Write-Host "compile done"
}

if ($Step -eq "all" -or $Step -eq "elaborate") {
  Push-Location $WorkDir
  try {
    Invoke-VsimDo "elaborate.do" "elaborate.log"
    if (Select-String -Path "elaborate.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "elaborate failed - see $WorkDir\elaborate.log"
    }
  } finally { Pop-Location }
  Write-Host "elaborate done"
}

if ($Step -eq "all" -or $Step -eq "simulate") {
  Push-Location $WorkDir
  try {
    Invoke-VsimDo "simulate.do" "simulate.log"
  } finally { Pop-Location }
  $text = Get-Content (Join-Path $WorkDir "simulate.log") -Raw
  $up = $text -match "PASS: Rivet RC \+ PG213 EP link_up"
  $hr = $text -match "PASS: Rivet RC \+ PG213 EP hot reset"
  if ($up -and $hr) {
    Write-Host "PASS: Rivet RC + PG213 EP link_up"
    Write-Host "PASS: Rivet RC + PG213 EP hot reset"
    exit 0
  }
  if (-not $up) { Fail "simulate did not reach link_up - see $WorkDir\simulate.log" }
  Fail "simulate did not complete hot reset - see $WorkDir\simulate.log"
}
