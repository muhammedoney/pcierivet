# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Create a local Vivado project for the VCU118 Gen2 x4 Endpoint.
# Generated IP and the project directory are gitignored.
#
#   vivado -mode batch -source fpga/vcu118/create_project.tcl
#   vivado -mode batch -source fpga/vcu118/create_project.tcl -tclargs synth
#
# Requires a Vivado install that can generate PG239 (pcie_phy) for XCVU9P GTY.
# Board files for xilinx.com:vcu118 are optional; the part is set either way.

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set build_dir  [file join $script_dir build]
set part       xcvu9p-flga2104-2L-e
set board      xilinx.com:vcu118:part0:2.4

# Edge-connector lane 0. Quad 227, MGTREFCLK0 (pins AC9/AC8).
set lane0_loc  GTYE4_CHANNEL_X1Y35
set lane0_bank GTY_Quad_227
set refclk_loc Bank_227_MGTREFCLK0

proc rivet_add_filelist {repo listfile} {
  set fh [open $listfile r]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
      continue
    }
    if {[string match "-f *" $line]} {
      set sub [string trim [string range $line 3 end]]
      rivet_add_filelist $repo [file join $repo $sub]
      continue
    }
    set path [file normalize [file join $repo $line]]
    if {![file exists $path]} {
      close $fh
      error "missing source: $path"
    }
    add_files -norecurse $path
  }
  close $fh
}

proc rivet_try_ip_config {obj name value} {
  if {[catch {set_property CONFIG.$name $value $obj} err]} {
    puts "WARN: CONFIG.$name=$value was rejected: $err"
    if {![catch {set legal [list_property_value CONFIG.$name $obj]}]} {
      puts "      legal values: $legal"
    }
    return 0
  }
  return 1
}

file mkdir $build_dir
create_project rivet_vcu118 $build_dir -part $part -force
set_property target_language Verilog [current_project]
if {[catch {set_property board_part $board [current_project]} err]} {
  puts "WARN: board part $board not installed ($err). Continuing with $part."
}

rivet_add_filelist $repo_root [file join $repo_root rtl filelist_core.f]
add_files -norecurse [file normalize [file join $script_dir rtl rivet_vcu118_ep.sv]]
add_files -norecurse [file normalize [file join $repo_root rtl phy rivet_pipe_pg239_pad.sv]]

foreach f [get_files -of_objects [current_fileset]] {
  set name [get_property NAME $f]
  if {[string match *.sv $name]} {
    set_property file_type SystemVerilog $f
  }
}
set_property include_dirs [list \
  [file normalize [file join $repo_root third_party ref common_cells include]] \
] [current_fileset]

set xdc [file join $script_dir constraints vcu118_pcie.xdc]
add_files -fileset constrs_1 -norecurse $xdc

create_ip -name pcie_phy -vendor xilinx.com -library ip -module_name pcie_phy_0
set ip [get_ips pcie_phy_0]
rivet_try_ip_config $ip gt_type          GTY
rivet_try_ip_config $ip phy_lane         X4
rivet_try_ip_config $ip phy_max_speed    5.0_GT/s
rivet_try_ip_config $ip phy_refclk_freq  100_MHz
rivet_try_ip_config $ip phy_userclk_freq 250_MHz
rivet_try_ip_config $ip phy_async_en     true
rivet_try_ip_config $ip pll_type         QPLL1
rivet_try_ip_config $ip tx_preset        4
rivet_try_ip_config $ip ins_loss_profile Add-in_Card
rivet_try_ip_config $ip aspm             No_ASPM
rivet_try_ip_config $ip lane0_gt_location $lane0_loc
rivet_try_ip_config $ip lane0_gt_bank     $lane0_bank
rivet_try_ip_config $ip refclk1_location  $refclk_loc
generate_target {instantiation_template synthesis} $ip

set_property top rivet_vcu118_ep [current_fileset]
update_compile_order -fileset sources_1

set do_synth 0
if {[info exists argv] && [llength $argv] > 0 && [lindex $argv 0] eq "synth"} {
  set do_synth 1
}
if {$do_synth} {
  launch_runs synth_1 -jobs 4
  wait_on_run synth_1
  if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 failed — see $build_dir"
  }
  puts "PASS: synth_1 complete"
}

puts "Project: [file join $build_dir rivet_vcu118.xpr]"
puts "Open it in Vivado, run synth, then impl. LEDs: \[0\]=link_up \[1\]=phy_ready \[2\]=heartbeat \[7:3\]=LTSSM\[4:0\] (L0 is 0x10)."
close_project
