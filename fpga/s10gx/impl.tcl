# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Full compile of the Stratix 10 GX project: synthesis, fit, timing, bitstream.
#   fpga\s10gx\create_project.cmd
#   fpga\s10gx\impl.cmd

set script_dir [file normalize [file dirname [info script]]]
set qpf [file join $script_dir build rivet_s10gx.qpf]

if {![file exists $qpf]} {
  error "Missing $qpf. Run create_project.cmd first."
}

package require ::quartus::flow
project_open $qpf
foreach tool {syn fit sta asm} {
  puts "rivet: execute_module $tool"
  if {[catch {execute_module -tool $tool} err]} {
    project_close
    error "Quartus $tool failed: $err"
  }
}
project_close
puts "PASS: Quartus bitstream complete"
puts "Project: $qpf"
