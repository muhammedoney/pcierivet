// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Frame TL payload with Seq# + LCRC and emit MAC TLP beats. New traffic is
// pushed into the replay buffer; replay path re-emits stored framed images.

module rivet_dll_tlp_tx #(
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        enable_i,
  input  logic        replay_en_i,

  input  logic                       tl_valid_i,
  output logic                       tl_ready_o,
  input  logic [SLOT_BYTES*8-1:0]    tl_data_i,
  input  logic [15:0]                tl_len_i,

  input  logic                       replay_valid_i,
  output logic                       replay_ready_o,
  input  logic [11:0]                replay_seq_i,
  input  logic [SLOT_BYTES*8-1:0]    replay_data_i,
  input  logic [15:0]                replay_len_i,

  output logic                       push_valid_o,
  input  logic                       push_ready_i,
  output logic [11:0]                push_seq_o,
  output logic [SLOT_BYTES*8-1:0]    push_data_o,
  output logic [15:0]                push_len_o,

  output rivet_pkg::rivet_dll_mac_tx_beat_t beat_o,
  output logic                              beat_valid_o,
  input  logic                              beat_ready_i,

  output logic [11:0] next_tx_seq_o
);

  import rivet_pkg::*;

  localparam int unsigned DATA_W  = SLOT_BYTES * 8;
  localparam int unsigned MAX_PLD = SLOT_BYTES - RIVET_TLP_SEQ_BYTES - RIVET_TLP_LCRC_BYTES;
  localparam int unsigned OFF_W   = (SLOT_BYTES <= 1) ? 1 : $clog2(SLOT_BYTES + 1);
  localparam int unsigned CRC_W   = 160 * 8;

`ifndef SYNTHESIS
  initial begin
    if (SLOT_BYTES > 160)
      $error("rivet_dll_tlp_tx SLOT_BYTES must be <= 160 (LCRC helper width)");
  end
`endif

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_PUSH = 2'd1,
    ST_EMIT = 2'd2
  } state_e;

  state_e state_q;
  logic [DATA_W-1:0] frame_q;
  logic [15:0]       frame_len_q;
  logic [11:0]       seq_q;
  logic [OFF_W-1:0]  off_q;
  logic [11:0]       next_seq_q;

  function automatic logic [DATA_W-1:0] build_frame(
      input logic [11:0]       seq,
      input logic [DATA_W-1:0] pld,
      input logic [15:0]       pld_len);
    logic [DATA_W-1:0] bytes;
    logic [CRC_W-1:0]  crc_in;
    logic [15:0]       seq_w;
    logic [31:0]       lcrc;
    int unsigned       i;
    int unsigned       base;
    bytes  = '0;
    seq_w  = rivet_tlp_seq_bytes(seq);
    bytes[7:0]  = seq_w[7:0];
    bytes[15:8] = seq_w[15:8];
    for (i = 0; i < MAX_PLD; i++) begin
      if (16'(i) < pld_len)
        bytes[8*(i+RIVET_TLP_SEQ_BYTES) +: 8] = pld[8*i +: 8];
    end
    crc_in = '0;
    crc_in[DATA_W-1:0] = bytes;
    lcrc = rivet_lcrc32_calc(crc_in, int'(pld_len) + RIVET_TLP_SEQ_BYTES);
    base = int'(pld_len) + RIVET_TLP_SEQ_BYTES;
    bytes[8*(base+0) +: 8] = lcrc[7:0];
    bytes[8*(base+1) +: 8] = lcrc[15:8];
    bytes[8*(base+2) +: 8] = lcrc[23:16];
    bytes[8*(base+3) +: 8] = lcrc[31:24];
    return bytes;
  endfunction

  assign next_tx_seq_o = next_seq_q;
  assign tl_ready_o = enable_i && (state_q == ST_IDLE) && !replay_en_i &&
                      (tl_len_i != 16'd0) && (tl_len_i <= MAX_PLD[15:0]);
  assign replay_ready_o = replay_en_i && (state_q == ST_IDLE);
  assign push_valid_o = (state_q == ST_PUSH);
  assign push_seq_o   = seq_q;
  assign push_data_o  = frame_q;
  assign push_len_o   = frame_len_q;

  logic [15:0] remain;
  logic [7:0]  beat_bytes;
  logic [7:0]  keep_bits;

  always_comb begin
    remain = (frame_len_q > 16'(off_q)) ? (frame_len_q - 16'(off_q)) : 16'd0;
    beat_bytes = (remain >= 16'd8) ? 8'd8 : remain[7:0];
    keep_bits = 8'h00;
    for (int unsigned ki = 0; ki < 8; ki++)
      if (ki < beat_bytes) keep_bits[ki] = 1'b1;
  end

  assign beat_valid_o = (state_q == ST_EMIT);
  always_comb begin
    beat_o = '0;
    beat_o.pkt_type = RIVET_MAC_PKT_TLP;
    beat_o.sop      = (off_q == '0);
    beat_o.eop      = (remain <= 16'd8);
    beat_o.keep     = keep_bits;
    for (int unsigned ki = 0; ki < 8; ki++) begin
      if (ki < beat_bytes)
        beat_o.data[8*ki +: 8] = frame_q[8*(off_q + OFF_W'(ki)) +: 8];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= ST_IDLE;
      frame_q     <= '0;
      frame_len_q <= '0;
      seq_q       <= '0;
      off_q       <= '0;
      next_seq_q  <= 12'd0;
    end else begin
      unique case (state_q)
        ST_IDLE: begin
          off_q <= '0;
          if (replay_en_i && replay_valid_i && replay_ready_o) begin
            frame_q     <= replay_data_i;
            frame_len_q <= replay_len_i;
            seq_q       <= replay_seq_i;
            state_q     <= ST_EMIT;
          end else if (enable_i && tl_valid_i && tl_ready_o) begin
            frame_q     <= build_frame(next_seq_q, tl_data_i, tl_len_i);
            frame_len_q <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES);
            seq_q       <= next_seq_q;
            next_seq_q  <= next_seq_q + 12'd1;
            state_q     <= ST_PUSH;
          end
        end
        ST_PUSH: begin
          if (push_ready_i) state_q <= ST_EMIT;
        end
        ST_EMIT: begin
          if (beat_valid_o && beat_ready_i) begin
            if (beat_o.eop) state_q <= ST_IDLE;
            else off_q <= off_q + OFF_W'(beat_bytes);
          end
        end
        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_dll_tlp_tx
