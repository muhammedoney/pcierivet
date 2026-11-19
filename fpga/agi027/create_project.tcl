# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Quartus project for the Agilex 7 FPGA I-Series Development Kit
# (DK-DEV-AGI027-RA-B, AGIB027R29A1E1VB).
#
# This elaborates rivet_pcie_ctrl only. The kit PCIe edge is R-tile PIPE
# SerDes, not 16-bit Gen2 PIPE, so the script assigns no edge pins.
#
#   quartus_sh -t fpga/agi027/create_project.tcl
#   fpga\agi027\create_project.cmd

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set build_dir  [file join $script_dir build]
set part       AGIB027R29A1E1VB
set families {
  "Agilex 7"
  "Agilex 7 FPGA"
}

proc rivet_patch_cdc_2phase {src build regs_svh} {
  set dst_dir [file join $build src]
  set inc_dir [file join $dst_dir common_cells]
  file mkdir $inc_dir
  set dst [file join $dst_dir cc_cdc_2phase.sv]
  set fh [open $src r]
  set text [read $fh]
  close $fh
  if {![string match "*data_t'('0)*" $text]} {
    error "cc_cdc_2phase.sv no longer contains data_t'('0); update the Quartus patch"
  }
  if {![string match {*`include "common_cells/registers.svh"*} $text]} {
    error "cc_cdc_2phase.sv no longer includes common_cells/registers.svh; update the Quartus patch"
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
    if {[string match *.sv $path]} {
      set_global_assignment -name SYSTEMVERILOG_FILE $path
    } else {
      set_global_assignment -name VERILOG_FILE $path
    }
  }
  close $fh
}

file mkdir $build_dir
package require ::quartus::project
cd $build_dir
catch {project_close}

set proj_err ""
set proj_ok 0
set family_used ""
foreach family $families {
  if {![catch {project_new -family $family -part $part -overwrite rivet_agi027} proj_err]} {
    set proj_ok 1
    set family_used $family
    break
  }
  puts "WARN: project_new -family \"$family\" failed: $proj_err"
}
if {!$proj_ok} {
  error "project_new failed for $part:\n$proj_err"
}
puts "rivet: family $family_used part $part"

set_global_assignment -name FAMILY $family_used
set_global_assignment -name DEVICE $part
set_global_assignment -name TOP_LEVEL_ENTITY rivet_agi027_ep
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2005
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 100
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
set_global_assignment -name OPTIMIZATION_TECHNIQUE SPEED
set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"
set_global_assignment -name SEARCH_PATH [file normalize [file join $build_dir src]]
set_global_assignment -name SEARCH_PATH [file normalize [file join $repo_root rtl pcie_ctrl]]

set regs_svh [file normalize [file join $script_dir include common_cells registers.svh]]
rivet_add_filelist $repo_root [file join $repo_root rtl filelist_core.f] $build_dir $regs_svh
set_global_assignment -name SYSTEMVERILOG_FILE [file normalize [file join $script_dir rtl rivet_agi027_ep.sv]]
set_global_assignment -name SDC_FILE [file normalize [file join $script_dir constraints agi027_ctrl.sdc]]

foreach pin {clk reset_n led[0] led[1] led[2] led[3]} {
  set_instance_assignment -name VIRTUAL_PIN ON -to $pin
}

project_close
puts "PASS: Quartus project [file join $build_dir rivet_agi027.qpf]"
puts "Next: fpga\\agi027\\impl.cmd"
