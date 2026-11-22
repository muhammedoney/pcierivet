// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Frame a TL payload with Seq# + LCRC and emit MAC beats one 64-bit word
// at a time. The payload stays in the packer RAM. Replay records the same
// byte stream as packed 64-bit words, not a SLOT_BYTES-wide copy.

module rivet_dll_tlp_tx #(
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        enable_i,
  input  logic        replay_en_i,

  input  logic        tl_valid_i,
  output logic        tl_ready_o,
  input  logic [15:0] tl_len_i,
  input  logic [63:0] tl_word_i,
  output logic [15:0] tl_word_idx_o,

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

  output rivet_pkg::rivet_dll_mac_tx_beat_t beat_o,
  output logic                              beat_valid_o,
  input  logic                              beat_ready_i,

  output logic         idle_o,
  output logic [11:0]  next_tx_seq_o
);

  import rivet_pkg::*;

  localparam int unsigned BEAT_B = 8;

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_PREP  = 3'd1,
    ST_CRC   = 3'd2,
    ST_LCRC  = 3'd3,
    ST_FLUSH = 3'd4,
    ST_EMIT  = 3'd5
  } state_e;

  state_e      state_q;
  logic [11:0] seq_q, next_seq_q;
  logic [31:0] crc_q;
  logic [15:0] crc_left_q, pld_left_q, rem_q, frame_len_q;
  logic [15:0] word_idx_q;
  logic [127:0] acc_q;
  logic [4:0]  acc_n_q;
  logic [63:0] hold_q;
  logic [63:0] cap_acc_q;
  logic [3:0]  cap_n_q;
  logic        cap_pend_q, cap_last_q;
  logic [63:0] cap_word_q;
  logic        pref_q, emit_sop_q, replay_q, tl_seen_q;
  // The packer stays valid until capture finishes. Without this hold the
  // transmitter can return to idle and start that same TLP a second time.
  logic        tl_held_q;
  logic        start_tl, start_rp;

  assign next_tx_seq_o = next_seq_q;
  assign idle_o        = (state_q == ST_IDLE) && !cap_pend_q;
  assign cap_valid_o   = cap_pend_q;
  assign cap_data_o    = cap_word_q;
  assign cap_last_o    = cap_last_q;
  assign cap_seq_o     = seq_q;
  assign cap_len_o     = frame_len_q;

  assign start_tl = (state_q == ST_IDLE) && pref_q && tl_seen_q && !tl_held_q &&
                    !replay_en_i && enable_i && tl_valid_i && cap_ready_i &&
                    (tl_len_i != 16'd0) &&
                    (tl_len_i <= 16'(SLOT_BYTES - RIVET_TLP_SEQ_BYTES - RIVET_TLP_LCRC_BYTES));
  assign start_rp = (state_q == ST_IDLE) && pref_q && replay_en_i &&
                    replay_valid_i && !cap_pend_q;

  assign tl_word_idx_o     = start_tl ? 16'd1 :
                             ((state_q == ST_IDLE) ? 16'd0 : word_idx_q);
  assign replay_word_idx_o = start_rp ? 16'd1 :
                             ((state_q == ST_IDLE) ? 16'd0 : word_idx_q);

  assign tl_ready_o     = cap_pend_q && cap_last_q && cap_ready_i && !replay_q;
  assign replay_ready_o = (state_q == ST_EMIT) && beat_valid_o && beat_ready_i &&
                          beat_o.eop;

  function automatic logic [7:0] len_to_keep8(input logic [15:0] n);
    if (n >= 9'd8) return 8'hFF;
    unique case (n[2:0])
      3'd1: return 8'h01;
      3'd2: return 8'h03;
      3'd3: return 8'h07;
      3'd4: return 8'h0F;
      3'd5: return 8'h1F;
      3'd6: return 8'h3F;
      3'd7: return 8'h7F;
      default: return 8'h00;
    endcase
  endfunction

  typedef struct packed {
    logic [63:0] acc;
    logic [3:0]  acc_n;
    logic        pend;
    logic [63:0] word;
    logic        word_last;
  } pack_r_t;

  // Merge `n` low bytes of `src` into the replay packer. At most one
  // 64-bit word comes out; a leftover stays in acc for the next beat.
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

  always_comb begin
    logic [3:0] take;
    beat_o          = '0;
    beat_o.pkt_type = RIVET_MAC_PKT_TLP;
    beat_valid_o    = 1'b0;
    take            = (crc_left_q >= 16'd8) ? 4'd8 : crc_left_q[3:0];
    if ((state_q == ST_CRC) && cap_free && (acc_n_q >= 5'(take)) && (take != 4'd0)) begin
      beat_valid_o = 1'b1;
      beat_o.sop   = emit_sop_q;
      beat_o.eop   = 1'b0;
      beat_o.keep  = len_to_keep8(16'(take));
      beat_o.data  = acc_q[63:0];
    end else if ((state_q == ST_LCRC) && cap_free) begin
      beat_valid_o = 1'b1;
      beat_o.sop   = 1'b0;
      beat_o.eop   = 1'b1;
      beat_o.keep  = 8'h0F;
      beat_o.data  = {32'h0, crc_q};
    end else if ((state_q == ST_EMIT) && (rem_q != 16'd0)) begin
      beat_valid_o = 1'b1;
      beat_o.sop   = emit_sop_q;
      beat_o.eop   = (rem_q <= 16'd8);
      beat_o.keep  = len_to_keep8(rem_q);
      beat_o.data  = hold_q;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= ST_IDLE;
      seq_q        <= '0;
      next_seq_q   <= '0;
      crc_q        <= 32'hFFFF_FFFF;
      crc_left_q   <= '0;
      pld_left_q   <= '0;
      rem_q        <= '0;
      frame_len_q  <= '0;
      word_idx_q   <= '0;
      acc_q        <= '0;
      acc_n_q      <= '0;
      hold_q       <= '0;
      cap_acc_q    <= '0;
      cap_n_q      <= '0;
      cap_pend_q   <= 1'b0;
      cap_last_q   <= 1'b0;
      cap_word_q   <= '0;
      pref_q       <= 1'b0;
      emit_sop_q   <= 1'b0;
      replay_q     <= 1'b0;
      tl_seen_q    <= 1'b0;
      tl_held_q    <= 1'b0;
    end else begin
      // One cycle after the packer marks a TLP valid, word 0 is in rd_data.
      tl_seen_q <= (state_q == ST_IDLE) && tl_valid_i && !start_tl;
      if (start_tl)
        tl_held_q <= 1'b1;
      else if (tl_ready_o)
        tl_held_q <= 1'b0;
      if (cap_pend_q && cap_ready_i)
        cap_pend_q <= 1'b0;

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
            hold_q      <= replay_word_i;
            word_idx_q  <= 16'd2;
            emit_sop_q  <= 1'b1;
            replay_q    <= 1'b1;
            state_q     <= ST_EMIT;
          end else if (start_tl) begin
            logic [15:0] seq_w;
            seq_w        = rivet_tlp_seq_bytes(next_seq_q);
            seq_q        <= next_seq_q;
            next_seq_q   <= next_seq_q + 12'd1;
            crc_q        <= 32'hFFFF_FFFF;
            crc_left_q   <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES);
            pld_left_q   <= tl_len_i;
            frame_len_q  <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES);
            acc_q        <= {112'h0, seq_w};
            acc_n_q      <= 5'(RIVET_TLP_SEQ_BYTES);
            hold_q       <= tl_word_i;
            word_idx_q   <= 16'd2;
            cap_acc_q    <= '0;
            cap_n_q      <= '0;
            emit_sop_q   <= 1'b1;
            replay_q     <= 1'b0;
            state_q      <= ST_PREP;
          end
        end
        ST_PREP: begin
          logic [15:0] n;
          logic [127:0] acc;
          n   = (pld_left_q >= 16'd8) ? 16'd8 : pld_left_q;
          acc = acc_q;
          for (int unsigned i = 0; i < 8; i++) begin
            if (16'(i) < n)
              acc[8*(32'(acc_n_q) + i) +: 8] = hold_q[8*i +: 8];
          end
          acc_q      <= acc;
          acc_n_q    <= acc_n_q + n[4:0];
          pld_left_q <= pld_left_q - n;
          hold_q     <= tl_word_i;
          state_q    <= ST_CRC;
        end
        ST_CRC: begin
          if (beat_valid_o && beat_ready_i && (!cap_pend_q || cap_ready_i)) begin
            logic [3:0]   take;
            logic [127:0] acc;
            logic [4:0]   an;
            pack_r_t      pk;
            take = (crc_left_q >= 16'd8) ? 4'd8 : crc_left_q[3:0];
            crc_q      <= rivet_crc32_fold(crc_q, acc_q[63:0], take);
            acc        = acc_q >> (32'(take) * 8);
            an         = acc_n_q - 5'(take);
            crc_left_q <= crc_left_q - 16'(take);
            emit_sop_q <= 1'b0;
            pk = pack_bytes(cap_acc_q, cap_n_q, acc_q[63:0], take, 1'b0);
            if (pk.pend) begin
              cap_pend_q <= 1'b1;
              cap_word_q <= pk.word;
              cap_last_q <= 1'b0;
            end
            cap_acc_q <= pk.acc;
            cap_n_q   <= pk.acc_n;
            if (pld_left_q != 16'd0) begin
              logic [15:0] n;
              n = (pld_left_q >= 16'd8) ? 16'd8 : pld_left_q;
              for (int unsigned i = 0; i < 8; i++) begin
                if (16'(i) < n)
                  acc[8*(32'(an) + i) +: 8] = hold_q[8*i +: 8];
              end
              an         = an + n[4:0];
              pld_left_q <= pld_left_q - n;
              hold_q     <= tl_word_i;
              word_idx_q <= word_idx_q + 16'd1;
            end
            acc_q   <= acc;
            acc_n_q <= an;
            if (crc_left_q == 16'(take)) begin
              crc_q   <= ~rivet_crc32_fold(crc_q, acc_q[63:0], take);
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
            cap_word_q <= cap_acc_q;
            cap_last_q <= 1'b1;
            cap_acc_q  <= '0;
            cap_n_q    <= '0;
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
              hold_q     <= replay_word_i;
              word_idx_q <= word_idx_q + 16'd1;
            end
          end
        end
        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_dll_tlp_tx
