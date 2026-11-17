# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Platform Designer system for the Stratix 10 GX Gen2 x4 PIPE PHY.
# Run by fpga/s10gx/create_project.tcl via qsys-script.
#
# L-tile and H-tile share altera_xcvr_native_s10_htile. The kit FPGA is
# the L-tile 1SG280. PIPE Gen2 x4, simplified data interface off, so the
# 80-bit/lane map in rivet_s10gx_ep.sv. Polarity and rate live in the TX word.

package require qsys
if {![info exists ::rivet_s10gx_build]} {
  error "create_project.tcl must pass ::rivet_s10gx_build with qsys-script --cmd"
}
set build $::rivet_s10gx_build
file mkdir $build

proc rivet_has_param {inst name} {
  global rivet_params
  if {![info exists rivet_params($inst)]} {
    if {[catch {set rivet_params($inst) [get_instance_parameters $inst]} err]} {
      error "get_instance_parameters $inst failed: $err"
    }
  }
  return [expr {[lsearch -exact $rivet_params($inst) $name] >= 0}]
}

proc rivet_try_param {inst name value} {
  if {![rivet_has_param $inst $name]} {
    return 0
  }
  if {[catch {set_instance_parameter_value $inst $name $value} err]} {
    puts "rivet: $inst.$name rejected ($value): $err"
    return 0
  }
  set got ""
  catch {set got [get_instance_parameter_value $inst $name]}
  if {[string equal $got ""]} {
    puts "rivet: $inst.$name value $value stored empty"
    return 0
  }
  puts "rivet: $inst.$name = $got"
  return 1
}

proc rivet_require_param {inst name values} {
  foreach value $values {
    if {[rivet_try_param $inst $name $value]} {
      return
    }
  }
  error "rivet: $inst.$name accepted none of: $values"
}

proc rivet_require_named {inst names value} {
  foreach name $names {
    if {[rivet_try_param $inst $name $value]} {
      return
    }
  }
  error "rivet: $inst has none of {$names} for value $value"
}

create_system rivet_s10gx_xcvr
set_project_property DEVICE 1SG280LU2F50E2VG
set_project_property DEVICE_FAMILY {Stratix 10}
set_project_property HIDE_FROM_IP_CATALOG true
catch {set_use_testbench_naming_pattern 0 {}}

add_instance pll altera_xcvr_atx_pll_s10_htile
rivet_require_named pll {set_auto_reference_clock_frequency set_refclk_freq gui_refclk_freq} 100.0
# Gen2 PIPE, byte serializer x2: PLL output is 2500 MHz, line rate 5000 Mbps.
rivet_require_named pll {set_output_clock_frequency gui_output_clock_frequency} 2500.0
catch {rivet_try_param pll set_auto_data_rate 1}
rivet_require_named pll {enable_mcgb} 1
rivet_require_named pll {mcgb_div gui_mcgb_div} 1
rivet_require_named pll {enable_bonding_clks} 1
set pcie_clk_ok 0
foreach name {enable_pcie_clk enable_pll_pcie_clk pcie_clk_enable enable_hclk set_enable_pcie_clk} {
  if {[rivet_try_param pll $name 1]} {
    set pcie_clk_ok 1
    break
  }
}
catch {rivet_try_param pll enable_mcgb_pcie_clksw 1}
if {!$pcie_clk_ok} {
  error "rivet: ATX PLL has no pll_pcie_clk enable"
}
catch {rivet_try_param pll support_mode user_mode}
catch {rivet_try_param pll enable_pll_reconfig 0}
set_instance_property pll AUTO_EXPORT true

