// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Synthesis tools reject default macro arguments in upstream
// common_cells/registers.svh (`__clk = `REG_DFLT_CLK). The `FF / `FFL
// defines then never take effect. This header has no defaults.
// create_project.tcl copies it to build/src/common_cells/registers.svh
// so `include "common_cells/registers.svh" resolves next to the patched
// cc_cdc_2phase.sv. Simulation still uses the upstream header.

`ifndef COMMON_CELLS_REGISTERS_SVH_
`define COMMON_CELLS_REGISTERS_SVH_

`define FF(__q, __d, __reset_value, __clk, __arst_n) \
  always_ff @(posedge (__clk) or negedge (__arst_n)) begin \
    if (!__arst_n) begin \
      __q <= (__reset_value); \
    end else begin \
      __q <= (__d); \
    end \
  end

`define FFL(__q, __d, __load, __reset_value, __clk, __arst_n) \
  always_ff @(posedge (__clk) or negedge (__arst_n)) begin \
    if (!__arst_n) begin \
      __q <= (__reset_value); \
    end else begin \
      if (__load) begin \
        __q <= (__d); \
      end \
    end \
  end

`endif
