// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Vivado 2024.2 rejects default macro arguments in upstream
// common_cells/registers.svh (`__clk = `REG_DFLT_CLK). The `FF / `FFL
// defines then never take effect, and each call is HDL 9-1206 near '('.
// This file is earlier on the Vivado include path and uses the same
// include guard, so the upstream header is not read. cc_cdc_2phase.sv
// passes clk and reset explicitly.

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
