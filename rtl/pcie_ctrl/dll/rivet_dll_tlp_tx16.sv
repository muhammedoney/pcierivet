// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Frame a TL payload with Seq# + LCRC and emit 16-byte MAC beats.
// Beats are cut through: the header goes out while later payload beats
// are still arriving. Replay capture copies the emitted bytes beside
// that path. A full capture slot may pause the pipe. Capture of an
// earlier beat does not.

module rivet_dll_tlp_tx16 #(
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         enable_i,
  input  logic         replay_en_i,

  input  logic         tl_valid_i,
  output logic         tl_ready_o,
  input  logic [15:0]  tl_len_i,
  input  logic         tl_last_i,
  input  logic [127:0] tl_word_i,
  output logic [15:0]  tl_word_idx_o,

  input  logic         replay_valid_i,
  output logic         replay_ready_o,
  input  logic [11:0]  replay_seq_i,
  input  logic [15:0]  replay_len_i,
  input  logic [63:0]  replay_word_i,
  output logic [15:0]  replay_word_idx_o,

  output logic         cap_valid_o,
  input  logic         cap_ready_i,
  output logic [63:0]  cap_data_o,
  output logic         cap_last_o,
  output logic [11:0]  cap_seq_o,
  output logic [15:0]  cap_len_o,
  output logic         cap_hi_valid_o,
  output logic [63:0]  cap_hi_data_o,

  output rivet_pkg::rivet_dll_mac_tx_beat_t beat_o,
  output logic                              beat_valid_o,
  input  logic                              beat_ready_i,

  output logic         idle_o,
  output logic [11:0]  next_tx_seq_o
);

  import rivet_pkg::*;

  localparam int unsigned BEAT_B = 16;
  localparam int unsigned ACC_B  = 32;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_LIVE = 2'd1,
    ST_EMIT = 2'd2
  } state_e;

  state_e       state_q;
  logic [11:0]  seq_q, next_seq_q;
  logic [31:0]  crc_q;
  logic [15:0]  rem_q, frame_len_q, pay_q;
  logic [15:0]  word_idx_q;
  logic [255:0] acc_q;
  logic [5:0]   acc_n_q;
  // Bytes from the front of acc through the end of the frame. 0 means
  // the open frame has not taken its last beat yet.
  logic [5:0]   eop_n_q;
  logic         pkt_q;
  logic [127:0] hold_q;
  logic [63:0]  cap_acc_q;
  logic [3:0]   cap_n_q;
  logic         cap_pend_q, cap_last_q, cap_hi_q;
  logic [63:0]  cap_word_q, cap_hi_word_q;
  logic         pref_q, emit_sop_q, replay_q;
  logic         start_rp;

  logic         cap_free;
  logic         live_v;
  logic         live_eop;
  logic [4:0]   live_n;
  logic [5:0]   left_n;
  logic         eop_block;
  logic [15:0]  room_add;

  assign next_tx_seq_o  = next_seq_q;
  assign idle_o         = (state_q == ST_IDLE) && !cap_pend_q && (acc_n_q == 6'd0);
  assign cap_valid_o    = cap_pend_q;
  assign cap_data_o     = cap_word_q;
  assign cap_last_o     = cap_last_q;
  assign cap_seq_o      = seq_q;
  assign cap_len_o      = frame_len_q;
  assign cap_hi_valid_o = cap_hi_q;
  assign cap_hi_data_o  = cap_hi_word_q;
  assign tl_word_idx_o  = 16'd0;

  assign start_rp = (state_q == ST_IDLE) && pref_q && replay_en_i &&
                    replay_valid_i && !cap_pend_q && (acc_n_q == 6'd0);

  assign replay_word_idx_o = start_rp ? 16'd1 :
                             ((state_q == ST_EMIT) ? word_idx_q : 16'd0);

  assign replay_ready_o = (state_q == ST_EMIT) && beat_valid_o && beat_ready_i &&
                          beat_o.eop;

  assign cap_free = !cap_pend_q || cap_ready_i;

  // A new packet needs 2 sequence bytes + a 16-byte beat + 4 LCRC bytes.
  // An open packet needs at most one more beat and the LCRC.
  assign room_add = pkt_q ? 16'd20 : 16'd22;

  always_comb begin
    live_v   = 1'b0;
    live_eop = 1'b0;
    live_n   = '0;
    if ((state_q != ST_EMIT) && cap_free && (acc_n_q != 6'd0)) begin
      if ((acc_n_q >= 6'(BEAT_B)) && ((eop_n_q == 6'd0) || (eop_n_q > 6'(BEAT_B)))) begin
        live_v   = 1'b1;
        live_n   = 5'(BEAT_B);
        live_eop = 1'b0;
      end else if ((eop_n_q != 6'd0) && (eop_n_q <= 6'(BEAT_B)) &&
                   (acc_n_q >= eop_n_q)) begin
        live_v   = 1'b1;
        live_n   = eop_n_q[4:0];
        live_eop = 1'b1;
      end
    end
  end

  always_comb begin
    left_n = acc_n_q;
    if (live_v && beat_ready_i)
      left_n = acc_n_q - {1'b0, live_n};
    // Do not append the next packet behind a frame that still has more
    // than this cycle's beat left to send.
    eop_block = (eop_n_q != 6'd0) && !(live_v && live_eop && beat_ready_i);
    tl_ready_o = enable_i && !replay_en_i && !start_rp &&
                 (state_q != ST_EMIT) && !eop_block &&
                 (({1'b0, left_n} + room_add[6:0]) <= 7'(ACC_B)) &&
                 ((pay_q + room_add) <= 16'(SLOT_BYTES));
  end

  function automatic logic [15:0] len_to_keep16(input logic [15:0] n);
    logic [15:0] k;
    k = '0;
    for (int unsigned i = 0; i < 16; i++)
      if (16'(i) < n)
        k[i] = 1'b1;
    return k;
  endfunction

  function automatic logic [31:0] fold16(
      input logic [31:0]  crc,
      input logic [127:0] data,
      input logic [4:0]   n);
    logic [31:0] c;
    logic [3:0]  n0, n1;
    c  = crc;
    n0 = (n >= 5'd8) ? 4'd8 : n[3:0];
    n1 = (n > 5'd8) ? 4'(n - 5'd8) : 4'd0;
    if (n0 != 4'd0)
      c = rivet_crc32_fold(c, data[63:0], n0);
    if (n1 != 4'd0)
      c = rivet_crc32_fold(c, data[127:64], n1);
    return c;
  endfunction

  typedef struct packed {
    logic [63:0] acc;
    logic [3:0]  acc_n;
    logic        pend;
    logic [63:0] word;
    logic        word_last;
  } pack_r_t;

  function automatic pack_r_t pack_bytes(
      input logic [63:0] acc_in,
      input logic [3:0]  acc_n_in,
      input logic [63:0] src,
      input logic [3:0]  n,
      input logic        last);
    logic [127:0] wide;
    logic [4:0]   sum;
    pack_r_t r;
    wide = {64'h0, acc_in};
    for (int unsigned i = 0; i < 8; i++) begin
      if (4'(i) < n)
        wide[8*(32'(acc_n_in) + i) +: 8] = src[8*i +: 8];
    end
    sum = {1'b0, acc_n_in} + {1'b0, n};
    r = '0;
    if (sum >= 5'd8) begin
      r.pend      = 1'b1;
      r.word      = wide[63:0];
      r.acc       = wide[127:64];
      r.acc_n     = 4'(sum - 5'd8);
      r.word_last = last && (sum == 5'd8);
    end else if (last && (sum != 5'd0)) begin
      r.pend      = 1'b1;
      r.word      = wide[63:0];
      r.word_last = 1'b1;
    end else begin
      r.acc   = wide[63:0];
      r.acc_n = sum[3:0];
    end
    return r;
  endfunction

  function automatic logic [255:0] append_bytes(
      input logic [255:0] acc_in,
      input logic [5:0]   n0,
      input logic [127:0] src,
      input logic [4:0]   n);
    logic [255:0] a;
    a = acc_in;
    for (int unsigned i = 0; i < 16; i++) begin
      if (5'(i) < n)
        a[8*(32'(n0) + i) +: 8] = src[8*i +: 8];
    end
    return a;
  endfunction

  always_comb begin
    beat_o          = '0;
    beat_o.pkt_type = RIVET_MAC_PKT_TLP;
    beat_valid_o    = 1'b0;
    if (state_q == ST_EMIT) begin
      if (rem_q != 16'd0) begin
        beat_valid_o = 1'b1;
        beat_o.sop   = emit_sop_q;
        beat_o.eop   = (rem_q <= 16'd8);
        beat_o.keep  = len_to_keep16((rem_q >= 16'd8) ? 16'd8 : rem_q);
        beat_o.data  = {64'h0, hold_q[63:0]};
      end
    end else if (live_v) begin
      beat_valid_o = 1'b1;
      beat_o.sop   = emit_sop_q;
      beat_o.eop   = live_eop;
      beat_o.keep  = len_to_keep16(16'(live_n));
      beat_o.data  = acc_q[127:0];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q       <= ST_IDLE;
      seq_q         <= '0;
      next_seq_q    <= '0;
      crc_q         <= 32'hFFFF_FFFF;
      rem_q         <= '0;
      frame_len_q   <= '0;
      pay_q         <= '0;
      word_idx_q    <= '0;
      acc_q         <= '0;
      acc_n_q       <= '0;
      eop_n_q       <= '0;
      pkt_q         <= 1'b0;
      hold_q        <= '0;
      cap_acc_q     <= '0;
      cap_n_q       <= '0;
      cap_pend_q    <= 1'b0;
      cap_last_q    <= 1'b0;
      cap_hi_q      <= 1'b0;
      cap_word_q    <= '0;
      cap_hi_word_q <= '0;
      pref_q        <= 1'b0;
      emit_sop_q    <= 1'b0;
      replay_q      <= 1'b0;
    end else begin
      logic [255:0] acc;
      logic [5:0]   an;
      logic [5:0]   eop_n;
      logic [31:0]  crc;
      logic         pkt;
      logic         sop;
      logic [15:0]  pay;
      logic [11:0]  seq;
      logic [11:0]  nseq;
      logic [63:0]  cap_acc;
      logic [3:0]   cap_n;
      logic         cap_pend;
      logic         cap_hi;
      logic         cap_last;
      logic [63:0]  cap_word;
      logic [63:0]  cap_hi_word;

      acc          = acc_q;
      an           = acc_n_q;
      eop_n        = eop_n_q;
      crc          = crc_q;
      pkt          = pkt_q;
      sop          = emit_sop_q;
      pay          = pay_q;
      seq          = seq_q;
      nseq         = next_seq_q;
      cap_acc      = cap_acc_q;
      cap_n        = cap_n_q;
      cap_pend     = cap_pend_q;
      cap_hi       = cap_hi_q;
      cap_last     = cap_last_q;
      cap_word     = cap_word_q;
      cap_hi_word  = cap_hi_word_q;

      if (cap_pend_q && cap_ready_i) begin
        cap_pend = 1'b0;
        cap_hi   = 1'b0;
      end

      if (state_q == ST_IDLE)
        pref_q <= 1'b1;
      else
        pref_q <= 1'b0;

      if (state_q == ST_EMIT) begin
        if (beat_valid_o && beat_ready_i) begin
          logic [15:0] take;
          take = (rem_q >= 16'd8) ? 16'd8 : rem_q;
          sop        = 1'b0;
          rem_q     <= rem_q - take;
          if (rem_q <= 16'd8) begin
            state_q  <= ST_IDLE;
            replay_q <= 1'b0;
          end else begin
            hold_q     <= {64'h0, replay_word_i};
            word_idx_q <= word_idx_q + 16'd1;
          end
        end
        emit_sop_q <= sop;
      end else if (start_rp) begin
        seq          = replay_seq_i;
        rem_q       <= replay_len_i;
        frame_len_q <= replay_len_i;
        hold_q      <= {64'h0, replay_word_i};
        word_idx_q  <= 16'd2;
        sop          = 1'b1;
        replay_q    <= 1'b1;
        acc          = '0;
        an           = '0;
        eop_n        = '0;
        pkt          = 1'b0;
        state_q     <= ST_EMIT;
        emit_sop_q  <= sop;
        acc_q       <= acc;
        acc_n_q     <= an;
        eop_n_q     <= eop_n;
        pkt_q       <= pkt;
        seq_q       <= seq;
      end else begin
        if (live_v && beat_ready_i) begin
          pack_r_t pk0, pk1;
          logic [3:0] n_lo, n_hi;
          n_lo = (live_n >= 5'd8) ? 4'd8 : live_n[3:0];
          n_hi = (live_n > 5'd8) ? 4'(live_n - 5'd8) : 4'd0;
          pk0  = pack_bytes(cap_acc, cap_n, acc[63:0], n_lo, live_eop && (n_hi == 4'd0));
          if (n_hi != 4'd0)
            pk1 = pack_bytes(pk0.acc, pk0.acc_n, acc[127:64], n_hi, live_eop);
          else
            pk1 = pk0;
          cap_acc = pk1.acc;
          cap_n   = pk1.acc_n;
          if (pk0.pend) begin
            cap_pend     = 1'b1;
            cap_word     = pk0.word;
            cap_hi       = pk1.pend && (n_hi != 4'd0);
            cap_hi_word  = pk1.word;
            cap_last     = cap_hi ? pk1.word_last : pk0.word_last;
          end else if (pk1.pend && (n_hi != 4'd0)) begin
            cap_pend    = 1'b1;
            cap_word    = pk1.word;
            cap_last    = pk1.word_last;
            cap_hi      = 1'b0;
          end
          acc = acc >> (32'(live_n) * 8);
          an  = an - {1'b0, live_n};
          if (live_eop) begin
            eop_n   = '0;
            pkt     = 1'b0;
            sop     = 1'b1;
            cap_acc = '0;
            cap_n   = '0;
          end else begin
            sop = 1'b0;
            if (eop_n != 6'd0)
              eop_n = eop_n - {1'b0, live_n};
          end
        end

        if (tl_valid_i && tl_ready_o) begin
          logic [4:0]  nb;
          logic [31:0] lcrc;
          nb = (tl_len_i >= 16'd16) ? 5'd16 : tl_len_i[4:0];
          if (nb != 5'd0) begin
            if (!pkt) begin
              logic [15:0] seq_w;
              seq_w = rivet_tlp_seq_bytes(nseq);
              seq   = nseq;
              nseq  = nseq + 12'd1;
              crc   = rivet_crc32_fold(32'hFFFF_FFFF, {48'h0, seq_w}, 4'd2);
              acc   = append_bytes(acc, an, {112'h0, seq_w}, 5'd2);
              an    = an + 6'd2;
              pay   = 16'd2;
              pkt   = 1'b1;
              sop   = 1'b1;
            end
            crc = fold16(crc, tl_word_i, nb);
            acc = append_bytes(acc, an, tl_word_i, nb);
            an  = an + {1'b0, nb};
            pay = pay + 16'(nb);
            if (tl_last_i) begin
              lcrc    = ~crc;
              acc     = append_bytes(acc, an, {96'h0, lcrc}, 5'd4);
              an      = an + 6'd4;
              eop_n   = an;
              pay     = pay + 16'(RIVET_TLP_LCRC_BYTES);
              frame_len_q <= pay;
              pkt     = 1'b0;
              pay     = '0;
            end
          end
        end

        if ((an == 6'd0) && (eop_n == 6'd0))
          state_q <= ST_IDLE;
        else
          state_q <= ST_LIVE;

        acc_q      <= acc;
        acc_n_q    <= an;
        eop_n_q    <= eop_n;
        crc_q      <= crc;
        pkt_q      <= pkt;
        emit_sop_q <= sop;
        pay_q      <= pay;
        seq_q      <= seq;
        next_seq_q <= nseq;
        cap_acc_q  <= cap_acc;
        cap_n_q    <= cap_n;
        cap_pend_q <= cap_pend;
        cap_hi_q   <= cap_hi;
        cap_last_q <= cap_last;
        cap_word_q <= cap_word;
        cap_hi_word_q <= cap_hi_word;
      end
    end
  end

endmodule : rivet_dll_tlp_tx16
