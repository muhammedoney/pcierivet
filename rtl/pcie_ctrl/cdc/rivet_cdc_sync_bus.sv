// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Multi-bit level synchronizer built from tech_cells_generic tc_sync.

module rivet_cdc_sync_bus #(
  parameter int unsigned WIDTH  = 1,
  parameter int unsigned STAGES = 2
) (
  input  logic             dst_clk_i,
  input  logic             dst_rst_ni,
  input  logic [WIDTH-1:0] src_i,
  output logic [WIDTH-1:0] dst_o
);

  for (genvar i = 0; i < WIDTH; i++) begin : g_bit
    tc_sync #(
      .Stages     (STAGES),
      .ResetValue (1'b0)
    ) u_sync (
      .clk_i    (dst_clk_i),
      .rst_ni   (dst_rst_ni),
      .serial_i (src_i[i]),
      .serial_o (dst_o[i])
    );
  end

endmodule : rivet_cdc_sync_bus
