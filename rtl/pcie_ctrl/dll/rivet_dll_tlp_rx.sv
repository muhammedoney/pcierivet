// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Assemble MAC TLP beats, check Seq# / LCRC, deliver payload to TL, schedule ACK/NAK.
//
// Two word-RAM banks. Playback of one frame reads its bank while the next
// frame is captured into the other, so a completion burst is not stored and
// then played back to back. Nothing wider than a word is clocked.

module rivet_dll_tlp_rx #(
  parameter int unsigned SLOT_BYTES = 4128
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        enable_i,

  input  rivet_pkg::rivet_dll_mac_rx_beat_t beat_i,
  input  logic                              beat_valid_i,
  output logic                              beat_ready_o,

  output logic                       tl_valid_o,
  input  logic                       tl_ready_i,
  output logic [63:0]                tl_data_o,
  output logic [7:0]                 tl_keep_o,
  output logic                       tl_last_o,
  output logic [11:0]                tl_seq_o,

  output rivet_pkg::rivet_dllp_req_t ack_req_o,
  output logic                       ack_valid_o,
  input  logic                       ack_ready_i,

  output logic [11:0] last_good_seq_o,
  output logic        lcrc_err_o,
  // One cycle after a cut-through frame fails LCRC and some TLP bytes
  // were already handed to TL.
  output logic        tl_abort_o
);

  import rivet_pkg::*;

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

  (* ram_style = "block" *) logic [63:0] word_ram [0:RAM_N-1];
  logic              ram_we;
  logic [IDX_W:0]    ram_waddr;
  logic [IDX_W:0]    ram_raddr;
  logic [63:0]       ram_wdata;
  logic [63:0]       rd_q;
  logic [IDX_W-1:0]  rd_addr_q;

  logic [127:0]      acc_q;
  logic [4:0]        acc_n_q;
  logic [IDX_W-1:0]  word_idx_q;
  logic              fresh_q;

  logic              can_send;
  logic              play_stall;
  logic              play_consume;
  logic              more_after;
  logic              rd_issue;
  logic [3:0]        take_n;
  logic [3:0]        take_skip;

  logic              tl_v_q;
  logic [63:0]       tl_data_q;
  logic [7:0]        tl_keep_q;
  logic              tl_last_q;
  // Playback started before LCRC. The last 4 frame bytes stay held.
  logic              play_open_q;
  logic [13:0]       pld_seen_q;
  logic              tl_sent_q;
  logic              tl_abort_q;
  logic              words_ok;
  logic              hold_tail;

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

  function automatic logic [7:0] keep_popcount(input logic [7:0] k);
    return 8'(k[0]) + 8'(k[1]) + 8'(k[2]) + 8'(k[3]) +
           8'(k[4]) + 8'(k[5]) + 8'(k[6]) + 8'(k[7]);
  endfunction

  logic        take_beat;
  logic [7:0]  nbytes;
  logic [31:0] crc_next;
  logic [12:0] len_next;

  assign nbytes    = keep_popcount(beat_i.keep);
  assign take_beat = beat_valid_i && beat_ready_o &&
                     (beat_i.pkt_type == RIVET_MAC_PKT_TLP) && !beat_i.err;
  assign len_next  = beat_i.sop ? {5'd0, nbytes} : (cap_len_q + {5'd0, nbytes});
  assign crc_next  = rivet_crc32_fold(
      (take_beat && beat_i.sop) ? 32'hFFFF_FFFF : cap_crc_q,
      beat_i.data, nbytes[3:0]);

  assign ram_we    = take_beat && !cap_ovf_q &&
                     (wr_idx_q != IDX_W'(10'h3FF) || beat_i.sop);
  assign ram_waddr = {cap_bank_q, beat_i.sop ? {IDX_W{1'b0}} : wr_idx_q};
  assign ram_raddr = {play_bank_q, rd_addr_q};
  assign ram_wdata = beat_i.data;

`ifndef SYNTHESIS
  initial begin
    if ((SLOT_BYTES % 8) != 0)
      $error("rivet_dll_tlp_rx SLOT_BYTES (%0d) must be a multiple of 8", SLOT_BYTES);
    for (int unsigned ii = 0; ii < RAM_N; ii++) word_ram[ii] = '0;
  end
`endif

  always_ff @(posedge clk_i) begin
    if (ram_we)
      word_ram[ram_waddr] <= ram_wdata;
  end

  // Synchronous read-data reset. An async BRAM reset fails Versal REQP-2042.
  always_ff @(posedge clk_i) begin
    if (!rst_ni)
      rd_q <= '0;
    else if (rd_issue)
      rd_q <= word_ram[ram_raddr];
  end

  // Play geometry. Word 0 contributes 6 bytes (the sequence number is 2).
  always_comb begin
    logic [12:0] word_off;
    logic [3:0]  bytes_here;
    logic [3:0]  skip;
    logic [3:0]  avail;
    logic [4:0]  n_after;
    logic [13:0] left_after;
    logic        want;
    word_off   = {word_idx_q, 3'b000};
    bytes_here = (({1'b0, word_off} + 13'd8) <= {1'b0, play_len_q})
                 ? 4'd8 : 4'(play_len_q - word_off);
    skip       = (word_idx_q == '0) ? 4'd2 : 4'd0;
    avail      = (bytes_here > skip) ? (bytes_here - skip) : 4'd0;
    take_n     = (14'(avail) > pld_left_q) ? pld_left_q[3:0] : avail;
    take_skip  = skip;
    n_after    = acc_n_q + 5'(take_n);
    left_after = pld_left_q - 14'(take_n);
    can_send   = !tl_v_q || tl_ready_i;
    want       = (play_st_q == PLAY_RUN) && fresh_q && (pld_left_q != 14'd0) &&
                 (acc_n_q <= 5'd6);
    words_ok   = !play_open_q || (play_bank_q != cap_bank_q) ||
                 (word_idx_q < wr_idx_q);
    hold_tail  = play_open_q && (pld_left_q != 14'd0) && (pld_left_q <= 14'(avail));
    play_stall = want && (!words_ok || hold_tail ||
                          (((n_after >= 5'd8) ||
                            ((left_after == 14'd0) && (n_after != 5'd0))) && !can_send));
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
      logic [1:0]        ack_n;
      rivet_dllp_req_t   ack0;
      rivet_dllp_req_t   ack1;
      rivet_dllp_req_t   ack_new;

      logic              launch_live;
      logic              close_live;
      logic              abort_live;
      logic [12:0]       frame_vis;
      logic [13:0]       pld_vis;
      logic [13:0]       pld_delta;
      logic [13:0]       pld_len;
      logic [13:0]       left_add;

      ready_b0 = bank_ready_q[0];
      ready_b1 = bank_ready_q[1];
      blen0    = bank_len_q[0];
      blen1    = bank_len_q[1];
      bseq0    = bank_seq_q[0];
      bseq1    = bank_seq_q[1];
      bpld0    = bank_pld_q[0];
      bpld1    = bank_pld_q[1];
      finish   = 1'b0;
      launch   = 1'b0;
      launch_b = 1'b0;
      launch_live = 1'b0;
      close_live  = 1'b0;
      abort_live  = 1'b0;
      frame_vis   = 13'd0;
      pld_vis     = 14'd0;
      pld_delta   = 14'd0;
      pld_len     = 14'd0;
      left_add    = 14'd0;
      ack0     = ack_slot_q[0];
      ack1     = ack_slot_q[1];
      ack_n    = ack_n_q;
      ack_new  = '0;
      if ((ack_n != 2'd0) && ack_ready_i) begin
        ack0  = ack1;
        ack_n = ack_n - 2'd1;
      end

      lcrc_err_q <= 1'b0;
      tl_abort_q <= 1'b0;

      frame_vis = (take_beat && !beat_i.eop) ? (len_next - 13'd4) : 13'd0;
      pld_vis   = (frame_vis > 13'd2) ? 14'(frame_vis - 13'd2) : 14'd0;

      if (take_beat) begin
`ifndef SYNTHESIS
        if (!beat_i.sop && (cap_len_q[2:0] != 3'b000))
          $error("rivet_dll_tlp_rx: unaligned len=%0d on non-SOP beat", int'(cap_len_q));
        if (beat_i.eop && (beat_i.keep != (8'hFF >> (8 - nbytes))))
          $error("rivet_dll_tlp_rx: keep %02h is not a low prefix of %0d bytes",
                 beat_i.keep, nbytes);
`endif
        cap_len_q <= len_next;
        cap_crc_q <= crc_next;
        wr_idx_q  <= beat_i.sop ? IDX_W'(1) : (wr_idx_q + IDX_W'(1));
        if (beat_i.sop) begin
          cap_seq_q <= {beat_i.data[3:0], beat_i.data[15:8]};
          cap_st_q  <= CAP_RUN;
        end
        if (int'(len_next) > SLOT_BYTES)
          cap_ovf_q <= 1'b1;
        // One full TL beat (8 bytes) is enough to start. The tail stays held.
        if (!beat_i.eop && !play_open_q && (play_st_q == PLAY_IDLE) &&
            (pld_vis >= 14'd8) && !bank_ready_q[0] && !bank_ready_q[1])
          launch_live = 1'b1;
      end

      if (take_beat && beat_i.eop && play_open_q)
        cap_bank_q <= ~cap_bank_q;

      if (take_beat && beat_i.eop) begin
        cap_st_q <= CAP_DEC;
      end else if (cap_st_q == CAP_DEC) begin
        if (ack_n == 2'd2) begin
          // The ACK/NAK queue is full. Hold the decision for one cycle.
        end else begin
          logic        lcrc_ok;
          logic        seq_ok;
          logic        seq_dup;
          logic [11:0] seq_delta;
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
              close_live = 1'b1;
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
        rd_addr_q  <= IDX_W'(1);
        play_st_q  <= PLAY_RUN;
      end else if (play_st_q == PLAY_RUN) begin
        logic [127:0] acc_t;
        logic [4:0]   n_t;
        logic [13:0]  left_t;
        acc_t  = acc_q;
        n_t    = acc_n_q;
        left_t = pld_left_q;
        if (play_consume) begin
          for (int unsigned bi = 0; bi < 8; bi++) begin
            if (4'(bi) < take_n) begin
              acc_t[8*(acc_n_q + 5'(bi)) +: 8] = rd_q[8*(take_skip + 4'(bi)) +: 8];
              n_t = n_t + 5'd1;
            end
          end
          left_t = pld_left_q - 14'(take_n);
        end
        if (!play_stall && can_send &&
            ((n_t >= 5'd8) || ((left_t == 14'd0) && (n_t != 5'd0)))) begin
          logic [3:0] emit_n;
          emit_n = (n_t >= 5'd8) ? 4'd8 : n_t[3:0];
          tl_data_q <= acc_t[63:0];
          tl_keep_q <= (emit_n == 4'd8) ? 8'hFF : (8'hFF >> (8 - emit_n));
          tl_v_q    <= 1'b1;
          tl_last_q <= (left_t == 14'd0) && (5'(emit_n) == n_t) && !play_open_q;
          acc_t = acc_t >> (8 * emit_n);
          n_t   = n_t - 5'(emit_n);
          if ((left_t == 14'd0) && (n_t == 5'd0) && !play_open_q)
            finish = 1'b1;
        end else if (!play_stall && tl_v_q && tl_ready_i) begin
          tl_v_q <= 1'b0;
        end
        acc_q      <= acc_t;
        acc_n_q    <= n_t;
        pld_left_q <= left_t;
        if (play_stall || more_after)
          fresh_q <= 1'b1;
        else if (play_consume)
          fresh_q <= 1'b0;
        if (play_consume) begin
          word_idx_q <= word_idx_q + IDX_W'(1);
          if (more_after)
            rd_addr_q <= rd_addr_q + IDX_W'(1);
          tl_sent_q <= 1'b1;
        end
        if (finish && !play_open_q)
          play_st_q <= PLAY_IDLE;
      end else if (tl_v_q && tl_ready_i) begin
        tl_v_q <= 1'b0;
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

      if (launch_live) begin
        play_open_q <= 1'b1;
        play_bank_q <= cap_bank_q;
        play_len_q  <= frame_vis;
        pld_left_q  <= pld_vis;
        pld_seen_q  <= pld_vis;
        seq_q       <= cap_seq_q;
        acc_q       <= '0;
        acc_n_q     <= '0;
        word_idx_q  <= '0;
        fresh_q     <= 1'b0;
        rd_addr_q   <= '0;
        tl_sent_q   <= 1'b0;
        play_st_q   <= PLAY_PREP;
      end else if (play_open_q && take_beat && !beat_i.eop && (pld_vis > pld_seen_q)) begin
        pld_delta   = pld_vis - pld_seen_q;
        pld_seen_q <= pld_vis;
        play_len_q <= frame_vis;
      end
      if (close_live) begin
        pld_delta   = pld_len - pld_seen_q;
        play_open_q <= 1'b0;
        play_len_q  <= cap_len_q;
      end
      if (abort_live) begin
        play_open_q <= 1'b0;
        play_st_q   <= PLAY_IDLE;
        pld_left_q  <= '0;
        tl_v_q      <= 1'b0;
        tl_last_q   <= 1'b0;
        tl_abort_q  <= tl_sent_q;
      end
      if ((pld_delta != 14'd0) &&
          ((play_st_q == PLAY_RUN) || (play_st_q == PLAY_PREP))) begin
        left_add = ((play_st_q == PLAY_RUN) && play_consume)
                   ? (pld_left_q - 14'(take_n)) : pld_left_q;
        pld_left_q <= left_add + pld_delta;
      end

      ack_slot_q[0] <= ack0;
      ack_slot_q[1] <= ack1;
      ack_n_q       <= ack_n;
    end
  end

endmodule : rivet_dll_tlp_rx