add_instance phy altera_xcvr_native_s10_htile
rivet_require_param phy protocol_mode {pipe_g2 pipe_gen2}
rivet_require_param phy pma_mode {basic}
rivet_require_param phy duplex_mode {duplex}
rivet_require_param phy channels {4}
rivet_require_param phy bonded_mode {pma_pcs}
rivet_require_param phy set_pcs_bonding_master {0}
# PMA+PCS bonding with Gen2 PIPE and HIP off requires simultaneous PCS
# reset and the tx_clkout2 port. Compensation must be an explicit token.
rivet_require_param phy pcs_reset_sequencing_mode {bonded}
rivet_require_param phy enable_port_tx_clkout2 {1}
# Bonded Gen2 PIPE phase-comp FIFO requires tx_clkout2 from PCS clkout x2.
rivet_require_param phy tx_clkout2_sel {pcs_x2_clkout}
rivet_require_param phy tx_pma_compensation_en {disable enable}
rivet_require_param phy set_data_rate {5000}
rivet_require_param phy set_cdr_refclk_freq {100.000000}
# Kit VCCR_GXB / VCCT_GXB are strapped 1.0 V or 1.1 V. 1.1 V is the
# high-performance setting and matches the pin assignment in s10gx_pins.tcl.
rivet_require_param phy anlg_voltage {1_1V 1_0V}
rivet_require_param phy anlg_link {sr}
rivet_require_param phy plls {1}
rivet_require_param phy enable_simple_interface {0}
rivet_require_param phy enable_split_interface {0}
rivet_require_param phy enable_hip {0}
rivet_require_param phy enable_ports_pipe_hclk {1}
rivet_require_param phy enable_ports_pipe_sw {1}
rivet_require_param phy enable_ports_pipe_rx_elecidle {1}
# S10 packs rxpolarity into tx_parallel_data[34]. There is no
# enable_port_pipe_rx_polarity on this PHY.
rivet_require_param phy std_pcs_pma_width {10}
rivet_require_param phy std_tx_byte_ser_mode {{Serialize x2}}
rivet_require_param phy std_rx_byte_deser_mode {{Deserialize x2}}
rivet_require_param phy std_tx_8b10b_enable {1}
rivet_require_param phy std_rx_8b10b_enable {1}
rivet_require_param phy std_tx_8b10b_disp_ctrl_enable {1}
rivet_require_param phy std_low_latency_bypass_enable {0}
# S10 names the PCS FIFO tx_fifo_mode / rx_fifo_mode. The Arria 10
# std_*_pcfifo_mode names are absent.
catch {rivet_try_param phy std_tx_pcfifo_mode low_latency}
catch {rivet_try_param phy std_rx_pcfifo_mode low_latency}
rivet_require_param phy tx_fifo_mode {{Phase compensation} phase_comp}
rivet_require_param phy rx_fifo_mode {{Phase compensation} phase_comp}
rivet_require_param phy pcie_rate_match {Bypass bypass}
rivet_require_param phy std_rx_rmfifo_mode {pipe {pipe 0ppm} PIPE pipe_0ppm}
rivet_require_param phy std_rx_word_aligner_mode {{synchronous state machine}}
rivet_require_param phy std_rx_word_aligner_pattern_len {10}
rivet_require_param phy std_rx_word_aligner_pattern {380}
rivet_require_param phy std_rx_word_aligner_renumber {16}
rivet_require_param phy std_rx_word_aligner_rgnumber {15}
rivet_require_param phy std_rx_word_aligner_rknumber {3}
rivet_require_param phy rx_ppm_detect_threshold {1000}
# S10 H-tile has no CTLE/DFE adaptation-mode parameters. Defaults stay.
catch {rivet_try_param phy rx_pma_ctle_adaptation_mode manual}
catch {rivet_try_param phy rx_pma_dfe_adaptation_mode disabled}
rivet_require_param phy message_level {error}
rivet_require_param phy set_enable_calibration {1}
rivet_require_param phy number_physical_bonding_clocks {1}
rivet_require_param phy std_rx_rmfifo_pattern_p {855683}
rivet_require_param phy std_rx_rmfifo_pattern_n {192892}
set_instance_property phy AUTO_EXPORT true

add_instance rst altera_xcvr_reset_control_s10
# h_tile is the production L-tile / H-tile setting. L-tile ES is gone.
rivet_require_param rst TILE_TYPE {h_tile}
rivet_require_param rst CHANNELS {4}
rivet_require_param rst PLLS {1}
rivet_require_param rst SYS_CLK_IN_MHZ {50}
rivet_require_param rst TX_PLL_ENABLE {1}
rivet_require_param rst TX_ENABLE {1}
rivet_require_param rst RX_ENABLE {1}
# S10 reset controller has no SYNCHRONIZE_RESET parameter.
catch {rivet_try_param rst SYNCHRONIZE_RESET 1}
set_instance_property rst AUTO_EXPORT true

# Re-apply after tx_fifo_mode. That assignment re-validates tx_clkout2_sel
# and the IP writes the default back. Generate then rejects the default.
rivet_require_param phy pcs_reset_sequencing_mode {bonded}
rivet_require_param phy enable_port_tx_clkout2 {1}
rivet_require_param phy tx_clkout2_sel {pcs_x2_clkout}
rivet_require_param phy tx_pma_compensation_en {disable enable}

sync_sysinfo_parameters
rivet_require_param phy tx_clkout2_sel {pcs_x2_clkout}
save_system [file join $build rivet_s10gx_xcvr.qsys]
puts "rivet: wrote [file join $build rivet_s10gx_xcvr.qsys]"

# save_system writes the default pcs_clkout even after a successful set.
# Generate rejects that default for bonded Gen2 PIPE, so correct the file.
proc rivet_force_tx_clkout2 {path} {
  set fh [open $path r]
  set body [read $fh]
  close $fh
  set key {<ipxact:name>tx_clkout2_sel</ipxact:name>}
  set i [string first $key $body]
  if {$i < 0} {
    puts "rivet: $path has no tx_clkout2_sel"
    return
  }
  set j [string first {<ipxact:value>} $body $i]
  set k [string first {</ipxact:value>} $body $j]
  set val [string range $body [expr {$j + 14}] [expr {$k - 1}]]
  puts "rivet: [file tail $path] tx_clkout2_sel='$val'"
  if {![string equal $val pcs_clkout]} {
    return
  }
  set body [string replace $body [expr {$j + 14}] [expr {$k - 1}] pcs_x2_clkout]
  set fh [open $path w]
  puts -nonewline $fh $body
  close $fh
  puts "rivet: patched [file tail $path] tx_clkout2_sel to pcs_x2_clkout"
}
foreach phy_ip [glob -nocomplain [file join $build ip rivet_s10gx_xcvr rivet_s10gx_xcvr_phy*.ip]] {
  rivet_force_tx_clkout2 $phy_ip
}
