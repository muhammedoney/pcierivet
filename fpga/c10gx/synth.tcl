# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Synthesize an existing Cyclone 10 GX project. Does not create it.
#
#   fpga\c10gx\create_project.cmd
#   fpga\c10gx\synth.cmd
#
#   quartus_sh -t fpga/c10gx/synth.tcl

set script_dir [file normalize [file dirname [info script]]]
set qpf [file join $script_dir build rivet_c10gx.qpf]

if {![file exists $qpf]} {
  error "Missing $qpf. Run create_project.cmd first."
}

package require ::quartus::flow
project_open $qpf
if {[catch {execute_module -tool syn} err]} {
  project_close
  error "Quartus synthesis failed: $err"
}
project_close
puts "PASS: Quartus synthesis complete"
puts "Project: $qpf"
