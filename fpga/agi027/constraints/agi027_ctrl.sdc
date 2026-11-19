# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Gen2 16-bit PIPE clock. clk is a virtual pin, not the R-tile refclk.

create_clock -name clk -period 4.000 [get_ports clk]
set_false_path -from [get_ports reset_n]
derive_clock_uncertainty
