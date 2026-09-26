// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Assemble MAC TLP beats, check Seq# / LCRC, deliver payload to TL, schedule ACK/NAK.

module rivet_dll_tlp_rx #(
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        enable_i,

  input  rivet_pkg::rivet_dll_mac_rx_beat_t beat_i,
  input  logic                              beat_valid_i,
  output logic                              beat_ready_o,

  output logic                       tl_valid_o,
  input  logic                       tl_ready_i,
  output logic [SLOT_BYTES*8-1:0]    tl_data_o,
  output logic [15:0]                tl_len_o,
  output logic [11:0]                tl_seq_o,

  output rivet_pkg::rivet_dllp_req_t ack_req_o,
  output logic                       ack_valid_o,
  input  logic                       ack_ready_i,

  output logic [11:0] last_good_seq_o,
  output logic        lcrc_err_o
);

  import rivet_pkg::*;

  localparam int unsigned DATA_W = SLOT_BYTES * 8;
  localparam int unsigned OFF_W  = (SLOT_BYTES <= 1) ? 1 : $clog2(SLOT_BYTES + 1);
  localparam int unsigned MIN_FR = RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES;
  localparam int unsigned CRC_W  = 160 * 8;

`ifndef SYNTHESIS
  initial begin
    if (SLOT_BYTES > 160)
      $error("rivet_dll_tlp_rx SLOT_BYTES must be <= 160 (LCRC helper width)");
  end
`endif

  logic [DATA_W-1:0] buf_q;
  logic [OFF_W-1:0]  len_q;

  logic [DATA_W-1:0] pld_q;
  logic [15:0]       pld_len_q;
  logic [11:0]       seq_q;
  logic              tl_pend_q;

  rivet_dllp_req_t   ack_q;
  logic              ack_pend_q;
  logic [11:0]       last_good_q;
  logic [11:0]       expect_q;
  logic              lcrc_err_q;

  assign last_good_seq_o = last_good_q;
  assign lcrc_err_o      = lcrc_err_q;
  assign tl_valid_o      = tl_pend_q;
  assign tl_data_o       = pld_q;
  assign tl_len_o        = pld_len_q;
  assign tl_seq_o        = seq_q;
  assign ack_valid_o     = ack_pend_q;
  assign ack_req_o       = ack_q;
  // ACK/NAK may sit pending while another TLP arrives; cumulative ACK/NAK
  // simply overwrites. Only TL delivery backpressure blocks RX.
  assign beat_ready_o    = enable_i && !tl_pend_q;

  function automatic logic [7:0] keep_popcount(input logic [7:0] k);
    return 8'(k[0]) + 8'(k[1]) + 8'(k[2]) + 8'(k[3]) +
           8'(k[4]) + 8'(k[5]) + 8'(k[6]) + 8'(k[7]);
  endfunction

  logic              take_beat;
  logic [7:0]        nbytes;
  logic [DATA_W-1:0] buf_next;
  logic [OFF_W-1:0]  len_next;
  logic [OFF_W-1:0]  wr_base;
  int unsigned       filled;

  assign take_beat = beat_valid_i && beat_ready_o &&
                     (beat_i.pkt_type == RIVET_MAC_PKT_TLP) && !beat_i.err;

  always_comb begin
    nbytes   = keep_popcount(beat_i.keep);
    buf_next = beat_i.sop ? '0 : buf_q;
    wr_base  = beat_i.sop ? '0 : len_q;
    filled   = 0;
    for (int unsigned i = 0; i < 8; i++) begin
      if (take_beat && beat_i.keep[i] &&
          (int'(wr_base) + filled < SLOT_BYTES)) begin
        buf_next[8*(int'(wr_base) + filled) +: 8] = beat_i.data[8*i +: 8];
        filled++;
      end
    end
    len_next = take_beat ? OFF_W'(int'(wr_base) + filled) : len_q;
  end

  logic        eop_take;
  logic [11:0] rx_seq;
  logic [15:0] pld_len;
  logic [31:0] lcrc_calc;
  logic [31:0] lcrc_wire;
  logic        lcrc_ok;
  logic        seq_ok;
  logic        seq_dup;
  logic [11:0] seq_delta;
  logic [CRC_W-1:0] crc_in;
  int unsigned      lcrc_base;

  assign eop_take = take_beat && beat_i.eop;

  always_comb begin
    rx_seq     = {buf_next[3:0], buf_next[15:8]};
    pld_len    = (int'(len_next) >= MIN_FR) ? 16'(int'(len_next) - MIN_FR) : 16'd0;
    lcrc_base  = int'(pld_len) + RIVET_TLP_SEQ_BYTES;
    lcrc_wire  = {
      buf_next[8*(lcrc_base + 3) +: 8],
      buf_next[8*(lcrc_base + 2) +: 8],
      buf_next[8*(lcrc_base + 1) +: 8],
      buf_next[8*(lcrc_base + 0) +: 8]
    };
    crc_in = '0;
    crc_in[DATA_W-1:0] = buf_next;
    lcrc_calc = rivet_lcrc32_calc(crc_in, lcrc_base);
    lcrc_ok   = (lcrc_calc == lcrc_wire) && (int'(len_next) >= MIN_FR);
    seq_ok    = (rx_seq == expect_q);
    seq_delta = expect_q - rx_seq;
    seq_dup   = lcrc_ok && !seq_ok && (seq_delta != 12'd0) && (seq_delta <= 12'd32);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      buf_q       <= '0;
      len_q       <= '0;
      pld_q       <= '0;
      pld_len_q   <= '0;
      seq_q       <= '0;
      tl_pend_q   <= 1'b0;
      ack_q       <= '0;
      ack_pend_q  <= 1'b0;
      last_good_q <= 12'hFFF;
      expect_q    <= 12'd0;
      lcrc_err_q  <= 1'b0;
    end else begin
      lcrc_err_q <= 1'b0;

      if (tl_pend_q && tl_ready_i) tl_pend_q <= 1'b0;
      if (ack_pend_q && ack_ready_i) ack_pend_q <= 1'b0;

      if (take_beat) begin
        buf_q <= buf_next;
        len_q <= len_next;
      end

      if (eop_take) begin
`ifndef SYNTHESIS
        $display("[%t] : TLP RX eop len=%0d seq=%03h expect=%03h lcrc_wire=%08h lcrc_calc=%08h ok=%0b seq_ok=%0b dup=%0b",
                 $realtime, int'(len_next), rx_seq, expect_q, lcrc_wire, lcrc_calc,
                 lcrc_ok, seq_ok, seq_dup);
`endif
        if (lcrc_ok && seq_ok) begin
          pld_q <= '0;
          for (int unsigned j = 0; j < SLOT_BYTES - MIN_FR; j++) begin
            if (16'(j) < pld_len)
              pld_q[8*j +: 8] <= buf_next[8*(j + RIVET_TLP_SEQ_BYTES) +: 8];
          end
          pld_len_q     <= pld_len;
          seq_q         <= rx_seq;
          tl_pend_q     <= 1'b1;
          last_good_q   <= rx_seq;
          expect_q      <= rx_seq + 12'd1;
          ack_q         <= '0;
          ack_q.kind    <= RIVET_DLLP_KIND_ACK;
          ack_q.ack_seq <= rx_seq;
          ack_pend_q    <= 1'b1;
        end else if (seq_dup) begin
          ack_q         <= '0;
          ack_q.kind    <= RIVET_DLLP_KIND_ACK;
          ack_q.ack_seq <= last_good_q;
          ack_pend_q    <= 1'b1;
        end else begin
          lcrc_err_q    <= !lcrc_ok;
          ack_q         <= '0;
          ack_q.kind    <= RIVET_DLLP_KIND_NAK;
          ack_q.ack_seq <= last_good_q;
          ack_pend_q    <= 1'b1;
        end
      end
    end
  end

endmodule : rivet_dll_tlp_rx
