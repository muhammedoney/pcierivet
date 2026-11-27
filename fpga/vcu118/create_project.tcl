# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Create a local Vivado project for the VCU118 Gen2 x4 Endpoint.
# Generated IP and the project directory are gitignored.
#
#   vivado -mode batch -source fpga/vcu118/create_project.tcl
#   vivado -mode batch -source fpga/vcu118/create_project.tcl -tclargs synth
#   fpga\vcu118\create_project.cmd
#   fpga\vcu118\create_project.cmd synth
#
# The PMA is rivet_pcie_phy_soft on GTYE4 primitives. PG239 is not generated.
# Board files for xilinx.com:vcu118 are optional; the part is set either way.

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set gen4 0
if {[info exists argv] && [llength $argv] == 2 &&
    [lindex $argv 0] eq "4" && [lindex $argv 1] eq "ep"} {
  set gen4 1
} elseif {[info exists argv] && [llength $argv] == 1 && [lindex $argv 0] eq "synth"} {
  # Raw `vivado -tclargs synth` still builds and synthesizes the Gen2 project.
} elseif {[info exists argv] && [llength $argv] != 0} {
  error "usage: no arguments, or: 4 ep"
}
set build_dir [file join $script_dir build [expr {$gen4 ? "gen4_ep" : ""}]]
set part       xcvu9p-flga2104-2L-e
set board      xilinx.com:vcu118:part0:2.4

# Edge-connector lane 0. Quad 227, MGTREFCLK0 (pins AC9/AC8).
set lane0_loc  GTYE4_CHANNEL_X1Y35
set lane0_bank GTY_Quad_227
set refclk_loc Bank_227_MGTREFCLK0

# Quoted `include is resolved from the including file's directory first.
# The Vivado copy of cc_cdc_2phase.sv lives in build/src, so
# `include "common_cells/registers.svh" needs
# build/src/common_cells/registers.svh. That copy is the header without
# default macro arguments. data_t'('0) is still rewritten to '0.
# FF / FFL call sites stay as they are. Simulation keeps the upstream file.
proc rivet_patch_cdc_2phase {src build regs_svh} {
  set dst_dir [file join $build src]
  set inc_dir [file join $dst_dir common_cells]
  file mkdir $inc_dir
  set dst [file join $dst_dir cc_cdc_2phase.sv]
  set fh [open $src r]
  set text [read $fh]
  close $fh
  if {![string match "*data_t'('0)*" $text]} {
    error "cc_cdc_2phase.sv no longer contains data_t'('0); update the Vivado patch"
  }
  if {![string match {*`include "common_cells/registers.svh"*} $text]} {
    error "cc_cdc_2phase.sv no longer includes common_cells/registers.svh; update the Vivado patch"
  }
  set text [string map [list {data_t'('0)} {'0}] $text]
  set out [open $dst w]
  puts -nonewline $out $text
  close $out
  file copy -force $regs_svh [file join $inc_dir registers.svh]
  return [file normalize $dst]
}

proc rivet_add_filelist {repo listfile build regs_svh} {
  set fh [open $listfile r]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
      continue
    }
    if {[string match "-f *" $line]} {
      set sub [string trim [string range $line 3 end]]
      rivet_add_filelist $repo [file join $repo $sub] $build $regs_svh
      continue
    }
    set path [file normalize [file join $repo $line]]
    if {![file exists $path]} {
      close $fh
      error "missing source: $path"
    }
    if {[string match *cc_cdc_2phase.sv $path]} {
      set path [rivet_patch_cdc_2phase $path $build $regs_svh]
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

proc rivet_collect_v {dir} {
  set hits [lsort [glob -nocomplain -directory $dir *.v]]
  foreach sub [lsort [glob -nocomplain -directory $dir -type d *]] {
    set hits [concat $hits [rivet_collect_v $sub]]
  }
  return $hits
}

proc rivet_file_range {path port} {
  if {![file exists $path]} {
    return ""
  }
  set fh [open $path r]
  set body [read $fh]
  close $fh
  if {[regexp "\\\[\\s*(\[0-9\]+)\\s*:\\s*(\[0-9\]+)\\s*\\\]\\s*${port}\\M" $body -> hi lo]} {
    return "${hi}:${lo}"
  }
  return ""
}

file mkdir $build_dir
create_project rivet_vcu118 $build_dir -part $part -force
set_property target_language Verilog [current_project]
if {[catch {set_property board_part $board [current_project]} err]} {
  puts "WARN: board part $board not installed ($err). Continuing with $part."
}

set regs_svh [file normalize [file join $script_dir include common_cells registers.svh]]
rivet_add_filelist $repo_root [file join $repo_root rtl filelist_core.f] $build_dir $regs_svh
add_files -norecurse [file normalize [file join $script_dir rtl rivet_vcu118_ep.sv]]
rivet_add_filelist $repo_root [file join $repo_root rtl phy filelist_phy.f] $build_dir $regs_svh
add_files -norecurse [file normalize [file join $repo_root rtl phy rivet_phy_gty_usplus.sv]]
add_files -norecurse [file normalize [file join $repo_root fpga common rivet_fpga_pio256.sv]]

foreach f [get_files -of_objects [current_fileset]] {
  set name [get_property NAME $f]
  if {[string match *.sv $name]} {
    set_property file_type SystemVerilog $f
  }
}
# `include "common_cells/registers.svh" has a directory component.
# The include dir must be the parent of common_cells/, not the folder
# that contains registers.svh:
#   fpga/vcu118/include/common_cells/registers.svh
#   build/src/common_cells/registers.svh
# The upstream header under third_party/ref/common_cells/include uses
# default macro arguments. Leave that directory off this list.
# rivet_pkg.sv includes rivet_crc_fold.svh by basename from the same directory.
set_property include_dirs [list \
  [file normalize [file join $build_dir src]] \
  [file normalize [file join $script_dir include]] \
  [file normalize [file join $repo_root rtl pcie_ctrl]] \
  [file normalize [file join $repo_root rtl phy]] \
] [current_fileset]

set xdc [file join $script_dir constraints vcu118_pcie.xdc]
add_files -fileset constrs_1 -norecurse $xdc

set_property top rivet_vcu118_ep [current_fileset]
if {$gen4} {
  set_property generic {GEN=4} [current_fileset]
}
update_compile_order -fileset sources_1

set do_synth 0
if {!$gen4 && [info exists argv] && [llength $argv] > 0 && [lindex $argv 0] eq "synth"} {
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
