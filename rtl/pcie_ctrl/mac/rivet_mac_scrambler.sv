// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Per-lane Gen2 TX scrambler (symbol plane, before PIPE / 8b/10b in PHY).

module rivet_mac_scrambler #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] data_i,
  input  logic [2*LANES-1:0]               datak_i,
  input  logic [2*LANES-1:0]               os_d_i,
  input  logic                             valid_i,
  input  logic [LANES-1:0]                 lane_en_i,

  output logic [PIPE_DATA_WIDTH*LANES-1:0] data_o,
  output logic [2*LANES-1:0]               datak_o,
  output logic                             valid_o
);

  import rivet_pkg::*;

  localparam int unsigned SYMS = PIPE_DATA_WIDTH / 8;

`ifndef SYNTHESIS
  initial begin
    if (PIPE_DATA_WIDTH != 16)
      $error("rivet_mac_scrambler: only PIPE_DATA_WIDTH=16 (got %0d)", PIPE_DATA_WIDTH);
  end
`endif

  logic [15:0] lfsr_q [LANES];
  logic [15:0] lfsr_next [LANES];
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_scr;

  always_comb begin
    data_scr = data_i;
    for (int unsigned l = 0; l < LANES; l++) begin
      lfsr_next[l] = lfsr_q[l];
      if (valid_i && lane_en_i[l]) begin
        for (int unsigned s = 0; s < SYMS; s++) begin
          automatic logic [7:0]  din  = data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          automatic logic        is_k = datak_i[SYMS*l + s];
          automatic logic        os_d = os_d_i[SYMS*l + s];
          automatic logic [23:0] step;
          if (is_k && (din == RIVET_SYM_COM)) begin
            lfsr_next[l] = RIVET_LFSR_SEED;
          end else if (!(is_k && (din == RIVET_SYM_SKP))) begin
            step = rivet_lfsr_step(lfsr_next[l]);
            lfsr_next[l] = step[23:8];
            if (!is_k && !os_d)
              data_scr[PIPE_DATA_WIDTH*l + 8*s +: 8] = din ^ step[7:0];
          end
        end
      end
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned l = 0; l < LANES; l++) lfsr_q[l] <= RIVET_LFSR_SEED;
    end else begin
      for (int unsigned l = 0; l < LANES; l++) lfsr_q[l] <= lfsr_next[l];
    end
  end

  assign data_o  = data_scr;
  assign datak_o = datak_i;
  assign valid_o = valid_i;

endmodule : rivet_mac_scrambler
