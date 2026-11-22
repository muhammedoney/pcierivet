// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Assemble MAC TLP beats, check Seq# / LCRC, deliver payload to TL, schedule ACK/NAK.
//
// The frame sits in a block RAM, one 64-bit word per cycle. Payload beats
// shift off the 2-byte sequence number and stop before the 4-byte LCRC.
// Nothing wider than a word is clocked, so a 4 KB completion does not
// rebuild the wide RX bus that missed 250 MHz.

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
  output logic        lcrc_err_o
);

  import rivet_pkg::*;

  localparam int unsigned MIN_FR   = RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES;
  localparam int unsigned RAM_N    = 1024;
  localparam int unsigned RAM_W    = 10;

  typedef enum logic [1:0] {
    ST_CAP  = 2'd0,
    ST_DEC  = 2'd1,
    ST_PREP = 2'd2,
    ST_PLAY = 2'd3
  } st_e;

  st_e               st_q;
  logic [RAM_W-1:0]  wr_idx_q;
  logic [12:0]       len_q;
  logic [13:0]       pld_left_q;
  logic [11:0]       seq_lat_q;
  logic [11:0]       seq_q;
  logic              ovf_q;
  logic [31:0]       crc_q;
  logic [11:0]       expect_q;
  logic [11:0]       last_good_q;
  logic              lcrc_err_q;

  (* ram_style = "block" *) logic [63:0] word_ram [0:RAM_N-1];
  logic              ram_we;
  logic [RAM_W-1:0]  ram_waddr;
  logic [63:0]       ram_wdata;
  logic [63:0]       rd_q;
  logic              rd_capture_q;
  logic [RAM_W-1:0]  rd_addr_q;

  logic [127:0]      acc_q;
  logic [4:0]        acc_n_q;
  logic [RAM_W-1:0]  word_idx_q;
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

  rivet_dllp_req_t   ack_q;
  logic              ack_pend_q;

  assign tl_valid_o      = tl_v_q;
  assign tl_data_o       = tl_data_q;
  assign tl_keep_o       = tl_keep_q;
  assign tl_last_o       = tl_last_q;
  assign tl_seq_o        = seq_q;
  assign ack_valid_o     = ack_pend_q;
  assign ack_req_o       = ack_q;
  assign last_good_seq_o = last_good_q;
  assign lcrc_err_o      = lcrc_err_q;
  assign beat_ready_o    = enable_i && (st_q == ST_CAP);

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
  assign len_next  = beat_i.sop ? {5'd0, nbytes} : (len_q + {5'd0, nbytes});
  assign crc_next  = rivet_crc32_fold(
      (take_beat && beat_i.sop) ? 32'hFFFF_FFFF : crc_q,
      beat_i.data, nbytes[3:0]);

  assign ram_we    = take_beat && !ovf_q && (wr_idx_q != RAM_W'(RAM_N-1) || beat_i.sop);
  assign ram_waddr = beat_i.sop ? '0 : wr_idx_q;
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
  // rd_issue is comb so a consumed word prefetches the next one this cycle.
  always_ff @(posedge clk_i) begin
    if (!rst_ni)
      rd_q <= '0;
    else if (rd_issue)
      rd_q <= word_ram[rd_addr_q];
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
    bytes_here = (({1'b0, word_off} + 13'd8) <= {1'b0, len_q})
                 ? 4'd8 : 4'(len_q - word_off);
    skip       = (word_idx_q == '0) ? 4'd2 : 4'd0;
    avail      = (bytes_here > skip) ? (bytes_here - skip) : 4'd0;
    take_n     = (14'(avail) > pld_left_q) ? pld_left_q[3:0] : avail;
    take_skip  = skip;
    n_after    = acc_n_q + 5'(take_n);
    left_after = pld_left_q - 14'(take_n);
    can_send   = !tl_v_q || tl_ready_i;
    want       = (st_q == ST_PLAY) && fresh_q && (pld_left_q != 14'd0) && (acc_n_q <= 5'd6);
    play_stall = want && (((n_after >= 5'd8) ||
                           ((left_after == 14'd0) && (n_after != 5'd0))) && !can_send);
    play_consume = want && !play_stall;
    more_after = play_consume && (left_after != 14'd0);
    rd_issue   = (st_q == ST_PREP) || more_after;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q         <= ST_CAP;
      wr_idx_q     <= '0;
      len_q        <= '0;
      pld_left_q   <= '0;
      seq_lat_q    <= '0;
      seq_q        <= '0;
      ovf_q        <= 1'b0;
      crc_q        <= 32'hFFFF_FFFF;
      expect_q     <= 12'd0;
      last_good_q  <= 12'hFFF;
      lcrc_err_q   <= 1'b0;
      rd_capture_q <= 1'b0;
      rd_addr_q    <= '0;
      acc_q        <= '0;
      acc_n_q      <= '0;
      word_idx_q   <= '0;
      fresh_q      <= 1'b0;
      tl_v_q       <= 1'b0;
      tl_data_q    <= '0;
      tl_keep_q    <= '0;
      tl_last_q    <= 1'b0;
      ack_q        <= '0;
      ack_pend_q   <= 1'b0;
    end else begin
      lcrc_err_q <= 1'b0;
      if (ack_pend_q && ack_ready_i)
        ack_pend_q <= 1'b0;

      if (take_beat) begin
`ifndef SYNTHESIS
        if (!beat_i.sop && (len_q[2:0] != 3'b000))
          $error("rivet_dll_tlp_rx: unaligned len=%0d on non-SOP beat", int'(len_q));
        if (beat_i.eop && (beat_i.keep != (8'hFF >> (8 - nbytes))))
          $error("rivet_dll_tlp_rx: keep %02h is not a low prefix of %0d bytes",
                 beat_i.keep, nbytes);
`endif
        len_q    <= len_next;
        crc_q    <= crc_next;
        wr_idx_q <= beat_i.sop ? RAM_W'(1) : (wr_idx_q + RAM_W'(1));
        if (beat_i.sop)
          seq_lat_q <= {beat_i.data[3:0], beat_i.data[15:8]};
        if (int'(len_next) > SLOT_BYTES)
          ovf_q <= 1'b1;
      end

      if (take_beat && beat_i.eop) begin
        st_q <= ST_DEC;
      end else if (st_q == ST_DEC) begin
        logic        lcrc_ok;
        logic        seq_ok;
        logic        seq_dup;
        logic [11:0] seq_delta;
        logic [13:0] pld_len;
        lcrc_ok  = (crc_q == RIVET_LCRC32_RESIDUE) && (int'(len_q) >= MIN_FR) && !ovf_q;
        seq_ok   = (seq_lat_q == expect_q);
        seq_delta = expect_q - seq_lat_q;
        seq_dup  = lcrc_ok && !seq_ok && (seq_delta != 12'd0) && (seq_delta <= 12'd32);
        pld_len  = (int'(len_q) >= MIN_FR) ? 14'(int'(len_q) - MIN_FR) : 14'd0;
`ifndef SYNTHESIS
        $display("[%t] : TLP RX eop len=%0d seq=%03h expect=%03h crc=%08h ok=%0b seq_ok=%0b dup=%0b",
                 $realtime, int'(len_q), seq_lat_q, expect_q, crc_q,
                 lcrc_ok, seq_ok, seq_dup);
`endif
        ovf_q      <= 1'b0;
        ack_q      <= '0;
        ack_pend_q <= 1'b1;
        if (lcrc_ok && seq_ok) begin
          last_good_q   <= seq_lat_q;
          expect_q      <= seq_lat_q + 12'd1;
          seq_q         <= seq_lat_q;
          ack_q.kind    <= RIVET_DLLP_KIND_ACK;
          ack_q.ack_seq <= seq_lat_q;
          if (pld_len != 14'd0) begin
            pld_left_q   <= pld_len;
            acc_q        <= '0;
            acc_n_q      <= '0;
            word_idx_q   <= '0;
            fresh_q      <= 1'b0;
            rd_addr_q    <= '0;
            rd_capture_q <= 1'b0;
            st_q         <= ST_PREP;
          end else begin
            st_q <= ST_CAP;
          end
        end else if (seq_dup) begin
          ack_q.kind    <= RIVET_DLLP_KIND_ACK;
          ack_q.ack_seq <= last_good_q;
          st_q          <= ST_CAP;
        end else begin
          lcrc_err_q    <= !lcrc_ok;
          ack_q.kind    <= RIVET_DLLP_KIND_NAK;
          ack_q.ack_seq <= last_good_q;
          st_q          <= ST_CAP;
        end
      end else if (st_q == ST_PREP) begin
        // word 0 is captured this cycle (rd_issue). First play cycle must not recapture it.
        fresh_q      <= 1'b1;
        word_idx_q   <= '0;
        rd_addr_q    <= RAM_W'(1);
        rd_capture_q <= 1'b0;
        st_q         <= ST_PLAY;
      end else if (st_q == ST_PLAY) begin
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
          tl_last_q <= (left_t == 14'd0) && (5'(emit_n) == n_t);
          acc_t = acc_t >> (8 * emit_n);
          n_t   = n_t - 5'(emit_n);
          if ((left_t == 14'd0) && (n_t == 5'd0))
            st_q <= ST_CAP;
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
          word_idx_q <= word_idx_q + RAM_W'(1);
          if (more_after)
            rd_addr_q <= rd_addr_q + RAM_W'(1);
        end
      end
    end
  end

endmodule : rivet_dll_tlp_rx
