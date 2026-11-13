# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# DK-DEV-10CX220-B clocks. PCIe refclk is 100 MHz HCSL from the edge.
# The on-chip refclk buffer uses AC coupling (kit golden_top). The board
# route itself is DC-coupled; that is a different statement from this assignment.

create_clock -name clk50 -period 20.000 [get_ports clk50]
create_clock -name pcie_refclk -period 10.000 [get_ports pcie_refclk_p]

derive_pll_clocks
derive_clock_uncertainty

set_false_path -from [get_ports {pcie_perstn fpga_resetn user_pb0}]
