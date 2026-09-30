#Requires -Version 5.1
<#
.SYNOPSIS
  Run PG213 EP example BFM (Questa) — stock Xilinx EP or Rivet+PG239 EP under RP model.

.PARAMETER Dut
  stock | rivet

.PARAMETER Step
  compile | elaborate | simulate | all

.PARAMETER Lanes
  Rivet DUT only: RP advertised / negotiated link width 1|2|4 (EP PHY stays x4).
#>
param(
  [ValidateSet("all", "compile", "elaborate", "simulate")]
  [string]$Step = "all",
  [ValidateSet("stock", "rivet")]
  [string]$Dut = "stock",
  [ValidateSet(1, 2, 4)]
  [int]$Lanes = 4,
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
  $env:RIVET_PG213_EX = Join-Path $RepoRoot "third_party\xilinx_ip\pcie4_uscale_plus_0_ex"
}
if (-not $env:RIVET_PG239_EX) {
  $env:RIVET_PG239_EX = Join-Path $RepoRoot "third_party\xilinx_ip\pcie_phy_0_ex"
}
if (-not $env:RIVET_QUESTA_SIMLIB) {
  $shared = "C:\Users\tosba\vivado\pcie_phy_0_ex\pcie_phy_0_ex.cache\compile_simlib\questa"
  $local  = Join-Path $env:RIVET_PG213_EX "pcie4_uscale_plus_0_ex.cache\compile_simlib\questa"
  if (Test-Path (Join-Path $shared "modelsim.ini")) {
    $env:RIVET_QUESTA_SIMLIB = $shared
  } else {
    $env:RIVET_QUESTA_SIMLIB = $local
  }
}

$Ex213   = $env:RIVET_PG213_EX
$Ex239   = $env:RIVET_PG239_EX
$SimLib  = $env:RIVET_QUESTA_SIMLIB
$Questa213 = Join-Path $Ex213 "questa"
$BfmRoot = Join-Path $RepoRoot "tb\bfm\pg213_ep"
$WorkDir = Join-Path $BfmRoot "work"

function Fail([string]$Msg) { Write-Error $Msg; exit 1 }
function Require-Path([string]$Path, [string]$Hint) {
  if (-not (Test-Path $Path)) { Fail ("Missing: {0}`n{1}" -f $Path, $Hint) }
}

Require-Path $Ex213 "Set RIVET_PG213_EX in scripts/local_paths.ps1"
Require-Path (Join-Path $Ex213 "imports\board.v") "PG213 example imports/ missing"
Require-Path $Questa213 "Questa export missing (expect %RIVET_PG213_EX%\questa)"
Require-Path (Join-Path $SimLib "modelsim.ini") @"
compile_simlib missing. Reuse PG239 simlib or run:
  .\scripts\compile_simlib_pg239.ps1
"@

