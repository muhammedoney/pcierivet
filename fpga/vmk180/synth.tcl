# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Synthesize an existing VMK180 project. Does not create the project.
#
#   fpga\vmk180\create_project.cmd
#   fpga\vmk180\synth.cmd
#
#   vivado -mode batch -source fpga/vmk180/synth.tcl

set script_dir [file normalize [file dirname [info script]]]
set xpr [file join $script_dir build rivet_vmk180.xpr]

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
