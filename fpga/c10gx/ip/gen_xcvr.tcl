# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Platform Designer system for the Cyclone 10 GX Gen2 x4 PIPE PHY.
# Run by fpga/c10gx/create_project.tcl via qsys-script. Not a Quartus project.
#
# Native PHY parameter names are the Arria 10 transceiver IP names.
# Cyclone 10 GX uses that IP. PIPE Gen2 x4, simplified data interface off,
# so the 128-bit/lane bit map in rivet_c10gx_ep.sv stays valid.
# PCS bonding master is logical channel 0 (edge lane 0, physical Ch4).

# Quartus 25.3 does not load Platform Designer commands unless asked.
# qsys-script also reports [info script] as ".", and a missing parameter
# name is logged as Error without raising, which both mis-places the
# .qsys file and makes a later name look like it was accepted.
package require qsys
if {![info exists ::rivet_c10gx_build]} {
  error "create_project.tcl must pass ::rivet_c10gx_build with qsys-script --cmd"
}
set build $::rivet_c10gx_build
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
  # A GUI label can be accepted without storing a token. An empty
  # readback means this value did not stick; try the next alias.
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

create_system rivet_c10gx_xcvr
set_project_property DEVICE 10CX220YF780E5G
set_project_property DEVICE_FAMILY {Cyclone 10 GX}
set_project_property HIDE_FROM_IP_CATALOG true
catch {set_use_testbench_naming_pattern 0 {}}

add_instance pll altera_xcvr_atx_pll_a10
# Quartus 25.3 names the integer refclk set_auto_reference_clock_frequency.
# Older releases used set_refclk_freq / gui_refclk_freq.
rivet_require_named pll {set_auto_reference_clock_frequency set_refclk_freq gui_refclk_freq} 100.0
# Gen2 PIPE with byte-serializer x2 asks the ATX PLL for 2500 MHz.
# The PHY data rate stays 5000 Mbps.
rivet_require_named pll {set_output_clock_frequency gui_output_clock_frequency} 2500.0
catch {rivet_try_param pll set_auto_data_rate 1}
rivet_require_named pll {enable_mcgb} 1
rivet_require_named pll {mcgb_div gui_mcgb_div} 1
# x4 PIPE needs the Master CGB bonding clocks. Generation rejects the PLL
# when neither bonding clocks nor the non-bonded high-speed port is on.
rivet_require_named pll {enable_bonding_clks} 1
# 500 MHz ASN clock into pipe_hclk_in. The first name that exists wins.
set pcie_clk_ok 0
foreach name {enable_pcie_clk enable_pll_pcie_clk pcie_clk_enable enable_hclk set_enable_pcie_clk} {
  if {[rivet_try_param pll $name 1]} {
    set pcie_clk_ok 1
    break
  }
}
catch {rivet_try_param pll enable_mcgb_pcie_clksw 1}
if {!$pcie_clk_ok} {
  puts "WARN: no ATX PLL parameter enabled pll_pcie_clk. The glue step lists PLL outputs and stops if pipe_hclk_in has no source."
}
catch {rivet_try_param pll support_mode user_mode}
catch {rivet_try_param pll enable_pll_reconfig 0}
set_instance_property pll AUTO_EXPORT true

add_instance phy altera_xcvr_native_a10
rivet_require_param phy protocol_mode {pipe_g2 pipe_gen2}
rivet_require_param phy pma_mode {basic}
rivet_require_param phy duplex_mode {duplex}
rivet_require_param phy channels {4}
# Token, not the GUI label. Std PIPE with channels>1 allows only pma_pcs.
rivet_require_param phy bonded_mode {pma_pcs pma_pcs_bonding {PMA and PCS bonding}}
rivet_require_param phy set_pcs_bonding_master {0}
rivet_require_param phy set_data_rate {5000}
rivet_require_param phy set_cdr_refclk_freq {100.000000}
rivet_require_param phy anlg_voltage {1_0V}
rivet_require_param phy anlg_link {sr}
rivet_require_param phy plls {1}
rivet_require_param phy enable_simple_interface {0}
rivet_require_param phy enable_split_interface {0}
rivet_require_param phy enable_hip {0}
rivet_require_param phy enable_ports_pipe_hclk {1}
rivet_require_param phy enable_ports_pipe_sw {1}
rivet_require_param phy enable_ports_pipe_rx_elecidle {1}
rivet_require_param phy enable_port_pipe_rx_polarity {1}
rivet_require_param phy std_pcs_pma_width {10}
rivet_require_param phy std_tx_byte_ser_mode {{Serialize x2}}
rivet_require_param phy std_rx_byte_deser_mode {{Deserialize x2}}
rivet_require_param phy std_tx_8b10b_enable {1}
rivet_require_param phy std_rx_8b10b_enable {1}
rivet_require_param phy std_tx_8b10b_disp_ctrl_enable {1}
rivet_require_param phy std_low_latency_bypass_enable {0}
rivet_require_param phy std_tx_pcfifo_mode {low_latency}
rivet_require_param phy std_rx_pcfifo_mode {low_latency}
# Gen3 rate-match FIFO. Gen2 PIPE uses std_rx_rmfifo_mode, and Quartus
# then only accepts Bypass here.
rivet_require_param phy pcie_rate_match {Bypass bypass}
rivet_require_param phy std_rx_rmfifo_mode {pipe PIPE pipe_0ppm}
rivet_require_param phy std_rx_word_aligner_mode {{synchronous state machine}}
rivet_require_param phy std_rx_word_aligner_pattern_len {10}
rivet_require_param phy std_rx_word_aligner_pattern {380}
# Quartus 25.3 Gen2 PIPE + synchronous aligner legal counts.
rivet_require_param phy std_rx_word_aligner_renumber {16}
rivet_require_param phy std_rx_word_aligner_rgnumber {15}
rivet_require_param phy std_rx_word_aligner_rknumber {3}
rivet_require_param phy rx_ppm_detect_threshold {1000}
rivet_require_param phy rx_pma_ctle_adaptation_mode {manual}
rivet_require_param phy rx_pma_dfe_adaptation_mode {disabled}
rivet_require_param phy message_level {error}
rivet_require_param phy set_enable_calibration {1}
rivet_require_param phy number_physical_bonding_clocks {1}
# Rate-match SKP patterns from the PIPE Gen2 table: + 0x000d0e83, - 0x0002f17c.
rivet_require_param phy std_rx_rmfifo_pattern_p {855683}
rivet_require_param phy std_rx_rmfifo_pattern_n {192892}
set_instance_property phy AUTO_EXPORT true

add_instance rst altera_xcvr_reset_control
rivet_require_param rst CHANNELS {4}
rivet_require_param rst PLLS {1}
rivet_require_param rst SYS_CLK_IN_MHZ {50}
rivet_require_param rst TX_PLL_ENABLE {1}
rivet_require_param rst TX_ENABLE {1}
rivet_require_param rst RX_ENABLE {1}
rivet_require_param rst SYNCHRONIZE_RESET {1}
set_instance_property rst AUTO_EXPORT true

sync_sysinfo_parameters
save_system [file join $build rivet_c10gx_xcvr.qsys]
puts "rivet: wrote [file join $build rivet_c10gx_xcvr.qsys]"
