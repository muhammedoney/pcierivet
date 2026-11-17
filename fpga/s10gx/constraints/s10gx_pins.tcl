# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Stratix 10 GX FPGA Development Kit (UG-683674, DK-DEV-1SGX-H-A).
# Edge lanes 0-3. Quartus takes the positive serial pin and pairs the
# complement. Refclk is the slot HCSL pair, DC-coupled, terminated on
# the motherboard.
#   lane 0  TX BJ46  RX BH41
#   lane 1  TX BF45  RX BJ43
#   lane 2  TX BG47  RX BG43
#   lane 3  TX BE47  RX BE43
#   refclk  AK41 / AK40
#   PERST#  AJ34, 3.0 V
#   clk50   BH33, CLK_FPGA_50M, 1.8 V
#   USER_PB0 B20, CPU_RESETn A20, both active-low push buttons
#   USER_LED_G0..G3 B19 E17 D18 D19, light when driven low

set_location_assignment PIN_AK41 -to pcie_refclk_p
set_location_assignment PIN_AK40 -to "pcie_refclk_p(n)"
set_instance_assignment -name IO_STANDARD HCSL -to pcie_refclk_p

set_location_assignment PIN_BJ46 -to pci_exp_txp[0]
set_location_assignment PIN_BF45 -to pci_exp_txp[1]
set_location_assignment PIN_BG47 -to pci_exp_txp[2]
set_location_assignment PIN_BE47 -to pci_exp_txp[3]
set_location_assignment PIN_BH41 -to pci_exp_rxp[0]
set_location_assignment PIN_BJ43 -to pci_exp_rxp[1]
set_location_assignment PIN_BG43 -to pci_exp_rxp[2]
set_location_assignment PIN_BE43 -to pci_exp_rxp[3]

foreach bus {pci_exp_txp pci_exp_rxp} {
  set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to $bus
  set_instance_assignment -name XCVR_VCCR_VCCT_VOLTAGE 1_1V -to $bus
}

set_location_assignment PIN_BH33 -to clk50
set_location_assignment PIN_AJ34 -to pcie_perstn
set_location_assignment PIN_A20  -to cpu_resetn
set_location_assignment PIN_B20  -to user_pb0
set_location_assignment PIN_B19  -to led[0]
set_location_assignment PIN_E17  -to led[1]
set_location_assignment PIN_D18  -to led[2]
set_location_assignment PIN_D19  -to led[3]

set_instance_assignment -name IO_STANDARD "1.8 V" -to clk50
set_instance_assignment -name IO_STANDARD "1.8 V" -to cpu_resetn
set_instance_assignment -name IO_STANDARD "1.8 V" -to user_pb0
set_instance_assignment -name IO_STANDARD "1.8 V" -to led
set_instance_assignment -name IO_STANDARD "3.0-V LVCMOS" -to pcie_perstn
