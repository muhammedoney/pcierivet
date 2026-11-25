# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Synthesize an existing VCU118 project. Does not create the project.
#
#   fpga\vcu118\create_project.cmd
#   fpga\vcu118\synth.cmd
#
#   vivado -mode batch -source fpga/vcu118/synth.tcl

set script_dir [file normalize [file dirname [info script]]]
set gen4 0
if {[info exists argv] && [llength $argv] == 2 &&
    [lindex $argv 0] eq "4" && [lindex $argv 1] eq "ep"} {
  set gen4 1
} elseif {[info exists argv] && [llength $argv] != 0} {
  error "usage: no arguments, or: 4 ep"
}
set build_dir [file join $script_dir build [expr {$gen4 ? "gen4_ep" : ""}]]
set xpr [file join $build_dir rivet_vcu118.xpr]

if {![file exists $xpr]} {
  error "Missing $xpr. Run create_project.cmd first."
}

open_project $xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  set st [get_property STATUS [get_runs synth_1]]
  error "synth_1 failed ($st). See [file join $script_dir build]"
}
puts "PASS: synth_1 complete"
puts "Project: $xpr"
close_project
