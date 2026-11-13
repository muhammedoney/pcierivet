# VMK180 PCIe edge, lanes 0-3. Part xcvm1802-vsva2197-2MP-e-s.
# Quad 103 is GTY_QUAD_X0Y3 (PG346 CPM0 x4 site on XCVM1802). Lane 0 is
# channel 0 of that quad. REFCLK0 is the buffered slot clock, package
# W39/W40, site GTY_REFCLK_X0Y6 (quad Y * 2).
# PG345 places the serial pins from the quad LOC. Do not also PACKAGE_PIN them.
#
# Lane 0 TX AB41/AB42  RX AB46/AB47
# Lane 1 TX Y41/Y42    RX AA44/AA45
# Lane 2 TX V41/V42    RX Y46/Y47
# Lane 3 TX U43/U44    RX W44/W45

# Prefer the PG345 support hierarchy. Fall back to a single quad_inst.
set gt_quads [get_cells -quiet -hierarchical -filter {NAME =~ *gt_quad_base_0_inst/inst/quad_inst}]
if {[llength $gt_quads] == 0} {
  set gt_quads [get_cells -quiet -hierarchical -filter {NAME =~ *gt_quad_0/inst/quad_inst}]
}
if {[llength $gt_quads] == 0} {
  set gt_quads [get_cells -quiet -hierarchical -filter {NAME =~ *quad_inst}]
}
if {[llength $gt_quads] == 1} {
  set_property LOC GTY_QUAD_X0Y3 [lindex $gt_quads 0]
} else {
  puts "WARN: expected one GT quad for GTY_QUAD_X0Y3, found [llength $gt_quads]: $gt_quads"
}

set ref_bufs [get_cells -quiet -hierarchical -filter {REF_NAME == IBUFDS_GTE5}]
if {[llength $ref_bufs] == 1} {
  set_property LOC GTY_REFCLK_X0Y6 $ref_bufs
} else {
  puts "WARN: expected one IBUFDS_GTE5 for GTY_REFCLK_X0Y6, found [llength $ref_bufs]: $ref_bufs"
}

create_clock -period 10.000 -name sys_clk [get_ports sys_clk_p]

# SW4 / GPIO_PB0, bank 306, active-high lab reset.
# Slot PERST# is PMC MIO38 and is not a port on this PL shell.
set_property PACKAGE_PIN G37 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS18 [get_ports cpu_reset]
set_false_path -from [get_ports cpu_reset]

# GPIO_LED[0:3]: DS6 DS5 DS4 DS3 (UG1411 / VMK180 board XDC)
set_property PACKAGE_PIN H34 [get_ports {led[0]}]
set_property PACKAGE_PIN J33 [get_ports {led[1]}]
set_property PACKAGE_PIN K36 [get_ports {led[2]}]
set_property PACKAGE_PIN L35 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]
set_property DRIVE 8 [get_ports {led[*]}]
