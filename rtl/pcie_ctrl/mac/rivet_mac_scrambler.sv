// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Per-lane Gen2 TX scrambler (symbol plane, before PIPE / 8b/10b in PHY).
// Outputs are registered so LFSR XOR does not chain into lane remap / PIPE TX.

module rivet_mac_scrambler #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,
  input  logic [2:0] rate_i = rivet_pkg::RIVET_PIPE_RATE_GEN2,

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
    // 32 elaborates for Gen3. The 128b/130b LFSR is a later slice.
    if (!(PIPE_DATA_WIDTH == 16 || PIPE_DATA_WIDTH == 32))
      $error("rivet_mac_scrambler: PIPE_DATA_WIDTH must be 16 or 32 (got %0d)", PIPE_DATA_WIDTH);
  end
`endif

  logic [15:0] lfsr_q [LANES];
  logic [15:0] lfsr_next [LANES];
  logic [22:0] lfsr23_q [LANES];
  logic [22:0] lfsr23_next [LANES];
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_scr;
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_q;
  logic [2*LANES-1:0]               datak_q;
  logic                             valid_q;

  always_comb begin
    data_scr = data_i;
    for (int unsigned l = 0; l < LANES; l++) begin
      lfsr_next[l] = lfsr_q[l];
      lfsr23_next[l] = lfsr23_q[l];
      if ((rate_i == RIVET_PIPE_RATE_GEN3) && valid_i && lane_en_i[l]) begin
        // One OS flag covers the 4-byte word. SKP does not advance the LFSR.
        automatic logic os_word  = os_d_i[2*l];
        automatic logic skp_word = os_word &&
                                   (data_i[PIPE_DATA_WIDTH*l +: 8] == RIVET_SYM_SKP_BLK);
        if (!skp_word) begin
          for (int unsigned s = 0; s < SYMS; s++) begin
            automatic logic [7:0]  din = data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
            automatic logic [30:0] step;
            step = rivet_lfsr23_byte(lfsr23_next[l]);
            lfsr23_next[l] = step[30:8];
            if (!os_word)
              data_scr[PIPE_DATA_WIDTH*l + 8*s +: 8] = din ^ step[7:0];
          end
        end
      end else if (valid_i && lane_en_i[l]) begin
        for (int unsigned s = 0; s < SYMS; s++) begin
          automatic logic [7:0]  din;
          automatic logic        is_k;
          automatic logic        os_d;
          automatic logic [23:0] step;
          // 32-bit pipe, Gen1/Gen2: only the low 16 bits are symbols.
          if ((PIPE_DATA_WIDTH == 32) && (s >= 2))
            continue;
          din  = data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          is_k = datak_i[2*l + s];
          os_d = os_d_i[2*l + s];
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
      data_q  <= '0;
      datak_q <= '0;
      valid_q <= 1'b0;
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]   <= RIVET_LFSR_SEED;
        lfsr23_q[l] <= RIVET_LFSR23_SEED;
      end
    end else begin
      data_q  <= data_scr;
      datak_q <= datak_i;
      valid_q <= valid_i;
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]   <= lfsr_next[l];
        lfsr23_q[l] <= lfsr23_next[l];
      end
    end
  end

  assign data_o  = data_q;
  assign datak_o = datak_q;
  assign valid_o = valid_q;

endmodule : rivet_mac_scrambler
