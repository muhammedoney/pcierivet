# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Stratix 10 Reset Release IP. ninit_done stays high until the SDM
# finishes device initialization, then falls. The shell holds user reset
# until that fall. Exactly one instance is required (RES-10204).

package require qsys
if {![info exists ::rivet_s10gx_build]} {
  error "create_project.tcl must pass ::rivet_s10gx_build with qsys-script --cmd"
}
set build $::rivet_s10gx_build
file mkdir $build

create_system rivet_s10gx_init
set_project_property DEVICE 1SG280HU2F50E2VG
set_project_property DEVICE_FAMILY {Stratix 10}
set_project_property HIDE_FROM_IP_CATALOG true
catch {set_use_testbench_naming_pattern 0 {}}

add_instance reset_release altera_s10_user_rst_clkgate
set_instance_parameter_value reset_release outputType {Conduit Interface}
set_instance_property reset_release AUTO_EXPORT true

sync_sysinfo_parameters
save_system [file join $build rivet_s10gx_init.ip]
puts "rivet: wrote [file join $build rivet_s10gx_init.ip]"