if (-not (Get-Command vsim -ErrorAction SilentlyContinue)) {
  Fail "vsim not on PATH"
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

if ($ResetRun) {
  Push-Location $Questa213
  Remove-Item -Recurse -Force questa_lib -ErrorAction SilentlyContinue
  Remove-Item -Force compile.log,elaborate.log,simulate.log,vsim.wlf,transcript -ErrorAction SilentlyContinue
  Pop-Location
  Remove-Item -Recurse -Force (Join-Path $WorkDir "*") -ErrorAction SilentlyContinue
  Write-Host "Reset done."
  exit 0
}

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

# ---------------------------------------------------------------------------
# Stock: Vivado export flow under %RIVET_PG213_EX%\questa
# ---------------------------------------------------------------------------
if ($Dut -eq "stock") {
  Write-Host "PG213 EX : $Ex213"
  Write-Host "Simlib   : $SimLib"
  Write-Host "Questa   : $Questa213"
  Write-Host "DUT      : stock (Xilinx EP)"

  $SimDoRepo = Join-Path $BfmRoot "questa\simulate.do"
  Copy-Item -Force (Join-Path $SimLib "modelsim.ini") (Join-Path $Questa213 "modelsim.ini")
  Copy-Item -Force $SimDoRepo (Join-Path $Questa213 "simulate.do")

  Push-Location $Questa213
  try {
    if ($Step -eq "all" -or $Step -eq "compile") {
      Write-Host ""
      Write-Host "=== compile (Vivado export compile.do) ==="
      if (Test-Path "questa_lib") { Remove-Item -Recurse -Force "questa_lib" }
      New-Item -ItemType Directory -Force -Path "questa_lib" | Out-Null
      $compile = Get-Content "compile.do" -Raw
      if ($compile -notmatch "(?m)^vlib questa_lib\s*$") {
        $compile = "vlib questa_lib`r`n" + $compile
        Set-Content "compile.do.rivet" -Value $compile -Encoding ASCII
        Invoke-VsimDo "compile.do.rivet" "compile.log"
      } else {
        Invoke-VsimDo "compile.do" "compile.log"
      }
      if (Select-String -Path "compile.log" -Pattern "\*\* Error:" -Quiet) {
        Fail "compile failed - see $Questa213\compile.log"
      }
    }

    if ($Step -eq "all" -or $Step -eq "elaborate") {
      Write-Host ""
      Write-Host "=== elaborate ==="
      Invoke-VsimDo "elaborate.do" "elaborate.log"
      if (Select-String -Path "elaborate.log" -Pattern "\*\* Error:" -Quiet) {
        Fail "elaborate failed - see $Questa213\elaborate.log"
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
      $log = Join-Path $Questa213 "simulate.log"
      if ((Test-Path $log) -and -not $Gui) {
        $text = Get-Content $log -Raw
        if ($text -match "TEST PASSED|Test Completed Successfully|passed") {
          Write-Host ""
          Write-Host "PASS: stock PG213 EP example"
          Pop-Location
          exit 0
        }
        if ($text -match "TEST FAILED|Simulation timeout") {
          Fail "simulate reported FAIL - see $log"
        }
        Write-Warning "No clear PASS token in simulate.log - inspect $log"
        Pop-Location
        exit 2
      }
    }
  }
  finally {
    Pop-Location
  }

  Write-Host ""
  Write-Host "Done (step=$Step dut=$Dut)."
  exit 0
}

# ---------------------------------------------------------------------------
# Rivet: PG213 RP model + Rivet EP+PG239 under tb/bfm/pg213_ep/work
# ---------------------------------------------------------------------------
Require-Path $Ex239 "Set RIVET_PG239_EX (needed for Rivet EP PHY)"
Require-Path (Join-Path $Ex239 "imports\sys_clk_gen_ds.v") "PG239 example missing sys_clk_gen_ds"
Require-Path (Join-Path $BfmRoot "rtl\rivet_pg213_board.sv") "Missing rivet_pg213_board.sv"

$Ex239Unix = ((Resolve-Path $Ex239).Path -replace '\\', '/')
$Ex213Unix = ((Resolve-Path $Ex213).Path -replace '\\', '/')
$RepoUnix  = ($RepoRoot.Path -replace '\\', '/')
$WorkUnix  = ($WorkDir -replace '\\', '/')
$Imp213    = "$Ex213Unix/imports"
$Imp239    = "$Ex239Unix/imports"

Write-Host "PG213 EX : $Ex213"
Write-Host "PG239 EX : $Ex239"
Write-Host "Simlib   : $SimLib"
Write-Host "Work     : $WorkDir"
Write-Host "DUT      : rivet (PG213 RP + Rivet EP)"
Write-Host "Lanes    : x$Lanes (RP advertised; EP PHY fixed x4; Gen1-negotiated)"

function New-RivetCompileDo {
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

  $rpFiles = @(
    ('"{0}/tb/bfm/pg213_ep/rtl/board_common_inc.v"' -f $RepoUnix),
    ('"{0}/pci_exp_usrapp_cfg.v"' -f $Imp213),
    ('"{0}/pci_exp_usrapp_com.v"' -f $Imp213),
    ('"{0}/pci_exp_usrapp_rx.v"' -f $Imp213),
    ('"{0}/pci_exp_usrapp_tx.v"' -f $Imp213),
    ('"{0}/xp4_usp_smsw_model_core_top.v"' -f $Imp213),
    ('"{0}/pcie_4_0_rp.v"' -f $Imp213),
    ('"{0}/sys_clk_gen.v"' -f $Imp213),
    ('"{0}/sys_clk_gen_ds.v"' -f $Imp213),
    ('"{0}/xilinx_pcie_uscale_rp.v"' -f $Imp213)
  )

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
    "tb/bfm/pg213_ep/rtl/rivet_pg213_ep_swap.sv",
    "tb/bfm/pg213_ep/rtl/rivet_pg213_board.sv"
  ) | ForEach-Object { ('"{0}/{1}"' -f $RepoUnix, $_) }

  $glblSrc = Join-Path $Ex239 "sim\questa\glbl.v"
  if (-not (Test-Path $glblSrc)) {
    $glblSrc = Join-Path $Ex213 "sim\questa\glbl.v"
  }
  Require-Path $glblSrc "Missing glbl.v"
  Copy-Item -Force $glblSrc (Join-Path $WorkDir "glbl.v")

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("vlib questa_lib")
  [void]$sb.AppendLine("vlib questa_lib/work")
  [void]$sb.AppendLine("vlib questa_lib/msim")
  [void]$sb.AppendLine("vlib questa_lib/msim/gtwizard_ultrascale_v1_7_19")
  [void]$sb.AppendLine("vlib questa_lib/msim/xil_defaultlib")
  [void]$sb.AppendLine("vmap gtwizard_ultrascale_v1_7_19 questa_lib/msim/gtwizard_ultrascale_v1_7_19")
  [void]$sb.AppendLine("vmap xil_defaultlib questa_lib/msim/xil_defaultlib")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine(('vlog -work gtwizard_ultrascale_v1_7_19 -incr -mfcu "+incdir+{0}" \' -f $Imp239))
  for ($i = 0; $i -lt $gtStatic.Count; $i++) {
    $suffix = if ($i -lt $gtStatic.Count - 1) { " \" } else { "" }
    [void]$sb.AppendLine("$($gtStatic[$i])$suffix")
  }
  [void]$sb.AppendLine("")
  # PG239 PHY
  [void]$sb.AppendLine(('vlog -work xil_defaultlib -incr -mfcu "+incdir+{0}" \' -f $Imp239))
  for ($i = 0; $i -lt $phyCore.Count; $i++) {
    $suffix = if ($i -lt $phyCore.Count - 1) { " \" } else { "" }
    [void]$sb.AppendLine("$($phyCore[$i])$suffix")
  }
  [void]$sb.AppendLine("")
  # PG213 RP model (+ board_common macros via -mfcu prelude)
  [void]$sb.AppendLine(('vlog -work xil_defaultlib -incr -mfcu "+incdir+{0}" \' -f $Imp213))
  for ($i = 0; $i -lt $rpFiles.Count; $i++) {
    $suffix = if ($i -lt $rpFiles.Count - 1) { " \" } else { "" }
    [void]$sb.AppendLine("$($rpFiles[$i])$suffix")
  }
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("vlog -work xil_defaultlib \")
  [void]$sb.AppendLine(('"{0}/glbl.v"' -f $WorkUnix))
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine(('vlog -work xil_defaultlib -sv -incr -mfcu "+incdir+{0}" "+incdir+{1}/third_party/ref/common_cells/include" "+define+RIVET_BFM_LANES={2}" \' -f $Imp213, $RepoUnix, $Lanes))
  for ($i = 0; $i -lt $rivetSv.Count; $i++) {
    $suffix = if ($i -lt $rivetSv.Count - 1) { " \" } else { "" }
    [void]$sb.AppendLine("$($rivetSv[$i])$suffix")
  }

  Set-Content -Path (Join-Path $WorkDir "compile.do") -Value $sb.ToString() -Encoding ASCII
}

Copy-Item -Force (Join-Path $BfmRoot "questa\elaborate_rivet.do") (Join-Path $WorkDir "elaborate.do")
Copy-Item -Force (Join-Path $BfmRoot "questa\simulate_rivet.do") (Join-Path $WorkDir "simulate.do")

if ($Step -eq "all" -or $Step -eq "compile") {
  Write-Host ""
  Write-Host "=== compile (rivet) ==="
  if (Test-Path (Join-Path $WorkDir "questa_lib")) {
    Remove-Item -Recurse -Force (Join-Path $WorkDir "questa_lib")
  }
  Copy-Item -Force (Join-Path $SimLib "modelsim.ini") (Join-Path $WorkDir "modelsim.ini")
  New-RivetCompileDo
  Push-Location $WorkDir
  try {
    Invoke-VsimDo "compile.do" "compile.log"
    if (Select-String -Path "compile.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "compile failed - see $WorkDir\compile.log"
    }
  }
  finally { Pop-Location }
}

if ($Step -eq "all" -or $Step -eq "elaborate") {
  Write-Host ""
  Write-Host "=== elaborate (rivet) ==="
  Push-Location $WorkDir
  try {
    Invoke-VsimDo "elaborate.do" "elaborate.log"
    if ($LASTEXITCODE -ne 0) { Fail "elaborate failed - see $WorkDir\elaborate.log" }
    if (Select-String -Path "elaborate.log" -Pattern "\*\* Error:" -Quiet) {
      Fail "elaborate failed - see $WorkDir\elaborate.log"
    }
  }
  finally { Pop-Location }
}

if ($Step -eq "all" -or $Step -eq "simulate") {
  Write-Host ""
  Write-Host "=== simulate (rivet) ==="
  Push-Location $WorkDir
  try {
    if ($Gui) {
      & vsim -do "do {simulate.do}"
    } else {
      Invoke-VsimDo "simulate.do" "simulate.log"
      if ($LASTEXITCODE -ne 0) { Fail "simulate failed - see $WorkDir\simulate.log" }
    }
  }
  finally { Pop-Location }

  $log = Join-Path $WorkDir "simulate.log"
  if ((Test-Path $log) -and -not $Gui) {
    $text = Get-Content $log -Raw
    if ($text -match "Class E FAIL") {
      Write-Host ""
      Write-Host "FAIL: MemWr/MemRd app score - see $log"
      exit 1
    }
    if ($text -match "Class A\+C\+E|Class A\+C|Class A PASS|PG213 RP \+ Rivet EP PIO 1DW") {
      Write-Host ""
      if ($text -match "Class E PASS") {
        Write-Host "PASS: PG213 RP + Rivet EP Class A+C+E (Gen1 x$Lanes)"
      } elseif ($text -match "Class C PASS") {
        Write-Host "PASS: PG213 RP + Rivet EP Class A+C (Gen1 x$Lanes)"
      } else {
        Write-Host "PASS: PG213 RP + Rivet EP PIO 1DW (Gen1 x$Lanes)"
      }
      exit 0
    }
    if ($text -match "Class A FAIL|PIO 1DW incomplete") {
      Write-Host ""
      Write-Host "FAIL: Class A / PIO incomplete - see $log"
      exit 1
    }
    if ($text -match "Cfg Vendor/Device incomplete") {
      Write-Host ""
      Write-Host "FAIL: Cfg incomplete - see $log"
      exit 1
    }
    if ($text -match "Detect/Polling cycle|Config reached then back to Detect|link training timeout|TIMEOUT") {
      Write-Host ""
      Write-Host "FAIL: link training - see $log"
      exit 1
    }
    Write-Warning "No clear PASS/FAIL token in simulate.log - inspect $log"
    exit 2
  }
}

Write-Host ""
Write-Host "Done (step=$Step dut=$Dut)."
