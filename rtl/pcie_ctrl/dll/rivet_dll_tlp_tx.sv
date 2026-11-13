// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Frame TL payload with Seq# + LCRC and emit MAC TLP beats. New traffic is
// pushed into the replay buffer; replay path re-emits stored framed images.
//
// LCRC is an 8-byte parallel fold (rivet_crc32_fold), one chunk per cycle,
// over the latched Seq# + payload. A single-cycle serial LFSR over the whole
// frame does not close at Gen2 pclk. Emit shifts the frame by one beat so the
// MAC sees frame[63:0] instead of a 160-byte barrel mux.

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
  localparam int unsigned BEAT_B  = 8;

`ifndef SYNTHESIS
  initial begin
    if (SLOT_BYTES < BEAT_B)
      $error("rivet_dll_tlp_tx SLOT_BYTES must be >= %0d", BEAT_B);
  end
`endif

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_CRC  = 2'd1,
    ST_PUSH = 2'd2,
    ST_EMIT = 2'd3
  } state_e;

  state_e state_q;
  logic [DATA_W-1:0] frame_q;
  logic [DATA_W-1:0] crc_sh_q;
  logic [15:0]       frame_len_q;
  logic [15:0]       crc_left_q;
  logic [15:0]       crc_base_q;
  logic [31:0]       crc_q;
  logic [11:0]       seq_q;
  logic [OFF_W-1:0]  off_q;
  logic [11:0]       next_seq_q;

  function automatic logic [DATA_W-1:0] build_bytes(
      input logic [11:0]       seq,
      input logic [DATA_W-1:0] pld,
      input logic [15:0]       pld_len);
    logic [DATA_W-1:0] bytes;
    logic [15:0]       seq_w;
    int unsigned       i;
    bytes  = '0;
    seq_w  = rivet_tlp_seq_bytes(seq);
    bytes[7:0]  = seq_w[7:0];
    bytes[15:8] = seq_w[15:8];
    for (i = 0; i < MAX_PLD; i++) begin
      if (16'(i) < pld_len)
        bytes[8*(i + RIVET_TLP_SEQ_BYTES) +: 8] = pld[8*i +: 8];
    end
    return bytes;
  endfunction

  // Per-byte compare, so the LCRC insert is a mux and not a wide barrel shift.
  function automatic logic [DATA_W-1:0] insert_lcrc(
      input logic [DATA_W-1:0] bytes,
      input logic [15:0]       base,
      input logic [31:0]       lcrc);
    logic [DATA_W-1:0] b;
    int unsigned       i;
    b = bytes;
    for (i = 0; i < SLOT_BYTES; i++) begin
      if (16'(i) == base)
        b[8*i +: 8] = lcrc[7:0];
      else if (16'(i) == (base + 16'd1))
        b[8*i +: 8] = lcrc[15:8];
      else if (16'(i) == (base + 16'd2))
        b[8*i +: 8] = lcrc[23:16];
      else if (16'(i) == (base + 16'd3))
        b[8*i +: 8] = lcrc[31:24];
    end
    return b;
  endfunction

  logic [DATA_W-1:0] built_bytes;
  logic [3:0]  crc_n;
  logic [31:0] crc_nxt;
  logic [31:0] crc_wire;
  logic        crc_last;

  assign built_bytes = build_bytes(next_seq_q, tl_data_i, tl_len_i);

  assign crc_n    = (crc_left_q <= 16'(BEAT_B)) ? crc_left_q[3:0] : 4'(BEAT_B);
  assign crc_nxt  = rivet_crc32_fold(crc_q, crc_sh_q[BEAT_B*8-1:0], crc_n);
  assign crc_wire = ~crc_nxt;
  assign crc_last = (crc_left_q != 16'd0) && (crc_left_q <= 16'(BEAT_B));

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
    beat_bytes = (remain >= 16'(BEAT_B)) ? 8'(BEAT_B) : remain[7:0];
    keep_bits = 8'h00;
    for (int unsigned ki = 0; ki < BEAT_B; ki++)
      if (ki < beat_bytes) keep_bits[ki] = 1'b1;
  end

  assign beat_valid_o = (state_q == ST_EMIT);
  always_comb begin
    beat_o = '0;
    beat_o.pkt_type = RIVET_MAC_PKT_TLP;
    beat_o.sop      = (off_q == '0);
    beat_o.eop      = (remain <= 16'(BEAT_B));
    beat_o.keep     = keep_bits;
    for (int unsigned ki = 0; ki < BEAT_B; ki++) begin
      if (ki < beat_bytes)
        beat_o.data[8*ki +: 8] = frame_q[8*ki +: 8];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= ST_IDLE;
      frame_q     <= '0;
      crc_sh_q    <= '0;
      frame_len_q <= '0;
      crc_left_q  <= '0;
      crc_base_q  <= '0;
      crc_q       <= 32'hFFFF_FFFF;
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
            frame_q     <= built_bytes;
            crc_sh_q    <= built_bytes;
            frame_len_q <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES);
            crc_left_q  <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES);
            crc_base_q  <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES);
            crc_q       <= 32'hFFFF_FFFF;
            seq_q       <= next_seq_q;
            next_seq_q  <= next_seq_q + 12'd1;
            state_q     <= ST_CRC;
          end
        end
        ST_CRC: begin
          if (crc_last) begin
            frame_q <= insert_lcrc(frame_q, crc_base_q, crc_wire);
            state_q <= ST_PUSH;
          end else begin
            crc_q      <= crc_nxt;
            crc_sh_q   <= crc_sh_q >> (BEAT_B * 8);
            crc_left_q <= crc_left_q - 16'(BEAT_B);
          end
        end
        ST_PUSH: begin
          if (push_ready_i) state_q <= ST_EMIT;
        end
        ST_EMIT: begin
          if (beat_valid_o && beat_ready_i) begin
            if (beat_o.eop) state_q <= ST_IDLE;
            else begin
              off_q   <= off_q + OFF_W'(BEAT_B);
              frame_q <= frame_q >> (BEAT_B * 8);
            end
          end
        end
        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_dll_tlp_tx
