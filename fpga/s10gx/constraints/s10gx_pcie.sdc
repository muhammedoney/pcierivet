# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Slot refclk is 100 MHz HCSL. CLK_FPGA_50M is the free-running reset clock.
# Gen2 16-bit PIPE (250 MHz) is a generated clock inside the Native PHY.
# derive_pll_clocks picks it up from the IP SDC.

create_clock -name clk50 -period 20.000 [get_ports clk50]
create_clock -name pcie_refclk -period 10.000 [get_ports pcie_refclk_p]

derive_pll_clocks
derive_clock_uncertainty

set_false_path -from [get_ports {pcie_perstn cpu_resetn user_pb0}]

# Heartbeat and link LEDs are status pins. The heartbeat is clk50.
# link_up and phy_ready are pipe_clk. Both may drive the same LED bank.
set_false_path -to [get_ports {led[*]}]
