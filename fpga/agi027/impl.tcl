# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Compile the Agilex controller-only project: synthesis, fit, timing, assembly.
# Does not create the project. A missing license is expected to fail the fitter.
#
#   fpga\agi027\impl.cmd

set script_dir [file normalize [file dirname [info script]]]
set qpf [file join $script_dir build rivet_agi027.qpf]

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
