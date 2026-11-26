// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Frame a TL payload with Seq# + LCRC and emit 16-byte MAC beats.
// Beats are cut through: the header goes out while later payload beats
// are still arriving. Replay capture copies the emitted bytes beside
// that path. A full capture slot may pause the pipe. Capture of an
// earlier beat does not.

module rivet_dll_tlp_tx16 #(
  parameter int unsigned SLOT_BYTES = 160,
  // 128 emits 16-byte MAC beats. 256 emits 32-byte beats (Gen4 x4).
  parameter int unsigned WORD_BITS  = 128
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         enable_i,
  input  logic         replay_en_i,

  input  logic         tl_valid_i,
  output logic         tl_ready_o,
  input  logic [15:0]  tl_len_i,
  input  logic         tl_last_i,
  input  logic [WORD_BITS-1:0] tl_word_i,
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
  // Bytes 16..31 of a 32-byte beat. Idle when WORD_BITS is 128.
  output logic         cap_ex_valid_o,
  output logic [63:0]  cap_ex0_o,
  output logic [63:0]  cap_ex1_o,

  output rivet_pkg::rivet_dll_mac_tx_beat_t beat_o,
  output logic                              beat_valid_o,
  input  logic                              beat_ready_i,

  output logic         idle_o,
  output logic [11:0]  next_tx_seq_o
);

  import rivet_pkg::*;

  localparam int unsigned BEAT_B = WORD_BITS / 8;
  // Steady state holds the 2-byte sequence skew plus one beat. The
  // rest covers the first packet waiting for a Gen3 block boundary.
  localparam int unsigned ACC_B  = 80;

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
  logic [639:0] acc_q;
  logic [6:0]   acc_n_q;
  // Bytes from the front of acc through the end of the frame. 0 means
  // the open frame has not taken its last beat yet.
  logic [6:0]   eop_n_q;
  // End of a second finished frame sitting behind eop_n, counted from
  // the front of acc. 0 means there is no second frame yet.
  logic [6:0]   eop2_n_q;
  logic         pkt_q;
  logic [11:0]  cseq0_q, cseq1_q;
  logic [15:0]  clen0_q, clen1_q;
  logic [1:0]   cnum_q;
  logic [127:0] hold_q;
  logic [63:0]  cap_acc_q;
  logic [3:0]   cap_n_q;
  logic         cap_pend_q, cap_last_q, cap_hi_q, cap_ex_q;
  logic [63:0]  cap_word_q, cap_hi_word_q, cap_ex0_q, cap_ex1_q;
  logic         pref_q, emit_sop_q, replay_q;
  logic         start_rp;

  logic         cap_free;
  logic         live_v;
  logic         live_eop;
  logic [5:0]   live_n;
  logic         third_frame;
  logic [15:0]  room_add;

  assign next_tx_seq_o  = next_seq_q;
  assign idle_o         = (state_q == ST_IDLE) && !cap_pend_q && (acc_n_q == 6'd0);
  assign cap_valid_o    = cap_pend_q;
  assign cap_data_o     = cap_word_q;
  assign cap_last_o     = cap_last_q;
  assign cap_seq_o      = cseq0_q;
  assign cap_len_o      = clen0_q;
  assign cap_hi_valid_o = cap_hi_q;
  assign cap_hi_data_o  = cap_hi_word_q;
  assign cap_ex_valid_o = cap_ex_q;
  assign cap_ex0_o      = cap_ex0_q;
  assign cap_ex1_o      = cap_ex1_q;
  assign tl_word_idx_o  = 16'd0;

  assign start_rp = (state_q == ST_IDLE) && pref_q && replay_en_i &&
                    replay_valid_i && !cap_pend_q && (acc_n_q == 6'd0);

  assign replay_word_idx_o = start_rp ? 16'd1 :
                             ((state_q == ST_EMIT) ? word_idx_q : 16'd0);

  assign replay_ready_o = (state_q == ST_EMIT) && beat_valid_o && beat_ready_i &&
                          beat_o.eop;

  assign cap_free = !cap_pend_q || cap_ready_i;

  // A new packet needs 2 sequence bytes + one beat + 4 LCRC bytes.
  // An open packet needs at most one more beat and the LCRC.
  assign room_add = pkt_q ? 16'(BEAT_B + 4) : 16'(BEAT_B + 6);

  always_comb begin
    live_v   = 1'b0;
    live_eop = 1'b0;
    live_n   = '0;
    if ((state_q != ST_EMIT) && cap_free && (acc_n_q != 6'd0)) begin
      if ((acc_n_q >= 6'(BEAT_B)) && ((eop_n_q == 6'd0) || (eop_n_q > 6'(BEAT_B)))) begin
        live_v   = 1'b1;
        live_n   = 6'(BEAT_B);
        live_eop = 1'b0;
      end else if ((eop_n_q != 6'd0) && (eop_n_q <= 6'(BEAT_B)) &&
                   (acc_n_q >= eop_n_q)) begin
        live_v   = 1'b1;
        live_n   = eop_n_q[5:0];
        live_eop = 1'b1;
      end
    end
  end

  always_comb begin
    logic [15:0] nb;
    logic [15:0] need;
    // Two finished frames already sit in the accumulator. The next beat
    // would be a third, and there is only one slot behind the first end.
    // A parked beat is sized from its keep, not from a full beat. The max
    // Gen4 frame is 4118 bytes and the slot is 4128; reserving BEAT_B+4
    // for a 16-byte tail refuses that tail and never closes the packet.
    // Size room against registered acc_n_q (not post-drain) so tl_ready_o
    // never depends combinationally on beat_ready_i or cap_ready_i.
    third_frame = !pkt_q && (eop2_n_q != 6'd0);
    nb   = (tl_len_i >= 16'(BEAT_B)) ? 16'(BEAT_B) : tl_len_i;
    need = room_add;
    if (tl_valid_i && (nb != 16'd0))
      need = nb + (pkt_q ? 16'd0 : 16'd2) +
             (tl_last_i ? 16'(RIVET_TLP_LCRC_BYTES) : 16'd0);
    tl_ready_o = enable_i && !replay_en_i && !start_rp &&
                 (state_q != ST_EMIT) && !third_frame &&
                 (({1'b0, acc_n_q} + {1'b0, need[6:0]}) <= 8'(ACC_B)) &&
                 ((pay_q + need) <= 16'(SLOT_BYTES));
  end

  function automatic logic [31:0] len_to_keep16(input logic [15:0] n);
    logic [31:0] k;
    k = '0;
    for (int unsigned i = 0; i < 32; i++)
      if (16'(i) < n)
        k[i] = 1'b1;
    return k;
  endfunction

  // Destination-byte-first append of payload (optional 2 B seq + up to 32 B
  // payload) in one pass. LCRC (4 B) is inserted directly afterward so it
  // bypasses the 38:1 chunk mux.
  function automatic logic [639:0] append_pay(
      input logic [639:0] acc_in,
      input logic [6:0]   n0,
      input logic [271:0] src,
      input logic [5:0]   n);
    logic [7:0]   sb [64];
    logic [639:0] a;
    for (int unsigned i = 0; i < 64; i++)
      sb[i] = (i < 34) ? src[8*i +: 8] : 8'h00;
    a = acc_in;
    for (int unsigned k = 0; k < 80; k++) begin
      automatic logic [6:0] diff;
      diff = 7'(k) - n0;
      if ((7'(k) >= n0) && (diff < {1'b0, n}))
        a[8*k +: 8] = sb[diff[5:0]];
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
      beat_o.data  = '0;
      beat_o.data[BEAT_B*8-1:0] = acc_q[BEAT_B*8-1:0];
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
      eop2_n_q      <= '0;
      pkt_q         <= 1'b0;
      cseq0_q       <= '0;
      cseq1_q       <= '0;
      clen0_q       <= '0;
      clen1_q       <= '0;
      cnum_q        <= '0;
      hold_q        <= '0;
      cap_acc_q     <= '0;
      cap_n_q       <= '0;
      cap_pend_q    <= 1'b0;
      cap_last_q    <= 1'b0;
      cap_hi_q      <= 1'b0;
      cap_ex_q      <= 1'b0;
      cap_word_q    <= '0;
      cap_hi_word_q <= '0;
      cap_ex0_q     <= '0;
      cap_ex1_q     <= '0;
      pref_q        <= 1'b0;
      emit_sop_q    <= 1'b0;
      replay_q      <= 1'b0;
    end else begin
      logic [639:0] acc;
      logic [6:0]   an;
      logic [6:0]   eop_n;
      logic [6:0]   eop2;
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
      logic         cap_ex;
      logic         cap_last;
      logic [63:0]  cap_word;
      logic [63:0]  cap_hi_word;
      logic [63:0]  cap_ex0;
      logic [63:0]  cap_ex1;
      logic [11:0]  cseq0, cseq1;
      logic [15:0]  clen0, clen1;
      logic [1:0]   cnum;

      acc          = acc_q;
      an           = acc_n_q;
      eop_n        = eop_n_q;
      eop2         = eop2_n_q;
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
      cap_ex       = cap_ex_q;
      cap_last     = cap_last_q;
      cap_word     = cap_word_q;
      cap_hi_word  = cap_hi_word_q;
      cap_ex0      = cap_ex0_q;
      cap_ex1      = cap_ex1_q;
      cseq0        = cseq0_q;
      cseq1        = cseq1_q;
      clen0        = clen0_q;
      clen1        = clen1_q;
      cnum         = cnum_q;

      if (cap_pend_q && cap_ready_i) begin
        cap_pend = 1'b0;
        cap_hi   = 1'b0;
        cap_ex   = 1'b0;
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
        eop2         = '0;
        pkt          = 1'b0;
        cnum         = '0;
        state_q     <= ST_EMIT;
        emit_sop_q  <= sop;
        acc_q       <= acc;
        acc_n_q     <= an;
        eop_n_q     <= eop_n;
        eop2_n_q    <= eop2;
        pkt_q       <= pkt;
        cnum_q      <= cnum;
        seq_q       <= seq;
      end else begin
        if (live_v && beat_ready_i) begin
          // Flatten replay capture into one parallel 40-byte merge instead of
          // four serial pack_bytes stages.
          logic [7:0]   src_b [32];
          logic [319:0] wide;
          logic [5:0]   tot;
          logic [2:0]   full_w;
          logic [2:0]   rem_b;
          logic [2:0]   emit_w;
          for (int unsigned i = 0; i < 32; i++)
            src_b[5'(i)] = acc[8*5'(i) +: 8];
          wide = {256'h0, cap_acc};
          for (int unsigned k = 0; k < 40; k++) begin
            automatic logic [5:0] diff;
            diff = 6'(k) - {2'd0, cap_n};
            if ((6'(k) >= {2'd0, cap_n}) && (diff < live_n))
              wide[8*k +: 8] = src_b[diff[4:0]];
          end
          tot    = {2'd0, cap_n} + live_n;
          full_w = tot[5:3];
          rem_b  = tot[2:0];
          emit_w = full_w + ((live_eop && (rem_b != 3'd0) && (full_w < 3'd4)) ? 3'd1 : 3'd0);
          cap_pend = (emit_w != 3'd0);
          cap_hi   = (emit_w >= 3'd2);
          cap_ex   = (emit_w >= 3'd3);
          if (cap_pend) begin
            cap_word    = wide[63:0];
            cap_hi_word = wide[127:64];
            cap_ex0     = wide[191:128];
            cap_ex1     = wide[255:192];
            cap_last    = live_eop && ((full_w < 3'd4) || (rem_b == 3'd0));
          end
          case (full_w)
            3'd0:    cap_acc = live_eop ? 64'h0 : wide[63:0];
            3'd1:    cap_acc = wide[127:64];
            3'd2:    cap_acc = wide[191:128];
            3'd3:    cap_acc = wide[255:192];
            default: cap_acc = wide[319:256];
          endcase
          cap_n = (live_eop && (full_w < 3'd4)) ? 4'd0 : {1'b0, rem_b};

          acc = live_eop ? (acc >> (32'(live_n) * 8)) : (acc >> (BEAT_B * 8));
          an  = an - {1'b0, live_n};
          if (live_eop) begin
            logic closed_tail;
            closed_tail = (eop2 != 6'd0);
            if (closed_tail)
              eop_n = eop2 - {1'b0, live_n};
            else
              eop_n = '0;
            eop2    = '0;
            // pkt_q already tracks whether a subsequent frame is open; avoid
            // routing live_eop back into add_seq / CRC on the same cycle.
            sop     = 1'b1;
            cap_acc = '0;
            cap_n   = '0;
            if (cnum != 2'd0) begin
              cseq0 = cseq1;
              clen0 = clen1;
              cnum  = cnum - 2'd1;
            end
          end else begin
            sop = 1'b0;
            if (eop_n != 6'd0)
              eop_n = eop_n - {1'b0, live_n};
            if (eop2 != 6'd0)
              eop2 = eop2 - {1'b0, live_n};
          end
        end

        if (tl_valid_i && tl_ready_o) begin
          logic [5:0]   nb;
          logic [31:0]  crc_base;
          logic [31:0]  lcrc;
          logic [15:0]  seq_w;
          logic         add_seq;
          logic [5:0]   seq_len;
          logic [5:0]   pay_end;
          logic [5:0]   chunk_n;
          logic [6:0]   lcrc_off;
          logic [255:0] w256;
          logic [271:0] pay_chunk;
          nb = (tl_len_i >= 16'(BEAT_B)) ? 6'(BEAT_B) : tl_len_i[5:0];
          if (nb != 6'd0) begin
            add_seq  = !pkt_q;
            seq_w    = rivet_tlp_seq_bytes(nseq);
            crc_base = crc;
            if (add_seq) begin
              if (acc_n_q == 7'd0)
                sop = 1'b1;
              seq      = nseq;
              nseq     = nseq + 12'd1;
              crc_base = rivet_crc32_fold(32'hFFFF_FFFF, {48'h0, seq_w}, 4'd2);
              pay      = 16'd2;
              pkt      = 1'b1;
            end
            w256 = 256'(tl_word_i);
            crc  = rivet_crc32_fold32(crc_base, w256, nb);
            lcrc = ~crc;
            pay  = pay + 16'(nb);

            // Append optional 2 B seq + payload in parallel with CRC, then
            // insert the 4 B LCRC directly at lcrc_off = an + pay_end.
            seq_len   = add_seq ? 6'd2 : 6'd0;
            pay_end   = seq_len + nb;
            chunk_n   = pay_end + (tl_last_i ? 6'd4 : 6'd0);
            pay_chunk = add_seq ? {w256, seq_w} : {16'h0, w256};
            acc       = append_pay(acc, an, pay_chunk, pay_end);
            lcrc_off  = an + {1'b0, pay_end};
            if (tl_last_i) begin
              for (int unsigned k = 0; k < 80; k++) begin
                automatic logic [6:0] loff;
                loff = 7'(k) - lcrc_off;
                if ((7'(k) >= lcrc_off) && (loff < 7'd4))
                  acc[8*k +: 8] = lcrc[8*loff[1:0] +: 8];
              end
            end
            an = an + {1'b0, chunk_n};

            if (tl_last_i) begin
              if (eop_n == 7'd0)
                eop_n = an;
              else
                eop2 = an;
              pay = pay + 16'(RIVET_TLP_LCRC_BYTES);
              if (cnum == 2'd0) begin
                cseq0 = seq;
                clen0 = pay;
              end else begin
                cseq1 = seq;
                clen1 = pay;
              end
              cnum = cnum + 2'd1;
              pkt  = 1'b0;
              pay  = '0;
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
        eop2_n_q   <= eop2;
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
        cap_ex_q   <= cap_ex;
        cap_last_q <= cap_last;
        cap_word_q    <= cap_word;
        cap_hi_word_q <= cap_hi_word;
        cap_ex0_q     <= cap_ex0;
        cap_ex1_q     <= cap_ex1;
        cseq0_q       <= cseq0;
        cseq1_q       <= cseq1;
        clen0_q       <= clen0;
        clen1_q       <= clen1;
        cnum_q        <= cnum;
      end
    end
  end

endmodule : rivet_dll_tlp_tx16
