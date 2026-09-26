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

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] data_i,
  input  logic [2*LANES-1:0]               datak_i,
  input  logic [LANES-1:0]                 valid_i,
  input  logic [LANES-1:0]                 lane_en_i,

  output logic [PIPE_DATA_WIDTH*LANES-1:0] data_o,
  output logic [2*LANES-1:0]               datak_o,
  output logic [LANES-1:0]                 valid_o
);

  import rivet_pkg::*;

  localparam int unsigned SYMS = PIPE_DATA_WIDTH / 8;

`ifndef SYNTHESIS
  initial begin
    if (PIPE_DATA_WIDTH != 16)
      $error("rivet_mac_descrambler: only PIPE_DATA_WIDTH=16 (got %0d)", PIPE_DATA_WIDTH);
  end
`endif

  function automatic logic is_short_os_k(input logic [7:0] s);
    return (s == RIVET_SYM_SKP) || (s == RIVET_SYM_FTS) || (s == RIVET_SYM_IDL);
  endfunction

  logic [15:0] lfsr_q     [LANES];
  logic [4:0]  os_left_q  [LANES];
  logic        com_pend_q [LANES];
  logic [15:0] lfsr_next  [LANES];
  logic [4:0]  os_left_n  [LANES];
  logic        com_pend_n [LANES];
  logic [PIPE_DATA_WIDTH*LANES-1:0] data_d;

  always_comb begin
    data_d = data_i;
    for (int unsigned l = 0; l < LANES; l++) begin
      lfsr_next[l]  = lfsr_q[l];
      os_left_n[l]  = os_left_q[l];
      com_pend_n[l] = com_pend_q[l];
      if (valid_i[l] && lane_en_i[l]) begin
        for (int unsigned s = 0; s < SYMS; s++) begin
          automatic logic [7:0]  din   = data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          automatic logic        is_k  = datak_i[SYMS*l + s];
          automatic logic        in_os = (os_left_n[l] != 5'd0);
          automatic logic [23:0] step;
          automatic logic [7:0]  nxt;
          automatic logic        this_os;

          this_os = in_os;

          if (is_k && (din == RIVET_SYM_COM)) begin
            lfsr_next[l]  = RIVET_LFSR_SEED;
            com_pend_n[l] = 1'b0;
            if ((s + 1 < SYMS) && datak_i[SYMS*l + (s+1)]) begin
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
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]     <= RIVET_LFSR_SEED;
        os_left_q[l]  <= '0;
        com_pend_q[l] <= 1'b0;
      end
    end else begin
      for (int unsigned l = 0; l < LANES; l++) begin
        lfsr_q[l]     <= lfsr_next[l];
        os_left_q[l]  <= os_left_n[l];
        com_pend_q[l] <= com_pend_n[l];
      end
    end
  end

  assign data_o  = data_d;
  assign datak_o = datak_i;
  assign valid_o = valid_i;

endmodule : rivet_mac_descrambler
