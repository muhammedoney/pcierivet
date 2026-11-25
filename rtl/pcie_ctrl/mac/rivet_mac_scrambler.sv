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
  input  logic                             blk_start_i = 1'b0,
  input  logic [LANES-1:0]                 lane_en_i,

  output logic [PIPE_DATA_WIDTH*LANES-1:0] data_o,
  output logic [2*LANES-1:0]               datak_o,
  output logic                             valid_o,
  output logic                             os_o,
  output logic                             blk_start_o
);

  import rivet_pkg::*;

  localparam int unsigned SYMS = PIPE_DATA_WIDTH / 8;

`ifndef SYNTHESIS
  initial begin
    // 32 elaborates for Gen3. 64 elaborates for Gen4. The 64-bit block
    // pipe is a later slice.
    if (!(PIPE_DATA_WIDTH == 16 || PIPE_DATA_WIDTH == 32 ||
          PIPE_DATA_WIDTH == 64))
      $error("rivet_mac_scrambler: PIPE_DATA_WIDTH must be 16, 32, or 64 (got %0d)",
             PIPE_DATA_WIDTH);
  end
`endif

  logic [15:0] lfsr_q [LANES];
  logic [15:0] lfsr_next [LANES];
  logic [22:0] lfsr23_q [LANES];
  logic [22:0] lfsr23_next [LANES];
  // First Gen3 data word reloads the seed. Training blocks advance a
  // different count than the bytes a partner sees on the pipe.
  logic        lfsr23_data_q, lfsr23_data_n;
  logic [2:0]  rate_q;
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_scr;
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_q;
  logic [2*LANES-1:0]               datak_q;
  logic                             valid_q;
  logic                             os_q;
  logic                             blk_start_q;

  always_comb begin
    data_scr = data_i;
    lfsr23_data_n = lfsr23_data_q;
    for (int unsigned l = 0; l < LANES; l++) begin
      lfsr_next[l] = lfsr_q[l];
      lfsr23_next[l] = lfsr23_q[l];
      if (rivet_pkg::rivet_pipe_block_rate(rate_i) && valid_i && lane_en_i[l]) begin
        // One OS flag covers the 4-byte word. SKP does not advance the LFSR.
        automatic logic os_word  = os_d_i[2*l];
        automatic logic skp_word = os_word &&
                                   (data_i[PIPE_DATA_WIDTH*l +: 8] == RIVET_SYM_SKP_BLK);
        if (!skp_word) begin
          // Reload on a block boundary only. A mid-block reseed after the
          // Gen4 rate change leaves the peer, which arms on start_block,
          // one clock off for the rest of the link.
          if (!os_word && !lfsr23_data_q && blk_start_i)
            lfsr23_next[l] = RIVET_LFSR23_SEED;
          if (!os_word && (lfsr23_data_q || blk_start_i))
            lfsr23_data_n = 1'b1;
          for (int unsigned s = 0; s < SYMS; s++) begin
            automatic logic [7:0]  din;
            automatic logic [30:0] step;
            // Gen3 on a 64-bit pipe uses the low four symbols.
            if ((rate_i == RIVET_PIPE_RATE_GEN3) && (s >= 4))
              continue;
            din = data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
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
          if ((PIPE_DATA_WIDTH > 16) && (s >= 2))
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
      valid_q     <= 1'b0;
      os_q        <= 1'b0;
      blk_start_q <= 1'b0;
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]   <= RIVET_LFSR_SEED;
        lfsr23_q[l] <= RIVET_LFSR23_SEED;
      end
      lfsr23_data_q <= 1'b0;
      rate_q        <= rivet_pkg::RIVET_PIPE_RATE_GEN1;
    end else begin
      data_q      <= data_scr;
      datak_q     <= datak_i;
      valid_q     <= valid_i;
      os_q        <= rivet_pkg::rivet_pipe_block_rate(rate_i) ? (|os_d_i) : 1'b0;
      blk_start_q <= rivet_pkg::rivet_pipe_block_rate(rate_i) ? blk_start_i : 1'b0;
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]   <= lfsr_next[l];
        lfsr23_q[l] <= lfsr23_next[l];
      end
      // The first Gen4 data word reloads the seed. A continuous LFSR
      // would still be on the Gen3 schedule.
      if ((rate_i == rivet_pkg::RIVET_PIPE_RATE_GEN4) &&
          (rate_q != rivet_pkg::RIVET_PIPE_RATE_GEN4))
        lfsr23_data_q <= 1'b0;
      else if (!rivet_pkg::rivet_pipe_block_rate(rate_i))
        lfsr23_data_q <= 1'b0;
      else
        lfsr23_data_q <= lfsr23_data_n;
      rate_q <= rate_i;
    end
  end

  assign data_o      = data_q;
  assign datak_o     = datak_q;
  assign valid_o     = valid_q;
  assign os_o        = os_q;
  assign blk_start_o = blk_start_q;

endmodule : rivet_mac_scrambler
