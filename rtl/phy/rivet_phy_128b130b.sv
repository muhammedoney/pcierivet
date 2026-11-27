// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// 128b/130b gearbox. Gen3 uses a 32-bit PMA word. Gen4 uses 64.
// The sync header is the first two bits on the wire. Sixteen Gen3
// blocks, or thirty-two Gen4 blocks, leave one PMA word of residue.
// That word is the PIPE idle cycle. RX rebuilds the same 64-valid
// then one-idle cadence after block lock.

module rivet_phy_128b130b
  import rivet_pkg::*;
#(
  parameter int unsigned PIPE_W = 32
) (
  input  logic                    pclk,
  input  logic                    preset_n,
  input  logic                    enable,
  input  logic [2:0]              rate,

  input  logic [PIPE_W-1:0]       txdata,
  input  logic                    txdata_valid,
  input  logic                    txstart_block,
  input  logic [1:0]              txsync_header,
  output logic [63:0]             pma_txdata,

  input  logic [63:0]             pma_rxdata,
  output logic [PIPE_W-1:0]       rxdata,
  output logic                    rxdata_valid,
  output logic [1:0]              rxstart_block,
  output logic [1:0]              rxsync_header
);

  wire [6:0] word_w = ((rate == RIVET_PIPE_RATE_GEN4) && (PIPE_W >= 64)) ? 7'd64 : 7'd32;
  wire [2:0] words_per = (word_w == 7'd64) ? 3'd2 : 3'd4;

  logic [63:0] tx_w;
  always_comb begin
    tx_w = '0;
    tx_w[PIPE_W-1:0] = txdata;
  end

  function automatic logic hdr_ok(input logic [1:0] h);
    return (h == 2'b01) || (h == 2'b10);
  endfunction

  logic [127:0] acc_q;
  logic [7:0]   tn_q;
  logic [255:0] q_q;
  logic [8:0]   nq_q;
  logic         locked_q;
  logic         need_q;
  logic [2:0]   left_q;
  logic [1:0]   hdr_q;
  logic [6:0]   count_q;
  logic         idle_q;

  logic [127:0] acc_n;
  logic [7:0]   tn_n;
  logic [63:0]  tx_word_c;
  logic [255:0] q_n;
  logic [8:0]   nq_n;
  logic         locked_n;
  logic         need_n;
  logic [2:0]   left_n;
  logic [1:0]   hdr_n;
  logic [6:0]   count_n;
  logic         idle_n;
  logic [PIPE_W-1:0] rxdata_n;
  logic         rxvalid_n;
  logic [1:0]   rxstart_n;
  logic [1:0]   rxsync_n;

  // One PMA word per cycle. A start cycle pushes the header plus one
  // data word, so the residue grows by two bits. The idle cycle pushes
  // nothing and flushes a full residue word.
  always_comb begin
    logic [65:0] push_bits;
    logic [6:0]  push_n;
    acc_n     = acc_q;
    tn_n      = tn_q;
    tx_word_c = '0;
    push_bits = '0;
    push_n    = '0;
    if (enable && txdata_valid && txstart_block) begin
      push_bits = {tx_w, txsync_header};
      push_n    = word_w + 7'd2;
    end else if (enable && txdata_valid) begin
      push_bits = {2'b0, tx_w};
      push_n    = word_w;
    end
    if (enable && (push_n != 7'd0)) begin
      acc_n = acc_q | (128'(push_bits) << tn_q);
      tn_n  = tn_q + {1'b0, push_n};
    end
    if (enable && (tn_n >= {1'b0, word_w})) begin
      tx_word_c = acc_n[63:0];
      if (word_w == 7'd32)
        tx_word_c[63:32] = '0;
      acc_n = acc_n >> word_w;
      tn_n  = tn_n - {1'b0, word_w};
    end
    if (!enable) begin
      acc_n     = '0;
      tn_n      = '0;
      tx_word_c = '0;
    end
  end

  assign pma_txdata = tx_word_c;

  always_comb begin
    logic [63:0] rx_word;
    int unsigned guard;
    q_n       = q_q;
    nq_n      = nq_q;
    locked_n  = locked_q;
    need_n    = need_q;
    left_n    = left_q;
    hdr_n     = hdr_q;
    count_n   = count_q;
    idle_n    = idle_q;
    rxdata_n  = '0;
    rxvalid_n = 1'b0;
    rxstart_n = '0;
    rxsync_n  = '0;
    rx_word = pma_rxdata;
    if (word_w != 7'd64)
      rx_word[63:32] = '0;

    if (enable && ((locked_q || (|rx_word) || (nq_q != 9'd0)) && (nq_q <= 9'd192))) begin
      q_n  = q_q | (256'(rx_word) << nq_q);
      nq_n = nq_q + {2'b0, word_w};
    end

    if (enable && !locked_n) begin
      for (guard = 0; guard < 192; guard++) begin
        if (!locked_n && (nq_n >= 9'd132)) begin
          if (hdr_ok(q_n[1:0]) && hdr_ok(q_n[131:130]))
            locked_n = 1'b1;
          else begin
            q_n  = q_n >> 1;
            nq_n = nq_n - 9'd1;
          end
        end
      end
    end

    if (enable && locked_n && idle_n) begin
      idle_n = 1'b0;
    end else if (enable && locked_n) begin
      if (need_n && (nq_n >= 9'd2)) begin
        if (!hdr_ok(q_n[1:0])) begin
          locked_n = 1'b0;
          q_n      = q_n >> 2;
          nq_n     = nq_n - 9'd2;
          need_n   = 1'b1;
        end else begin
          hdr_n  = q_n[1:0];
          q_n    = q_n >> 2;
          nq_n   = nq_n - 9'd2;
          need_n = 1'b0;
          left_n = words_per;
        end
      end
      if (locked_n && !need_n && (left_n != 3'd0) && (nq_n >= {2'b0, word_w})) begin
        rxvalid_n = 1'b1;
        rxsync_n  = hdr_n;
        rxstart_n = (left_n == words_per) ? 2'b01 : 2'b00;
        if ((word_w == 7'd64) && (PIPE_W >= 64))
          rxdata_n = q_n[PIPE_W-1:0];
        else
          rxdata_n[31:0] = q_n[31:0];
        q_n    = q_n >> word_w;
        nq_n   = nq_n - {2'b0, word_w};
        left_n = left_n - 3'd1;
        if (left_n == 3'd0)
          need_n = 1'b1;
        count_n = count_n + 7'd1;
        if (count_n == 7'd64) begin
          count_n = '0;
          idle_n  = 1'b1;
        end
      end
    end

    if (!enable) begin
      q_n       = '0;
      nq_n      = '0;
      locked_n  = 1'b0;
      need_n    = 1'b1;
      left_n    = '0;
      hdr_n     = '0;
      count_n   = '0;
      idle_n    = 1'b0;
      rxdata_n  = '0;
      rxvalid_n = 1'b0;
      rxstart_n = '0;
      rxsync_n  = '0;
    end
  end

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      acc_q         <= '0;
      tn_q          <= '0;
      q_q           <= '0;
      nq_q          <= '0;
      locked_q      <= 1'b0;
      need_q        <= 1'b1;
      left_q        <= '0;
      hdr_q         <= '0;
      count_q       <= '0;
      idle_q        <= 1'b0;
      rxdata        <= '0;
      rxdata_valid  <= 1'b0;
      rxstart_block <= '0;
      rxsync_header <= '0;
    end else begin
      acc_q         <= acc_n;
      tn_q          <= tn_n;
      q_q           <= q_n;
      nq_q          <= nq_n;
      locked_q      <= locked_n;
      need_q        <= need_n;
      left_q        <= left_n;
      hdr_q         <= hdr_n;
      count_q       <= count_n;
      idle_q        <= idle_n;
      rxdata        <= rxdata_n;
      rxdata_valid  <= rxvalid_n;
      rxstart_block <= rxstart_n;
      rxsync_header <= rxsync_n;
    end
  end

endmodule : rivet_phy_128b130b
