// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Assemble MAC TLP beats, check Seq# / LCRC, deliver payload to TL, schedule ACK/NAK.
//
// Two word-RAM banks. A MAC beat may carry 16 bytes; those land in two
// 64-bit words in one cycle, and playback returns 16 TLP bytes per cycle.
// The 8-byte receiver is rivet_dll_tlp_rx.

module rivet_dll_tlp_rx16 #(
  parameter int unsigned SLOT_BYTES = 4128,
  // 128 plays 16 TLP bytes per cycle. 256 plays 32 (Gen4 x4).
  parameter int unsigned DATA_W     = 128
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        enable_i,

  input  rivet_pkg::rivet_dll_mac_rx_beat_t beat_i,
  input  logic                              beat_valid_i,
  output logic                              beat_ready_o,

  output logic                       tl_valid_o,
  input  logic                       tl_ready_i,
  output logic [DATA_W-1:0]         tl_data_o,
  output logic [DATA_W/8-1:0]        tl_keep_o,
  output logic                       tl_last_o,
  output logic [11:0]                tl_seq_o,

  output rivet_pkg::rivet_dllp_req_t ack_req_o,
  output logic                       ack_valid_o,
  input  logic                       ack_ready_i,

  output logic [11:0] last_good_seq_o,
  output logic        lcrc_err_o,
  // One cycle after a cut-through frame fails LCRC and some TLP bytes
  // were already handed to TL. The completion port must drop that frame.
  output logic        tl_abort_o
);

  import rivet_pkg::*;

  localparam int unsigned OUT_B   = (DATA_W >= 256) ? 32 : 16;
  localparam int unsigned NWORD   = OUT_B / 8;
  localparam int unsigned MIN_FR  = RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES;
  localparam int unsigned IDX_W   = 10;
  localparam int unsigned RAM_N   = 2 * (1 << IDX_W);

  typedef enum logic [1:0] {
    CAP_IDLE = 2'd0,
    CAP_RUN  = 2'd1,
    CAP_DEC  = 2'd2
  } cap_e;

  typedef enum logic [1:0] {
    PLAY_IDLE = 2'd0,
    PLAY_PREP = 2'd1,
    PLAY_RUN  = 2'd2
  } play_e;

  cap_e              cap_st_q;
  play_e             play_st_q;
  logic              cap_bank_q;
  logic              play_bank_q;
  logic              bank_ready_q [2];
  logic [12:0]       bank_len_q [2];
  logic [11:0]       bank_seq_q [2];
  logic [13:0]       bank_pld_q [2];

  logic [IDX_W-1:0]  wr_idx_q;
  logic [12:0]       cap_len_q;
  logic [13:0]       pld_left_q;
  logic [11:0]       cap_seq_q;
  logic [11:0]       seq_q;
  logic              cap_ovf_q;
  logic [31:0]       cap_crc_q;
  logic [11:0]       expect_q;
  logic [11:0]       last_good_q;
  logic              lcrc_err_q;
  logic [12:0]       play_len_q;

  logic              ram_we, ram_we2, ram_we3, ram_we4;
  logic [IDX_W:0]    ram_waddr, ram_waddr2, ram_waddr3, ram_waddr4;
  logic [IDX_W:0]    ram_raddr, ram_raddr1, ram_raddr2, ram_raddr3;
  logic [63:0]       ram_wdata, ram_wdata2, ram_wdata3, ram_wdata4;
  logic [63:0]       ram_rdata [4];
  logic [63:0]       rd_lo_q;
  logic [63:0]       rd_hi_q;
  logic [63:0]       rd_c_q;
  logic [63:0]       rd_d_q;
  logic [IDX_W-1:0]  rd_addr_q;

  logic [511:0]      acc_q;
  logic [5:0]        acc_n_q;
  logic [IDX_W-1:0]  word_idx_q;
  logic              fresh_q;

  logic              can_send;
  logic              play_stall;
  logic              play_consume;
  logic              more_after;
  logic              rd_issue;
  logic [5:0]        take_n;
  logic [5:0]        take_skip;
  logic              words_ok;
  logic              hold_tail;

  logic              tl_v_q;
  logic [DATA_W-1:0] tl_data_q;
  logic [DATA_W/8-1:0] tl_keep_q;
  logic              tl_last_q;
  // Playback started before LCRC. The last 4 frame bytes stay held so a
  // still-open frame cannot emit its LCRC. pld_seen is the payload already
  // released into pld_left.
  logic              play_open_q;
  logic [13:0]       pld_seen_q;
  logic              tl_sent_q;
  logic              tl_abort_q;

  rivet_dllp_req_t   ack_slot_q [2];
  logic [1:0]        ack_n_q;

  logic              bank_blocked;

  assign tl_valid_o      = tl_v_q;
  assign tl_data_o       = tl_data_q;
  assign tl_keep_o       = tl_keep_q;
  assign tl_last_o       = tl_last_q;
  assign tl_seq_o        = seq_q;
  assign ack_valid_o     = ack_n_q != 2'd0;
  assign ack_req_o       = ack_slot_q[0];
  assign last_good_seq_o = last_good_q;
  assign lcrc_err_o      = lcrc_err_q;
  assign tl_abort_o      = tl_abort_q;

  // A live frame keeps accepting beats into the bank it is already playing.
  assign bank_blocked = bank_ready_q[cap_bank_q] ||
                        ((play_st_q != PLAY_IDLE) && (play_bank_q == cap_bank_q) &&
                         !play_open_q);
  assign beat_ready_o = enable_i &&
                        ((cap_st_q == CAP_IDLE) || (cap_st_q == CAP_RUN)) &&
                        !bank_blocked;

  function automatic logic [7:0] keep_popcount(input logic [31:0] k);
    logic [2:0] c4 [8];
    logic [3:0] c8 [4];
    logic [4:0] c16 [2];
    logic [5:0] cnt;
    for (int unsigned i = 0; i < 8; i++)
      c4[i] = {2'd0, k[4*i]} + {2'd0, k[4*i + 1]} +
              {2'd0, k[4*i + 2]} + {2'd0, k[4*i + 3]};
    for (int unsigned i = 0; i < 4; i++)
      c8[i] = {1'b0, c4[2*i]} + {1'b0, c4[2*i + 1]};
    c16[0] = {1'b0, c8[0]} + {1'b0, c8[1]};
    c16[1] = {1'b0, c8[2]} + {1'b0, c8[3]};
    cnt    = {1'b0, c16[0]} + {1'b0, c16[1]};
    return {2'd0, cnt};
  endfunction

  function automatic logic [31:0] keep_prefix(input logic [5:0] n);
    logic [31:0] k;
    k = '0;
    for (int unsigned i = 0; i < 32; i++)
      if (6'(i) < n)
        k[i] = 1'b1;
    return k;
  endfunction

  function automatic logic [31:0] fold16(
      input logic [31:0]  crc,
      input logic [255:0] data,
      input logic [5:0]   n);
    logic [31:0] c;
    c = crc;
    for (int unsigned w = 0; w < 4; w++) begin
      if (n > 6'(w * 8)) begin
        automatic logic [5:0] left;
        automatic logic [3:0] nw;
        left = n - 6'(w * 8);
        nw   = (left >= 6'd8) ? 4'd8 : left[3:0];
        c    = rivet_crc32_fold(c, data[64*w +: 64], nw);
      end
    end
    return c;
  endfunction

  logic        take_beat;
  logic [7:0]  nbytes;
  logic [31:0] crc_next;
  logic [12:0] len_next;

  assign nbytes    = keep_popcount(beat_i.keep);
  assign take_beat = beat_valid_i && beat_ready_o &&
                     (beat_i.pkt_type == RIVET_MAC_PKT_TLP) && !beat_i.err;
  assign len_next  = beat_i.sop ? {5'd0, nbytes} : (cap_len_q + {5'd0, nbytes});
  assign crc_next  = fold16(
      (take_beat && beat_i.sop) ? 32'hFFFF_FFFF : cap_crc_q,
      beat_i.data, nbytes[5:0]);

  assign ram_we    = take_beat && !cap_ovf_q &&
                     (wr_idx_q != IDX_W'(10'h3FF) || beat_i.sop);
  assign ram_we2   = ram_we && (nbytes > 8'd8);
  assign ram_we3   = ram_we && (nbytes > 8'd16);
  assign ram_we4   = ram_we && (nbytes > 8'd24);
  assign ram_waddr = {cap_bank_q, beat_i.sop ? {IDX_W{1'b0}} : wr_idx_q};
  assign ram_waddr2 = ram_waddr + {{IDX_W{1'b0}}, 1'b1};
  assign ram_waddr3 = ram_waddr + {{IDX_W{1'b0}}, 2'd2};
  assign ram_waddr4 = ram_waddr + {{IDX_W{1'b0}}, 2'd3};
  assign ram_raddr = {play_bank_q, rd_addr_q};
  assign ram_wdata  = beat_i.data[63:0];
  assign ram_wdata2 = beat_i.data[127:64];
  assign ram_wdata3 = beat_i.data[191:128];
  assign ram_wdata4 = beat_i.data[255:192];
  assign ram_raddr1 = ram_raddr + {{IDX_W{1'b0}}, 1'b1};
  assign ram_raddr2 = ram_raddr + {{IDX_W{1'b0}}, 2'd2};
  assign ram_raddr3 = ram_raddr + {{IDX_W{1'b0}}, 2'd3};

`ifndef SYNTHESIS
  initial begin
    if ((SLOT_BYTES % 8) != 0)
      $error("rivet_dll_tlp_rx16 SLOT_BYTES (%0d) must be a multiple of 8", SLOT_BYTES);
  end
`endif

  rivet_ram_lane4 #(.DEPTH(RAM_N)) u_word_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .we_i    ({ram_we4, ram_we3, ram_we2, ram_we}),
    .waddr_i ('{ram_waddr, ram_waddr2, ram_waddr3, ram_waddr4}),
    .wdata_i ('{ram_wdata, ram_wdata2, ram_wdata3, ram_wdata4}),
    .re_i    (rd_issue),
    .raddr_i ('{ram_raddr, ram_raddr1, ram_raddr2, ram_raddr3}),
    .rdata_o (ram_rdata)
  );
  assign rd_lo_q = ram_rdata[0];
  assign rd_hi_q = ram_rdata[1];
  assign rd_c_q  = ram_rdata[2];
  assign rd_d_q  = ram_rdata[3];

  // Play geometry. Word 0 drops the 2-byte sequence number. A Gen3 beat
  // is two words (16 frame bytes). A Gen4 beat is four (32). The accumulator
  // realigns that onto OUT_B TLP bytes.
  always_comb begin
    logic [12:0] word_off;
    logic [5:0]  avail;
    logic [6:0]  n_after;
    logic [13:0] left_after;
    logic        want;
    logic        would_emit;
    logic [5:0]  room;
    word_off = {word_idx_q, 3'b000};
    avail    = '0;
    for (int unsigned wi = 0; wi < 4; wi++) begin
      if (wi < NWORD) begin
        automatic logic [12:0] off;
        automatic logic [5:0]  nb;
        off = word_off + 13'(wi * 8);
        nb  = '0;
        if (off < play_len_q) begin
          if (({1'b0, off} + 13'd8) <= {1'b0, play_len_q})
            nb = 6'd8;
          else
            nb = 6'(play_len_q - off);
        end
        if ((wi == 0) && (word_idx_q == '0))
          nb = (nb > 6'd2) ? (nb - 6'd2) : 6'd0;
        avail = avail + nb;
      end
    end
    take_skip  = (word_idx_q == '0) ? 6'd2 : 6'd0;
    take_n     = (14'(avail) > pld_left_q) ? pld_left_q[5:0] : avail;
    // 64 does not fit in 6 bits, so a 6-bit compare against 64 is a
    // compare against 0 and every Gen4 beat stalls.
    n_after    = {1'b0, acc_n_q} + {1'b0, take_n};
    left_after = pld_left_q - 14'(take_n);
    can_send   = !tl_v_q || tl_ready_i;
    room       = (OUT_B == 32) ? 6'd32 : 6'd16;
    want       = (play_st_q == PLAY_RUN) && fresh_q && (pld_left_q != 14'd0) &&
                 (acc_n_q <= room);
    would_emit = (n_after >= room) || ((left_after == 14'd0) && (n_after != 6'd0));
    // Words written on earlier cycles. A live frame must not read the beat
    // that capture is writing now, and must not end while more payload may
    // still arrive.
    words_ok   = !play_open_q || (play_bank_q != cap_bank_q) ||
                 (({1'b0, word_idx_q} + 7'(NWORD)) <= {1'b0, wr_idx_q});
    hold_tail  = play_open_q && (pld_left_q != 14'd0) && (pld_left_q <= 14'(avail));
    play_stall = want && (!words_ok || hold_tail ||
                          (n_after > ((OUT_B == 32) ? 7'd64 : 7'd32)) ||
                          (would_emit && !can_send));
    play_consume = want && !play_stall;
    more_after = play_consume && (left_after != 14'd0);
    rd_issue   = (play_st_q == PLAY_PREP) || more_after;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cap_st_q       <= CAP_IDLE;
      play_st_q      <= PLAY_IDLE;
      cap_bank_q     <= 1'b0;
      play_bank_q    <= 1'b0;
      bank_ready_q[0] <= 1'b0;
      bank_ready_q[1] <= 1'b0;
      bank_len_q[0]  <= '0;
      bank_len_q[1]  <= '0;
      bank_seq_q[0]  <= '0;
      bank_seq_q[1]  <= '0;
      bank_pld_q[0]  <= '0;
      bank_pld_q[1]  <= '0;
      wr_idx_q       <= '0;
      cap_len_q      <= '0;
      pld_left_q     <= '0;
      cap_seq_q      <= '0;
      seq_q          <= '0;
      cap_ovf_q      <= 1'b0;
      cap_crc_q      <= 32'hFFFF_FFFF;
      expect_q       <= 12'd0;
      last_good_q    <= 12'hFFF;
      lcrc_err_q     <= 1'b0;
      play_len_q     <= '0;
      rd_addr_q      <= '0;
      acc_q          <= '0;
      acc_n_q        <= '0;
      word_idx_q     <= '0;
      fresh_q        <= 1'b0;
      tl_v_q         <= 1'b0;
      tl_data_q      <= '0;
      tl_keep_q      <= '0;
      tl_last_q      <= 1'b0;
      play_open_q    <= 1'b0;
      pld_seen_q     <= '0;
      tl_sent_q      <= 1'b0;
      tl_abort_q     <= 1'b0;
      ack_slot_q[0]  <= '0;
      ack_slot_q[1]  <= '0;
      ack_n_q        <= 2'd0;
    end else begin
      logic              ready_b0;
      logic              ready_b1;
      logic [12:0]       blen0, blen1;
      logic [11:0]       bseq0, bseq1;
      logic [13:0]       bpld0, bpld1;
      logic              finish;
      logic              launch;
      logic              launch_b;
      logic              launch_live;
      logic              close_live;
      logic              abort_live;
      logic [12:0]       frame_vis_c;
      logic [13:0]       pld_vis_c;
      logic [13:0]       pld_delta;
      logic              emitted;
      logic [1:0]        ack_n;
      rivet_dllp_req_t   ack0;
      rivet_dllp_req_t   ack1;
      rivet_dllp_req_t   ack_new;

      ready_b0 = bank_ready_q[0];
      ready_b1 = bank_ready_q[1];
      blen0    = bank_len_q[0];
      blen1    = bank_len_q[1];
      bseq0    = bank_seq_q[0];
      bseq1    = bank_seq_q[1];
      bpld0    = bank_pld_q[0];
      bpld1    = bank_pld_q[1];
      finish      = 1'b0;
      launch      = 1'b0;
      launch_b    = 1'b0;
      launch_live = 1'b0;
      close_live  = 1'b0;
      abort_live  = 1'b0;
      frame_vis_c = 13'd0;
      pld_vis_c   = 14'd0;
      pld_delta   = 14'd0;
      tl_abort_q  <= 1'b0;
      if (take_beat && !beat_i.eop) begin
        // Hold the last 4 bytes until EOP. They may still be LCRC.
        frame_vis_c = (len_next > 13'd4) ? (len_next - 13'd4) : 13'd0;
        if (frame_vis_c > 13'd2)
          pld_vis_c = 14'(frame_vis_c - 13'd2);
      end
      launch_live = take_beat && !beat_i.eop && !play_open_q &&
                    (play_st_q == PLAY_IDLE) && (pld_vis_c >= 14'(OUT_B)) &&
                    !bank_ready_q[0] && !bank_ready_q[1];
      emitted  = 1'b0;
      ack0     = ack_slot_q[0];
      ack1     = ack_slot_q[1];
      ack_n    = ack_n_q;
      ack_new  = '0;
      if ((ack_n != 2'd0) && ack_ready_i) begin
        ack0  = ack1;
        ack_n = ack_n - 2'd1;
      end

      lcrc_err_q <= 1'b0;

      begin
        logic [2:0] nwords;
        nwords = 3'd1;
        if (nbytes > 8'd8)
          nwords = 3'd2;
        if (nbytes > 8'd16)
          nwords = 3'd3;
        if (nbytes > 8'd24)
          nwords = 3'd4;
      if (take_beat) begin
`ifndef SYNTHESIS
        if (!beat_i.sop && (cap_len_q[2:0] != 3'b000))
          $error("rivet_dll_tlp_rx16: unaligned len=%0d on non-SOP beat", int'(cap_len_q));
        if (beat_i.eop && (beat_i.keep != keep_prefix(nbytes[5:0])))
          $error("rivet_dll_tlp_rx16: keep %04h is not a low prefix of %0d bytes",
                 beat_i.keep, nbytes);
`endif
        cap_len_q <= len_next;
        cap_crc_q <= crc_next;
        wr_idx_q  <= beat_i.sop
                       ? IDX_W'(nwords)
                       : (wr_idx_q + IDX_W'(nwords));
        if (beat_i.sop) begin
          cap_seq_q <= {beat_i.data[3:0], beat_i.data[15:8]};
          cap_st_q  <= CAP_RUN;
        end
        if (int'(len_next) > SLOT_BYTES)
          cap_ovf_q <= 1'b1;
      end
      end

      if (take_beat && beat_i.eop) begin
        cap_st_q <= CAP_DEC;
        // The next frame must not overwrite the bank this playback is reading.
        if (play_open_q || launch_live)
          cap_bank_q <= ~cap_bank_q;
      end else if (cap_st_q == CAP_DEC) begin
        if (ack_n == 2'd2) begin
          // The ACK/NAK queue is full. Hold the decision for one cycle.
        end else begin
          logic        lcrc_ok;
          logic        seq_ok;
          logic        seq_dup;
          logic [11:0] seq_delta;
          logic [13:0] pld_len;
          lcrc_ok  = (cap_crc_q == RIVET_LCRC32_RESIDUE) &&
                     (int'(cap_len_q) >= MIN_FR) && !cap_ovf_q;
          seq_ok   = (cap_seq_q == expect_q);
          seq_delta = expect_q - cap_seq_q;
          seq_dup  = lcrc_ok && !seq_ok && (seq_delta != 12'd0) && (seq_delta <= 12'd32);
          pld_len  = (int'(cap_len_q) >= MIN_FR) ? 14'(int'(cap_len_q) - MIN_FR) : 14'd0;
`ifndef SYNTHESIS
          $display("[%t] : TLP RX eop len=%0d seq=%03h expect=%03h crc=%08h ok=%0b seq_ok=%0b dup=%0b",
                   $realtime, int'(cap_len_q), cap_seq_q, expect_q, cap_crc_q,
                   lcrc_ok, seq_ok, seq_dup);
`endif
          cap_ovf_q <= 1'b0;
          cap_len_q <= '0;
          cap_crc_q <= 32'hFFFF_FFFF;
          wr_idx_q  <= '0;
          ack_new   = '0;
          if (lcrc_ok && seq_ok) begin
            last_good_q    <= cap_seq_q;
            expect_q       <= cap_seq_q + 12'd1;
            ack_new.kind    = RIVET_DLLP_KIND_ACK;
            ack_new.ack_seq = cap_seq_q;
            if (play_open_q) begin
              // Bytes are already moving. Releasing the held tail is enough.
              // cap_bank already moved off this frame at EOP.
              close_live = 1'b1;
              if (pld_len > pld_seen_q)
                pld_delta = pld_len - pld_seen_q;
            end else if (pld_len != 14'd0) begin
              bank_len_q[cap_bank_q]   <= cap_len_q;
              bank_seq_q[cap_bank_q]   <= cap_seq_q;
              bank_pld_q[cap_bank_q]   <= pld_len;
              bank_ready_q[cap_bank_q] <= 1'b1;
              if (cap_bank_q == 1'b0) begin
                ready_b0 = 1'b1;
                blen0    = cap_len_q;
                bseq0    = cap_seq_q;
                bpld0    = pld_len;
              end else begin
                ready_b1 = 1'b1;
                blen1    = cap_len_q;
                bseq1    = cap_seq_q;
                bpld1    = pld_len;
              end
            end
          end else if (seq_dup) begin
            ack_new.kind    = RIVET_DLLP_KIND_ACK;
            ack_new.ack_seq = last_good_q;
          end else begin
            lcrc_err_q      <= !lcrc_ok;
            ack_new.kind    = RIVET_DLLP_KIND_NAK;
            ack_new.ack_seq = last_good_q;
            if (play_open_q)
              abort_live = 1'b1;
          end
          if (ack_n == 2'd0) ack0 = ack_new;
          else               ack1 = ack_new;
          ack_n    = ack_n + 2'd1;
          cap_st_q <= CAP_IDLE;
        end
      end

      if (play_st_q == PLAY_PREP) begin
        fresh_q    <= 1'b1;
        word_idx_q <= '0;
        rd_addr_q  <= IDX_W'(NWORD);
        play_st_q  <= PLAY_RUN;
      end else if (play_st_q == PLAY_RUN) begin
        logic [511:0] acc_t;
        logic [5:0]   n_t;
        logic [13:0]  left_t;
        logic [5:0]   emit_n;
        logic [5:0]   room;
        logic [255:0] srcw;
        logic [31:0]  keep_full;
        acc_t  = acc_q;
        n_t    = acc_n_q;
        left_t = pld_left_q;
        emit_n = 6'd0;
        room   = 6'(OUT_B);
        srcw   = {rd_d_q, rd_c_q, rd_hi_q, rd_lo_q};
        if (play_consume) begin
          // Pre-shift by take_skip (0 or 2) with a 2:1 mux, then select
          // each destination byte in parallel instead of a 32-deep cascade.
          logic [255:0] srcw_s;
          logic [7:0]   sb [32];
          srcw_s = (take_skip != 6'd0) ? {16'h0, srcw[255:16]} : srcw;
          for (int unsigned i = 0; i < 32; i++)
            sb[5'(i)] = srcw_s[8*5'(i) +: 8];
          for (int unsigned k = 0; k < 64; k++) begin
            automatic logic [6:0] diff;
            diff = 7'(k) - {1'b0, acc_n_q};
            if ((7'(k) >= {1'b0, acc_n_q}) && (diff < {1'b0, take_n}))
              acc_t[8*6'(k) +: 8] = sb[diff[4:0]];
          end
          n_t    = acc_n_q + take_n;
          left_t = pld_left_q - 14'(take_n);
        end
        if (!play_stall && can_send &&
            ((n_t >= room) || ((left_t == 14'd0) && (n_t != 6'd0)))) begin
          emit_n = (n_t >= room) ? room : n_t;
          keep_full = keep_prefix(emit_n);
          tl_data_q <= acc_t[DATA_W-1:0];
          tl_keep_q <= keep_full[DATA_W/8-1:0];
          tl_v_q    <= 1'b1;
          tl_last_q <= (left_t == 14'd0) && (emit_n == n_t) && !play_open_q;
          tl_sent_q <= 1'b1;
          emitted    = 1'b1;
          // Full beat always shifts by constant OUT_B; short final beat drains n_t to 0.
          acc_t = (n_t >= room) ? (acc_t >> (OUT_B * 8)) : 512'h0;
          n_t   = n_t - emit_n;
          if ((left_t == 14'd0) && (n_t == 6'd0))
            finish = 1'b1;
        end
        acc_q      <= acc_t;
        acc_n_q    <= n_t;
        pld_left_q <= left_t;
        if (play_stall || more_after)
          fresh_q <= 1'b1;
        else if (play_consume)
          fresh_q <= 1'b0;
        if (play_consume) begin
          word_idx_q <= word_idx_q + IDX_W'(NWORD);
          if (more_after)
            rd_addr_q <= rd_addr_q + IDX_W'(NWORD);
        end
        if (finish && !play_open_q)
          play_st_q <= PLAY_IDLE;
      end

      if (((play_st_q == PLAY_IDLE) || finish) && (play_st_q != PLAY_PREP)) begin
        if (ready_b0) begin
          launch   = 1'b1;
          launch_b = 1'b0;
        end else if (ready_b1) begin
          launch   = 1'b1;
          launch_b = 1'b1;
        end
      end
      if (launch) begin
        play_bank_q <= launch_b;
        play_len_q  <= launch_b ? blen1 : blen0;
        pld_left_q  <= launch_b ? bpld1 : bpld0;
        seq_q       <= launch_b ? bseq1 : bseq0;
        bank_ready_q[launch_b] <= 1'b0;
        acc_q       <= '0;
        acc_n_q     <= '0;
        word_idx_q  <= '0;
        fresh_q     <= 1'b0;
        rd_addr_q   <= '0;
        play_st_q   <= PLAY_PREP;
        if (bank_ready_q[cap_bank_q] || (cap_bank_q == launch_b))
          cap_bank_q <= ~launch_b;
      end else if (finish && bank_ready_q[cap_bank_q] && !play_open_q) begin
        cap_bank_q <= ~cap_bank_q;
      end

      if (play_open_q && take_beat && !beat_i.eop && !launch_live &&
          (pld_vis_c > pld_seen_q)) begin
        pld_delta   = pld_vis_c - pld_seen_q;
        pld_seen_q  <= pld_vis_c;
        play_len_q  <= frame_vis_c;
      end
      if ((pld_delta != 14'd0) &&
          ((play_st_q == PLAY_RUN) || (play_st_q == PLAY_PREP)))
        pld_left_q <= (play_consume ? (pld_left_q - 14'(take_n)) : pld_left_q) + pld_delta;
      if (close_live) begin
        play_open_q <= 1'b0;
        pld_seen_q  <= pld_seen_q + pld_delta;
        play_len_q  <= cap_len_q;
      end
      if (abort_live) begin
        play_open_q <= 1'b0;
        play_st_q   <= PLAY_IDLE;
        pld_left_q  <= '0;
        pld_seen_q  <= '0;
        tl_v_q      <= 1'b0;
        tl_last_q   <= 1'b0;
        tl_sent_q   <= 1'b0;
        if (tl_sent_q)
          tl_abort_q <= 1'b1;
      end else if (launch_live) begin
        play_open_q <= 1'b1;
        play_bank_q <= cap_bank_q;
        play_len_q  <= frame_vis_c;
        pld_left_q  <= pld_vis_c;
        pld_seen_q  <= pld_vis_c;
        seq_q       <= cap_seq_q;
        acc_q       <= '0;
        acc_n_q     <= '0;
        word_idx_q  <= '0;
        fresh_q     <= 1'b0;
        rd_addr_q   <= '0;
        play_st_q   <= PLAY_PREP;
        tl_sent_q   <= 1'b0;
      end else if (finish && !play_open_q) begin
        tl_sent_q <= 1'b0;
      end

      ack_slot_q[0] <= ack0;
      ack_slot_q[1] <= ack1;
      ack_n_q       <= ack_n;
      // A beat stays valid only until it is accepted. Playback often leaves
      // RUN on the same cycle it emits, so the drop has to happen in IDLE too.
      // Otherwise a one-beat completion is parsed again on every later idle.
      if (!emitted && tl_v_q && tl_ready_i)
        tl_v_q <= 1'b0;
    end
  end

endmodule : rivet_dll_tlp_rx16

// Four consecutive 64-bit words do not fit one block RAM. Each address
// lands in a different bank, and each bank has one write and one read.
module rivet_ram_lane4 #(
  parameter int unsigned DEPTH = 2048
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [3:0]               we_i,
  input  logic [$clog2(DEPTH)-1:0] waddr_i [4],
  input  logic [63:0]              wdata_i [4],
  input  logic                     re_i,
  input  logic [$clog2(DEPTH)-1:0] raddr_i [4],
  output logic [63:0]              rdata_o [4]
);
  localparam int unsigned AW      = $clog2(DEPTH);
  localparam int unsigned BANK_N  = DEPTH / 4;

  logic [63:0] dout_b [4];
  logic [1:0]  rbank_q [4];

  generate
    for (genvar b = 0; b < 4; b++) begin : g_bank
      (* ram_style = "block" *) logic [63:0] mem [0:BANK_N-1];
      logic              we, re;
      logic [AW-3:0]     widx, ridx;
      logic [63:0]       wdat;
      logic [63:0]       dout;

      always_comb begin
        we   = 1'b0;
        re   = 1'b0;
        widx = '0;
        ridx = '0;
        wdat = '0;
        if (we_i[0] && (waddr_i[0][1:0] == b[1:0])) begin
          we   = 1'b1;
          widx = waddr_i[0][AW-1:2];
          wdat = wdata_i[0];
        end
        if (we_i[1] && (waddr_i[1][1:0] == b[1:0])) begin
          we   = 1'b1;
          widx = waddr_i[1][AW-1:2];
          wdat = wdata_i[1];
        end
        if (we_i[2] && (waddr_i[2][1:0] == b[1:0])) begin
          we   = 1'b1;
          widx = waddr_i[2][AW-1:2];
          wdat = wdata_i[2];
        end
        if (we_i[3] && (waddr_i[3][1:0] == b[1:0])) begin
          we   = 1'b1;
          widx = waddr_i[3][AW-1:2];
          wdat = wdata_i[3];
        end
        if (re_i && (raddr_i[0][1:0] == b[1:0])) begin
          re   = 1'b1;
          ridx = raddr_i[0][AW-1:2];
        end
        if (re_i && (raddr_i[1][1:0] == b[1:0])) begin
          re   = 1'b1;
          ridx = raddr_i[1][AW-1:2];
        end
        if (re_i && (raddr_i[2][1:0] == b[1:0])) begin
          re   = 1'b1;
          ridx = raddr_i[2][AW-1:2];
        end
        if (re_i && (raddr_i[3][1:0] == b[1:0])) begin
          re   = 1'b1;
          ridx = raddr_i[3][AW-1:2];
        end
      end

`ifndef SYNTHESIS
      initial begin
        for (int unsigned ii = 0; ii < BANK_N; ii++)
          mem[ii] = '0;
      end
`endif

      always_ff @(posedge clk_i) begin
        if (we)
          mem[widx] <= wdat;
      end

      always_ff @(posedge clk_i) begin
        if (!rst_ni)
          dout <= '0;
        else if (re)
          dout <= mem[ridx];
      end

      assign dout_b[b] = dout;
    end
  endgenerate

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rbank_q[0] <= '0;
      rbank_q[1] <= '0;
      rbank_q[2] <= '0;
      rbank_q[3] <= '0;
    end else if (re_i) begin
      rbank_q[0] <= raddr_i[0][1:0];
      rbank_q[1] <= raddr_i[1][1:0];
      rbank_q[2] <= raddr_i[2][1:0];
      rbank_q[3] <= raddr_i[3][1:0];
    end
  end

  always_comb begin
    rdata_o[0] = dout_b[rbank_q[0]];
    rdata_o[1] = dout_b[rbank_q[1]];
    rdata_o[2] = dout_b[rbank_q[2]];
    rdata_o[3] = dout_b[rbank_q[3]];
  end
endmodule

