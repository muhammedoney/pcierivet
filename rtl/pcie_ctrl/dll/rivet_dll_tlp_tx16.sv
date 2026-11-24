// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Frame a TL payload with Seq# + LCRC and emit 16-byte MAC beats.
// The packer RAM is still 64-bit words; each read returns a pair and the
// index steps by two. Replay capture writes up to two 64-bit words per
// cycle so a 16-byte beat does not stall the replay buffer.

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

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_PREP  = 3'd1,
    ST_CRC   = 3'd2,
    ST_LCRC  = 3'd3,
    ST_FLUSH = 3'd4,
    ST_EMIT  = 3'd5
  } state_e;

  state_e       state_q;
  logic [11:0]  seq_q, next_seq_q;
  logic [31:0]  crc_q;
  logic [15:0]  crc_left_q, pld_left_q, rem_q, frame_len_q;
  logic [15:0]  word_idx_q;
  logic [255:0] acc_q;
  logic [5:0]   acc_n_q;
  logic [127:0] hold_q;
  logic [63:0]  cap_acc_q;
  logic [3:0]   cap_n_q;
  logic         cap_pend_q, cap_last_q, cap_hi_q;
  logic [63:0]  cap_word_q, cap_hi_word_q;
  // Third replay word when a merged tail+LCRC capture does not fit in two.
  logic         pend3_v_q;
  logic [63:0]  pend3_q;
  logic         pref_q, emit_sop_q, replay_q, tl_seen_q;
  logic         tl_held_q;
  logic         start_tl, start_rp;

  assign next_tx_seq_o  = next_seq_q;
  assign idle_o         = (state_q == ST_IDLE) && !cap_pend_q;
  assign cap_valid_o    = cap_pend_q;
  assign cap_data_o     = cap_word_q;
  assign cap_last_o     = cap_last_q;
  assign cap_seq_o      = seq_q;
  assign cap_len_o      = frame_len_q;
  assign cap_hi_valid_o = cap_hi_q;
  assign cap_hi_data_o  = cap_hi_word_q;

  assign start_tl = (state_q == ST_IDLE) && pref_q && tl_seen_q && !tl_held_q &&
                    !replay_en_i && enable_i && tl_valid_i && cap_ready_i &&
                    (tl_len_i != 16'd0) &&
                    (tl_len_i <= 16'(SLOT_BYTES - RIVET_TLP_SEQ_BYTES - RIVET_TLP_LCRC_BYTES));
  assign start_rp = (state_q == ST_IDLE) && pref_q && replay_en_i &&
                    replay_valid_i && !cap_pend_q;

  // Pair index. Idle presents words 0 and 1. Start asks for words 2 and 3.
  assign tl_word_idx_o     = start_tl ? 16'd2 :
                             ((state_q == ST_IDLE) ? 16'd0 : word_idx_q);
  assign replay_word_idx_o = start_rp ? 16'd1 :
                             ((state_q == ST_IDLE) ? 16'd0 : word_idx_q);

  assign tl_ready_o     = cap_pend_q && cap_last_q && cap_ready_i && !replay_q;
  assign replay_ready_o = (state_q == ST_EMIT) && beat_valid_o && beat_ready_i &&
                          beat_o.eop;

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

  wire cap_free = !cap_pend_q || cap_ready_i;
  wire [4:0] crc_take = (crc_left_q >= 16'(BEAT_B)) ? 5'(BEAT_B) : crc_left_q[4:0];
  // A 1..12 byte tail plus the 4-byte LCRC still fits in one MAC beat.
  // A separate short beat leaves the MAC window under a symbol-time and it stalls.
  wire crc_merge = (state_q == ST_CRC) && (crc_left_q != 16'd0) &&
                   (crc_left_q == 16'(crc_take)) && (crc_take <= 5'd12) &&
                   (acc_n_q >= 6'(crc_take));

  always_comb begin
    logic [4:0]  take;
    logic [31:0] crc_fin;
    logic [4:0]  nb;
    beat_o          = '0;
    beat_o.pkt_type = RIVET_MAC_PKT_TLP;
    beat_valid_o    = 1'b0;
    take            = crc_take;
    crc_fin         = '0;
    nb              = '0;
    if ((state_q == ST_CRC) && !crc_merge && cap_free &&
        (acc_n_q >= 6'(take)) && (take != 5'd0)) begin
      beat_valid_o = 1'b1;
      beat_o.sop   = emit_sop_q;
      beat_o.eop   = 1'b0;
      beat_o.keep  = len_to_keep16(16'(take));
      beat_o.data  = acc_q[127:0];
    end else if (crc_merge && cap_free) begin
      crc_fin        = ~fold16(crc_q, acc_q[127:0], take);
      nb             = take + 5'd4;
      beat_valid_o   = 1'b1;
      beat_o.sop     = emit_sop_q;
      beat_o.eop     = 1'b1;
      beat_o.keep    = len_to_keep16(16'(nb));
      beat_o.data    = acc_q[127:0];
      for (int unsigned i = 0; i < 4; i++)
        beat_o.data[8*(32'(take) + i) +: 8] = crc_fin[8*i +: 8];
    end else if ((state_q == ST_LCRC) && cap_free) begin
      beat_valid_o = 1'b1;
      beat_o.sop   = 1'b0;
      beat_o.eop   = 1'b1;
      beat_o.keep  = 16'h000F;
      beat_o.data  = {96'h0, crc_q};
    end else if ((state_q == ST_EMIT) && (rem_q != 16'd0)) begin
      beat_valid_o = 1'b1;
      beat_o.sop   = emit_sop_q;
      beat_o.eop   = (rem_q <= 16'd8);
      beat_o.keep  = len_to_keep16((rem_q >= 16'd8) ? 16'd8 : rem_q);
      beat_o.data  = {64'h0, hold_q[63:0]};
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q       <= ST_IDLE;
      seq_q         <= '0;
      next_seq_q    <= '0;
      crc_q         <= 32'hFFFF_FFFF;
      crc_left_q    <= '0;
      pld_left_q    <= '0;
      rem_q         <= '0;
      frame_len_q   <= '0;
      word_idx_q    <= '0;
      acc_q         <= '0;
      acc_n_q       <= '0;
      hold_q        <= '0;
      cap_acc_q     <= '0;
      cap_n_q       <= '0;
      cap_pend_q    <= 1'b0;
      cap_last_q    <= 1'b0;
      cap_hi_q      <= 1'b0;
      cap_word_q    <= '0;
      cap_hi_word_q <= '0;
      pend3_v_q     <= 1'b0;
      pend3_q       <= '0;
      pref_q        <= 1'b0;
      emit_sop_q    <= 1'b0;
      replay_q      <= 1'b0;
      tl_seen_q     <= 1'b0;
      tl_held_q     <= 1'b0;
    end else begin
      tl_seen_q <= (state_q == ST_IDLE) && tl_valid_i && !start_tl;
      if (start_tl)
        tl_held_q <= 1'b1;
      else if (tl_ready_o)
        tl_held_q <= 1'b0;
      if (cap_pend_q && cap_ready_i) begin
        cap_pend_q <= 1'b0;
        cap_hi_q   <= 1'b0;
      end

      if (state_q == ST_IDLE)
        pref_q <= 1'b1;
      else
        pref_q <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (start_rp) begin
            seq_q       <= replay_seq_i;
            rem_q       <= replay_len_i;
            frame_len_q <= replay_len_i;
            hold_q      <= {64'h0, replay_word_i};
            word_idx_q  <= 16'd2;
            emit_sop_q  <= 1'b1;
            replay_q    <= 1'b1;
            state_q     <= ST_EMIT;
          end else if (start_tl) begin
            logic [15:0] seq_w;
            seq_w         = rivet_tlp_seq_bytes(next_seq_q);
            seq_q         <= next_seq_q;
            next_seq_q    <= next_seq_q + 12'd1;
            crc_q         <= 32'hFFFF_FFFF;
            crc_left_q    <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES);
            pld_left_q    <= tl_len_i;
            frame_len_q   <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES);
            acc_q         <= {240'h0, seq_w};
            acc_n_q       <= 6'(RIVET_TLP_SEQ_BYTES);
            hold_q        <= tl_word_i;
            word_idx_q    <= 16'd4;
            cap_acc_q     <= '0;
            cap_n_q       <= '0;
            emit_sop_q    <= 1'b1;
            replay_q      <= 1'b0;
            pend3_v_q     <= 1'b0;
            state_q       <= ST_PREP;
          end
        end
        ST_PREP: begin
          logic [15:0]  n;
          logic [255:0] acc;
          n   = (pld_left_q >= 16'(BEAT_B)) ? 16'(BEAT_B) : pld_left_q;
          acc = acc_q;
          for (int unsigned i = 0; i < BEAT_B; i++) begin
            if (16'(i) < n)
              acc[8*(32'(acc_n_q) + i) +: 8] = hold_q[8*i +: 8];
          end
          acc_q      <= acc;
          acc_n_q    <= acc_n_q + n[5:0];
          pld_left_q <= pld_left_q - n;
          hold_q     <= tl_word_i;
          // The read issued this cycle is the pair after the one just captured.
          word_idx_q <= word_idx_q + 16'd2;
          state_q    <= ST_CRC;
        end
        ST_CRC: begin
          if (beat_valid_o && beat_ready_i && (!cap_pend_q || cap_ready_i)) begin
            logic [4:0]   take;
            logic [4:0]   n0, n1;
            logic [255:0] acc;
            logic [5:0]   an;
            pack_r_t      pk0, pk1;
            take = crc_take;
            if (crc_merge) begin
              logic [31:0] crc_fin;
              logic [3:0]  m0, m1;
              pack_r_t     p0, p1, p2;
              logic [63:0] qw [0:2];
              logic        ql [0:2];
              logic        last_now;
              int          nq;
              crc_fin = ~fold16(crc_q, acc_q[127:0], take);
              crc_q  <= crc_fin;
              m0 = (take >= 5'd8) ? 4'd8 : take[3:0];
              m1 = (take > 5'd8) ? 4'(take - 5'd8) : 4'd0;
              p0 = pack_bytes(cap_acc_q, cap_n_q, acc_q[63:0], m0, 1'b0);
              if (m1 != 4'd0)
                p1 = pack_bytes(p0.acc, p0.acc_n, acc_q[127:64], m1, 1'b0);
              else
                p1 = p0;
              p2 = pack_bytes(p1.acc, p1.acc_n, {32'h0, crc_fin}, 4'd4, 1'b1);
              nq = 0;
              qw[0] = '0; qw[1] = '0; qw[2] = '0;
              ql[0] = 1'b0; ql[1] = 1'b0; ql[2] = 1'b0;
              last_now = 1'b0;
              if (p0.pend && (m0 != 4'd0)) begin
                qw[nq] = p0.word; ql[nq] = p0.word_last; nq = nq + 1;
              end
              if ((m1 != 4'd0) && p1.pend) begin
                qw[nq] = p1.word; ql[nq] = p1.word_last; nq = nq + 1;
              end
              if (p2.pend) begin
                qw[nq] = p2.word; ql[nq] = p2.word_last; nq = nq + 1;
              end
              if ((nq > 0) && (nq <= 2))
                last_now = ql[nq - 1];
              cap_pend_q    <= (nq > 0);
              cap_word_q    <= qw[0];
              cap_last_q    <= last_now;
              cap_hi_q      <= (nq > 1);
              cap_hi_word_q <= qw[1];
              pend3_v_q     <= (nq > 2);
              pend3_q       <= qw[2];
              cap_acc_q     <= p2.acc;
              cap_n_q       <= p2.acc_n;
              if ((nq > 2) || (p2.acc_n != 4'd0))
                state_q <= ST_FLUSH;
              else
                state_q <= ST_IDLE;
            end else begin
            n0   = (take >= 5'd8) ? 5'd8 : take;
            n1   = (take > 5'd8) ? (take - 5'd8) : 5'd0;
            crc_q      <= (crc_left_q == 16'(take))
                          ? ~fold16(crc_q, acc_q[127:0], take)
                          : fold16(crc_q, acc_q[127:0], take);
            acc        = acc_q >> (32'(take) * 8);
            an         = acc_n_q - 6'(take);
            crc_left_q <= crc_left_q - 16'(take);
            emit_sop_q <= 1'b0;
            pk0 = pack_bytes(cap_acc_q, cap_n_q, acc_q[63:0], n0[3:0], 1'b0);
            if (n1 != 5'd0)
              pk1 = pack_bytes(pk0.acc, pk0.acc_n, acc_q[127:64], n1[3:0], 1'b0);
            else
              pk1 = pk0;
            if (pk0.pend) begin
              cap_pend_q    <= 1'b1;
              cap_word_q    <= pk0.word;
              cap_last_q    <= 1'b0;
              cap_hi_q      <= pk1.pend && (n1 != 5'd0);
              cap_hi_word_q <= pk1.word;
            end else if (pk1.pend && (n1 != 5'd0)) begin
              cap_pend_q <= 1'b1;
              cap_word_q <= pk1.word;
              cap_last_q <= 1'b0;
              cap_hi_q   <= 1'b0;
            end
            cap_acc_q <= pk1.acc;
            cap_n_q   <= pk1.acc_n;
            if (pld_left_q != 16'd0) begin
              logic [15:0] n;
              n = (pld_left_q >= 16'(BEAT_B)) ? 16'(BEAT_B) : pld_left_q;
              for (int unsigned i = 0; i < BEAT_B; i++) begin
                if (16'(i) < n)
                  acc[8*(32'(an) + i) +: 8] = hold_q[8*i +: 8];
              end
              an         = an + n[5:0];
              pld_left_q <= pld_left_q - n;
              hold_q     <= tl_word_i;
              word_idx_q <= word_idx_q + 16'd2;
            end
            acc_q   <= acc;
            acc_n_q <= an;
            if (crc_left_q == 16'(take))
              state_q <= ST_LCRC;
            end
          end
        end
        ST_LCRC: begin
          if (beat_valid_o && beat_ready_i && (!cap_pend_q || cap_ready_i)) begin
            pack_r_t pk;
            pk = pack_bytes(cap_acc_q, cap_n_q, {32'h0, crc_q}, 4'd4, 1'b1);
            cap_acc_q <= pk.acc;
            cap_n_q   <= pk.acc_n;
            cap_hi_q  <= 1'b0;
            if (pk.pend) begin
              cap_pend_q <= 1'b1;
              cap_word_q <= pk.word;
              cap_last_q <= pk.word_last;
            end
            if (pk.acc_n != 4'd0)
              state_q <= ST_FLUSH;
            else
              state_q <= ST_IDLE;
          end
        end
        ST_FLUSH: begin
          if (!cap_pend_q || cap_ready_i) begin
            cap_pend_q <= 1'b1;
            cap_word_q <= pend3_v_q ? pend3_q : cap_acc_q;
            cap_last_q <= 1'b1;
            cap_hi_q   <= 1'b0;
            cap_acc_q  <= '0;
            cap_n_q    <= '0;
            pend3_v_q  <= 1'b0;
            state_q    <= ST_IDLE;
          end
        end
        ST_EMIT: begin
          if (beat_valid_o && beat_ready_i) begin
            logic [15:0] take;
            take = (rem_q >= 16'd8) ? 16'd8 : rem_q;
            emit_sop_q <= 1'b0;
            rem_q      <= rem_q - take;
            if (rem_q <= 16'd8) begin
              state_q <= ST_IDLE;
            end else begin
              hold_q     <= {64'h0, replay_word_i};
              word_idx_q <= word_idx_q + 16'd1;
            end
          end
        end
        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_dll_tlp_tx16
