# VMK180 PCIe edge, lanes 0-3. Part xcvm1802-vsva2197-2MP-e-S.
# Quad 103 is GTY_QUAD_X0Y3 (PG346 CPM0 x4 site on XCVM1802). Lane 0 is
# channel 0 of that quad. REFCLK0 is the buffered slot clock, package
# W39/W40, site GTY_REFCLK_X0Y6 (quad Y * 2).
# PG345 places the serial pins from the quad LOC. Do not also PACKAGE_PIN them.
#
# Lane 0 TX AB41/AB42  RX AB46/AB47
# Lane 1 TX Y41/Y42    RX AA44/AA45
# Lane 2 TX V41/V42    RX Y46/Y47
# Lane 3 TX U43/U44    RX W44/W45

# Vivado rejects Tcl "if" in this XDC (Designutils 20-1307) and then
# skips the LOC. One GTY quad and one IBUFDS_GTE5 are required.
set_property LOC GTY_QUAD_X0Y3 [get_cells -hierarchical -filter {NAME =~ *gt_quad_base_0_inst/inst/quad_inst}]
set_property LOC GTY_REFCLK_X0Y6 [get_cells -hierarchical -filter {REF_NAME == IBUFDS_GTE5}]

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
