// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Per-lane Gen2 RX descrambler (symbol plane, after PIPE).

module rivet_mac_descrambler #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,
  input  logic [2:0] rate_i = rivet_pkg::RIVET_PIPE_RATE_GEN2,

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] data_i,
  input  logic [2*LANES-1:0]               datak_i,
  input  logic [LANES-1:0]                 valid_i,
  input  logic [LANES-1:0]                 lane_en_i,
  input  logic [LANES-1:0]                 os_block_i = '0,
  input  logic [LANES-1:0]                 block_start_i = '0,

  output logic [PIPE_DATA_WIDTH*LANES-1:0] data_o,
  output logic [2*LANES-1:0]               datak_o,
  output logic [LANES-1:0]                 valid_o,
  output logic [LANES-1:0]                 os_block_o,
  output logic [LANES-1:0]                 block_start_o
);

  import rivet_pkg::*;

  localparam int unsigned SYMS = PIPE_DATA_WIDTH / 8;

`ifndef SYNTHESIS
  initial begin
    // 32 elaborates for Gen3. 64 elaborates for Gen4. The 64-bit block
    // pipe is a later slice.
    if (!(PIPE_DATA_WIDTH == 16 || PIPE_DATA_WIDTH == 32 ||
          PIPE_DATA_WIDTH == 64))
      $error("rivet_mac_descrambler: PIPE_DATA_WIDTH must be 16, 32, or 64 (got %0d)",
             PIPE_DATA_WIDTH);
  end
`endif

  function automatic logic is_short_os_k(input logic [7:0] s);
    return (s == RIVET_SYM_SKP) || (s == RIVET_SYM_FTS) || (s == RIVET_SYM_IDL);
  endfunction

  logic [15:0] lfsr_q     [LANES];
  logic [22:0] lfsr23_q   [LANES];
  logic [22:0] lfsr23_next [LANES];
  // Stay at the seed until the first Gen3 block. The PIPE rate leads the
  // block data by the adapter registers, and those early bytes are not the
  // peer's first block.
  logic        lfsr23_arm_q, lfsr23_arm_n;
  logic [2:0]  rate_q;
  // After the rate becomes Gen4, wait out the adapter pipeline and the
  // electrical-idle gap, then seed on the first new block.
  logic        hold_q, gap_q;
  logic [2:0]  skp_left_q [LANES];
  logic [2:0]  skp_left_n [LANES];
  logic [LANES-1:0] os_q;
  logic [LANES-1:0] start_q;
  logic [4:0]  os_left_q  [LANES];
  logic        com_pend_q [LANES];
  logic [15:0] lfsr_next  [LANES];
  logic [4:0]  os_left_n  [LANES];
  logic        com_pend_n [LANES];
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_d;
  // Registered so the LFSR xor is not in the same cycle as the MAC
  // symbol window and the TLP byte insert (Gen2 pclk is 250 MHz).
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_q;
  logic [2*LANES-1:0]               datak_q;
  logic [LANES-1:0]                 valid_q;

  always_comb begin
    data_d = data_i;
    lfsr23_arm_n = lfsr23_arm_q;
    for (int unsigned l = 0; l < LANES; l++) begin
      lfsr_next[l]   = lfsr_q[l];
      lfsr23_next[l] = lfsr23_q[l];
      os_left_n[l]   = os_left_q[l];
      com_pend_n[l]  = com_pend_q[l];
      skp_left_n[l]  = skp_left_q[l];
      if (rivet_pkg::rivet_pipe_block_rate(rate_i) && valid_i[l] && lane_en_i[l] &&
          !(hold_q && !(gap_q && block_start_i[l])) &&
          (lfsr23_arm_q || block_start_i[l])) begin
        automatic bit skp_word;
        if (!lfsr23_arm_q)
          lfsr23_next[l] = RIVET_LFSR23_SEED;
        lfsr23_arm_n = 1'b1;
        skp_word = (skp_left_q[l] != 3'd0) ||
                   (block_start_i[l] && os_block_i[l] &&
                    (data_i[PIPE_DATA_WIDTH*l +: 8] == RIVET_SYM_SKP_BLK));
        if (os_block_i[l] && skp_word) begin
          if (block_start_i[l])
            skp_left_n[l] = (rate_i == RIVET_PIPE_RATE_GEN4) ? 3'd1 : 3'd3;
          else
            skp_left_n[l] = skp_left_q[l] - 3'd1;
        end else begin
          automatic logic [22:0] st;
          automatic logic [22:0] st4;
          skp_left_n[l] = 3'd0;
          st  = lfsr23_next[l];
          st4 = lfsr23_next[l];
          for (int unsigned s = 0; s < SYMS; s++) begin
            automatic logic [7:0]  din;
            automatic logic [30:0] step;
            din  = data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
            step = rivet_lfsr23_byte(st);
            st   = step[30:8];
            if (s == 3)
              st4 = st;
            if (!os_block_i[l] && !((rate_i == RIVET_PIPE_RATE_GEN3) && (s >= 4)))
              data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = din ^ step[7:0];
          end
          lfsr23_next[l] = ((SYMS > 4) && (rate_i == RIVET_PIPE_RATE_GEN3)) ? st4 : st;
        end
      end else if (valid_i[l] && lane_en_i[l]) begin
        for (int unsigned s = 0; s < SYMS; s++) begin
          automatic logic [7:0]  din;
          automatic logic        is_k;
          automatic logic        in_os;
          automatic logic [23:0] step;
          automatic logic [7:0]  nxt;
          automatic logic        this_os;
          // 32-bit pipe, Gen1/Gen2: only the low 16 bits are symbols.
          if ((PIPE_DATA_WIDTH > 16) && (s >= 2))
            continue;
          din   = data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          is_k  = datak_i[2*l + s];
          in_os = (os_left_n[l] != 5'd0);

          this_os = in_os;

          if (is_k && (din == RIVET_SYM_COM)) begin
            lfsr_next[l]  = RIVET_LFSR_SEED;
            com_pend_n[l] = 1'b0;
            if (((s + 1) < 2) && datak_i[2*l + (s + 1)]) begin
              nxt = data_i[PIPE_DATA_WIDTH*l + 8*(s+1) +: 8];
              if (is_short_os_k(nxt))
                os_left_n[l] = 5'(RIVET_SHORT_OS_LEN - 1);
              else
                os_left_n[l] = 5'(RIVET_TS_LEN - 1);
            end else begin
              // Second 16-bit phase: classify on the next Symbol.
              com_pend_n[l] = 1'b1;
              os_left_n[l]  = 5'd0;
            end
          end else if (com_pend_n[l]) begin
            com_pend_n[l] = 1'b0;
            this_os       = 1'b1;
            if (is_k && is_short_os_k(din))
              os_left_n[l] = 5'(RIVET_SHORT_OS_LEN - 2);
            else
              os_left_n[l] = 5'(RIVET_TS_LEN - 2);
            if (!(is_k && (din == RIVET_SYM_SKP))) begin
              step         = rivet_lfsr_step(lfsr_next[l]);
              lfsr_next[l] = step[23:8];
            end
          end else if (is_k && (din == RIVET_SYM_SKP)) begin
            if (in_os) os_left_n[l] = os_left_n[l] - 5'd1;
          end else begin
            step         = rivet_lfsr_step(lfsr_next[l]);
            lfsr_next[l] = step[23:8];
            if (!is_k && !this_os)
              data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = din ^ step[7:0];
            if (in_os) os_left_n[l] = os_left_n[l] - 5'd1;
          end
        end
      end
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_q  <= '0;
      datak_q <= '0;
      valid_q <= '0;
      os_q    <= '0;
      start_q <= '0;
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]     <= RIVET_LFSR_SEED;
        lfsr23_q[l]   <= RIVET_LFSR23_SEED;
        os_left_q[l]  <= '0;
        com_pend_q[l] <= 1'b0;
        skp_left_q[l] <= '0;
      end
      lfsr23_arm_q <= 1'b0;
      rate_q       <= '0;
      hold_q       <= 1'b0;
      gap_q        <= 1'b0;
    end else begin
      data_q  <= data_d;
      datak_q <= datak_i;
      valid_q <= valid_i;
      os_q    <= os_block_i;
      start_q <= block_start_i;
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]     <= lfsr_next[l];
        lfsr23_q[l]   <= lfsr23_next[l];
        os_left_q[l]  <= os_left_n[l];
        com_pend_q[l] <= com_pend_n[l];
        skp_left_q[l] <= skp_left_n[l];
      end
      if (!rivet_pkg::rivet_pipe_block_rate(rate_i)) begin
        lfsr23_arm_q <= 1'b0;
        for (int unsigned l = 0; l < LANES; l++)
          lfsr23_q[l] <= RIVET_LFSR23_SEED;
      end else if ((rate_i == RIVET_PIPE_RATE_GEN4) &&
                   (rate_q != RIVET_PIPE_RATE_GEN4)) begin
        // Gen4 counts eight symbols. Wait out the adapter pipeline and the
        // electrical-idle gap, then seed on the first new block.
        lfsr23_arm_q <= 1'b0;
        hold_q       <= 1'b1;
        gap_q        <= 1'b0;
      end else if (hold_q) begin
        lfsr23_arm_q <= 1'b0;
        if (!valid_i[0])
          gap_q <= 1'b1;
        if (gap_q && valid_i[0] && block_start_i[0]) begin
          hold_q       <= 1'b0;
          lfsr23_arm_q <= lfsr23_arm_n;
        end
      end else begin
        lfsr23_arm_q <= lfsr23_arm_n;
      end
      rate_q <= rate_i;
    end
  end

  assign data_o        = data_q;
  assign datak_o       = datak_q;
  assign valid_o       = valid_q;
  assign os_block_o    = os_q;
  assign block_start_o = start_q;

endmodule : rivet_mac_descrambler
