# VCU118 PCIe edge, lanes 0-3 (quad 227). Part xcvu9p-flga2104-2L-e.
# Lane 0 of the slot is GTYE4_CHANNEL_X1Y35. create_project.tcl places
# pcie_phy_0 lane0 on that site so these pins and the IP LOC agree.
# Pins from the VCU118 edge map (MGTY*227 / MGTREFCLK0_227 / PERST AM17).

# 100 MHz PCIe reference clock (MGTREFCLK0P/N_227)
set_property PACKAGE_PIN AC9 [get_ports sys_clk_p]
set_property PACKAGE_PIN AC8 [get_ports sys_clk_n]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk_p]

# Slot PERST# (active-low) and CPU_RESET SW9 (active-high)
set_property PACKAGE_PIN AM17 [get_ports pcie_perst_n]
set_property IOSTANDARD LVCMOS18 [get_ports pcie_perst_n]
set_property PULLUP true [get_ports pcie_perst_n]

set_property PACKAGE_PIN L19 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS12 [get_ports cpu_reset]

set_false_path -from [get_ports {pcie_perst_n cpu_reset}]

# Serial pairs. Lane index is the slot lane (0 = upstream lane 0).
set_property PACKAGE_PIN AA4 [get_ports {pci_exp_rxp[0]}]
set_property PACKAGE_PIN AA3 [get_ports {pci_exp_rxn[0]}]
set_property PACKAGE_PIN Y7  [get_ports {pci_exp_txp[0]}]
set_property PACKAGE_PIN Y6  [get_ports {pci_exp_txn[0]}]

set_property PACKAGE_PIN AB2 [get_ports {pci_exp_rxp[1]}]
set_property PACKAGE_PIN AB1 [get_ports {pci_exp_rxn[1]}]
set_property PACKAGE_PIN AB7 [get_ports {pci_exp_txp[1]}]
set_property PACKAGE_PIN AB6 [get_ports {pci_exp_txn[1]}]

set_property PACKAGE_PIN AC4 [get_ports {pci_exp_rxp[2]}]
set_property PACKAGE_PIN AC3 [get_ports {pci_exp_rxn[2]}]
set_property PACKAGE_PIN AD7 [get_ports {pci_exp_txp[2]}]
set_property PACKAGE_PIN AD6 [get_ports {pci_exp_txn[2]}]

set_property PACKAGE_PIN AD2 [get_ports {pci_exp_rxp[3]}]
set_property PACKAGE_PIN AD1 [get_ports {pci_exp_rxn[3]}]
set_property PACKAGE_PIN AF7 [get_ports {pci_exp_txp[3]}]
set_property PACKAGE_PIN AF6 [get_ports {pci_exp_txn[3]}]

# GPIO LEDs DS37..DS30 (UG1224)
set_property PACKAGE_PIN AT32 [get_ports {led[0]}]
set_property PACKAGE_PIN AV34 [get_ports {led[1]}]
set_property PACKAGE_PIN AY30 [get_ports {led[2]}]
set_property PACKAGE_PIN BB32 [get_ports {led[3]}]
set_property PACKAGE_PIN BF32 [get_ports {led[4]}]
set_property PACKAGE_PIN AU37 [get_ports {led[5]}]
set_property PACKAGE_PIN AV36 [get_ports {led[6]}]
set_property PACKAGE_PIN BA37 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS12 [get_ports {led[*]}]
set_property DRIVE 8 [get_ports {led[*]}]
