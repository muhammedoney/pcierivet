# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pinout from the kit golden_top.qsf (10CX220YF780E5G) and UG-20105.
# Edge lane i is Native PHY logical channel i.
#   lane 0  TX W28/W27  RX V26/V25   bank 1C ch4  (PCS bonding master)
#   lane 1  TX U28/U27  RX T26/T25   bank 1C ch5
#   lane 2  TX R28/R27  RX P26/P25   bank 1D ch0
#   lane 3  TX N28/N27  RX M26/M25   bank 1D ch1
#   refclk  R24/R23     bank 1D bottom refclk, 100 MHz
# Do not also LOC these serial pins onto a second I/O standard.

set_location_assignment PIN_R24 -to pcie_refclk_p
set_location_assignment PIN_R23 -to "pcie_refclk_p(n)"
set_instance_assignment -name IO_STANDARD LVDS -to pcie_refclk_p
set_instance_assignment -name XCVR_REFCLK_PIN_TERMINATION AC_COUPLING -to pcie_refclk_p

set_location_assignment PIN_W28 -to pci_exp_txp[0]
set_location_assignment PIN_W27 -to "pci_exp_txp[0](n)"
set_location_assignment PIN_V26 -to pci_exp_rxp[0]
set_location_assignment PIN_V25 -to "pci_exp_rxp[0](n)"
set_location_assignment PIN_U28 -to pci_exp_txp[1]
set_location_assignment PIN_U27 -to "pci_exp_txp[1](n)"
set_location_assignment PIN_T26 -to pci_exp_rxp[1]
set_location_assignment PIN_T25 -to "pci_exp_rxp[1](n)"
set_location_assignment PIN_R28 -to pci_exp_txp[2]
set_location_assignment PIN_R27 -to "pci_exp_txp[2](n)"
set_location_assignment PIN_P26 -to pci_exp_rxp[2]
set_location_assignment PIN_P25 -to "pci_exp_rxp[2](n)"
set_location_assignment PIN_N28 -to pci_exp_txp[3]
set_location_assignment PIN_N27 -to "pci_exp_txp[3](n)"
set_location_assignment PIN_M26 -to pci_exp_rxp[3]
set_location_assignment PIN_M25 -to "pci_exp_rxp[3](n)"

foreach bus {pci_exp_txp pci_exp_rxp} {
  set_instance_assignment -name IO_STANDARD "HSSI DIFFERENTIAL I/O" -to $bus
}
set_instance_assignment -name XCVR_VCCR_VCCT_VOLTAGE 1_0V -to pci_exp_txp
set_instance_assignment -name XCVR_VCCR_VCCT_VOLTAGE 1_0V -to pci_exp_rxp

# Fabric sideband. Bank 2A / 2L, 1.8 V. LEDs light on '1'.
set_location_assignment PIN_J23  -to clk50
set_location_assignment PIN_AB11 -to pcie_perstn
set_location_assignment PIN_AC12 -to fpga_resetn
set_location_assignment PIN_AE4  -to user_pb0
set_location_assignment PIN_AF6  -to led[0]
set_location_assignment PIN_AE6  -to led[1]
set_location_assignment PIN_AC6  -to led[2]
set_location_assignment PIN_AC7  -to led[3]

foreach pin {clk50 pcie_perstn fpga_resetn user_pb0 led[0] led[1] led[2] led[3]} {
  set_instance_assignment -name IO_STANDARD "1.8 V" -to $pin
}
