# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Implement an existing VMK180 project and write the bitstream.
# Does not create the project.
#
#   fpga\vmk180\impl.cmd
#
#   vivado -mode batch -source fpga/vmk180/impl.tcl

set script_dir [file normalize [file dirname [info script]]]
set xpr [file join $script_dir build rivet_vmk180.xpr]

if {![file exists $xpr]} {
  error "Missing $xpr. Run create_project.cmd first."
}

open_project $xpr

set syn  [get_runs synth_1]
set impl [get_runs impl_1]

if {[catch {set_property strategy Flow_PerfOptimized_high $syn} err]} {
  puts "WARN: synth strategy not applied: $err"
}

if {[catch {set_property strategy Performance_ExplorePostRoutePhysOpt $impl} err]} {
  puts "WARN: $err"
  puts "WARN: falling back to Performance_Explore"
  set_property strategy Performance_Explore $impl
}

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
if {[catch {wait_on_run impl_1} err]} {
  puts "WARN: wait_on_run: $err"
}

set st   [get_property STATUS   $impl]
set prog [get_property PROGRESS $impl]
puts "impl_1 status=$st progress=$prog"
if {$prog ne "100%"} {
  puts "ERROR: impl_1 failed ($st). See [file join $script_dir build]"
  catch {close_project}
  exit 1
}

set wns [get_property STATS.WNS $impl]
set tns [get_property STATS.TNS $impl]
set whs [get_property STATS.WHS $impl]
puts "WNS=$wns ns  TNS=$tns ns  WHS=$whs ns"
if {$wns < 0.0} {
  error "timing not met: WNS=$wns TNS=$tns"
}

puts "PASS: bitstream timing closed"
puts "Project: $xpr"
close_project
