// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Frame TL payload with Seq# + LCRC and emit MAC TLP beats. New traffic is
// pushed into the replay buffer; replay path re-emits stored framed images.
//
// LCRC is an 8-byte parallel fold (rivet_crc32_fold), one chunk per cycle,
// into a dedicated 32-bit register; ST_LCRC inserts the registered LCRC in
// its own cycle so the CRC XOR tree never chains into the 160-byte frame mux.
// Emit tracks remaining bytes / keep / EOP in registers so beat_o is pure
// wiring off frame_q[63:0].

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

  output logic                              idle_o,
  output logic [11:0] next_tx_seq_o
);

  import rivet_pkg::*;

  localparam int unsigned DATA_W  = SLOT_BYTES * 8;
  localparam int unsigned MAX_PLD = SLOT_BYTES - RIVET_TLP_SEQ_BYTES - RIVET_TLP_LCRC_BYTES;
  localparam int unsigned BEAT_B  = 8;

`ifndef SYNTHESIS
  initial begin
    if (SLOT_BYTES < BEAT_B)
      $error("rivet_dll_tlp_tx SLOT_BYTES must be >= %0d", BEAT_B);
  end
`endif

  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_CRC  = 3'd1,
    ST_LCRC = 3'd2,
    ST_PUSH = 3'd3,
    ST_EMIT = 3'd4
  } state_e;

  state_e            state_q;
  logic [DATA_W-1:0] frame_q;
  logic [DATA_W-1:0] crc_sh_q;
  logic [15:0]       frame_len_q;
  logic [15:0]       crc_left_q;
  logic [15:0]       lcrc_idx0_q, lcrc_idx1_q, lcrc_idx2_q, lcrc_idx3_q;
  logic [31:0]       crc_q;
  logic [11:0]       seq_q;
  logic [11:0]       next_seq_q;

  logic [15:0]       rem_q;
  logic              emit_sop_q;
  logic              emit_eop_q;
  logic [7:0]        emit_keep_q;

  function automatic logic [7:0] len_to_keep8(input logic [15:0] rem);
    if (rem >= 9'd8) return 8'hFF;
    unique case (rem[2:0])
      3'd0: return 8'h00;
      3'd1: return 8'h01;
      3'd2: return 8'h03;
      3'd3: return 8'h07;
      3'd4: return 8'h0F;
      3'd5: return 8'h1F;
      3'd6: return 8'h3F;
      3'd7: return 8'h7F;
    endcase
  endfunction

  function automatic logic [DATA_W-1:0] build_bytes(
      input logic [11:0]       seq,
      input logic [DATA_W-1:0] pld);
    logic [DATA_W-1:0] bytes;
    logic [15:0]       seq_w;
    bytes       = '0;
    seq_w       = rivet_tlp_seq_bytes(seq);
    bytes[7:0]  = seq_w[7:0];
    bytes[15:8] = seq_w[15:8];
    bytes[8*RIVET_TLP_SEQ_BYTES +: 8*MAX_PLD] = pld[8*MAX_PLD-1:0];
    return bytes;
  endfunction

  function automatic logic [DATA_W-1:0] insert_lcrc(
      input logic [DATA_W-1:0] bytes,
      input logic [15:0]       idx0,
      input logic [15:0]       idx1,
      input logic [15:0]       idx2,
      input logic [15:0]       idx3,
      input logic [31:0]       lcrc);
    logic [DATA_W-1:0] b;
    b = bytes;
    for (int unsigned i = 0; i < SLOT_BYTES; i++) begin
      if (16'(i) == idx0)
        b[8*i +: 8] = lcrc[7:0];
      else if (16'(i) == idx1)
        b[8*i +: 8] = lcrc[15:8];
      else if (16'(i) == idx2)
        b[8*i +: 8] = lcrc[23:16];
      else if (16'(i) == idx3)
        b[8*i +: 8] = lcrc[31:24];
    end
    return b;
  endfunction

  logic [DATA_W-1:0] built_bytes;
  logic [3:0]        crc_n;
  logic [31:0]       crc_nxt;
  logic              crc_last;

  assign built_bytes = build_bytes(next_seq_q, tl_data_i);

  assign crc_n    = (crc_left_q <= 16'(BEAT_B)) ? crc_left_q[3:0] : 4'(BEAT_B);
  assign crc_nxt  = rivet_crc32_fold(crc_q, crc_sh_q[BEAT_B*8-1:0], crc_n);
  assign crc_last = (crc_left_q != 16'd0) && (crc_left_q <= 16'(BEAT_B));

  assign idle_o         = (state_q == ST_IDLE);
  assign next_tx_seq_o  = next_seq_q;
  // A frame is accepted only when a replay slot is free. Replay is held off
  // until this machine is idle, so a full buffer can drain instead of sitting
  // in ST_PUSH behind replay_active.
  assign tl_ready_o     = enable_i && (state_q == ST_IDLE) && !replay_en_i &&
                          push_ready_i &&
                          (tl_len_i != 16'd0) && (tl_len_i <= MAX_PLD[15:0]);
  assign replay_ready_o = replay_en_i && (state_q == ST_IDLE);
  assign push_valid_o   = (state_q == ST_PUSH);
  assign push_seq_o     = seq_q;
  assign push_data_o    = frame_q;
  assign push_len_o     = frame_len_q;

  assign beat_valid_o = (state_q == ST_EMIT);
  always_comb begin
    beat_o          = '0;
    beat_o.pkt_type = RIVET_MAC_PKT_TLP;
    beat_o.sop      = emit_sop_q;
    beat_o.eop      = emit_eop_q;
    beat_o.keep     = emit_keep_q;
    for (int unsigned ki = 0; ki < BEAT_B; ki++) begin
      if (emit_keep_q[ki])
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
      lcrc_idx0_q <= '0;
      lcrc_idx1_q <= '0;
      lcrc_idx2_q <= '0;
      lcrc_idx3_q <= '0;
      crc_q       <= 32'hFFFF_FFFF;
      seq_q       <= '0;
      next_seq_q  <= 12'd0;
      rem_q       <= '0;
      emit_sop_q  <= 1'b0;
      emit_eop_q  <= 1'b0;
      emit_keep_q <= '0;
    end else begin
      unique case (state_q)
        ST_IDLE: begin
          if (replay_en_i && replay_valid_i && replay_ready_o) begin
            automatic logic [15:0] rlen = replay_len_i;
            frame_q     <= replay_data_i;
            frame_len_q <= replay_len_i;
            seq_q       <= replay_seq_i;
            rem_q       <= rlen;
            emit_sop_q  <= 1'b1;
            emit_eop_q  <= (rlen <= 9'(BEAT_B));
            emit_keep_q <= len_to_keep8(rlen);
            state_q     <= ST_EMIT;
          end else if (enable_i && tl_valid_i && tl_ready_o) begin
            automatic logic [15:0] base8 = tl_len_i + 16'(RIVET_TLP_SEQ_BYTES);
            frame_q     <= built_bytes;
            crc_sh_q    <= built_bytes;
            frame_len_q <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES + RIVET_TLP_LCRC_BYTES);
            crc_left_q  <= tl_len_i + 16'(RIVET_TLP_SEQ_BYTES);
            lcrc_idx0_q <= base8;
            lcrc_idx1_q <= base8 + 8'd1;
            lcrc_idx2_q <= base8 + 8'd2;
            lcrc_idx3_q <= base8 + 8'd3;
            crc_q       <= 32'hFFFF_FFFF;
            seq_q       <= next_seq_q;
            next_seq_q  <= next_seq_q + 12'd1;
            state_q     <= ST_CRC;
          end
        end
        ST_CRC: begin
          if (crc_last) begin
            crc_q   <= ~crc_nxt;
            state_q <= ST_LCRC;
          end else begin
            crc_q      <= crc_nxt;
            crc_sh_q   <= crc_sh_q >> (BEAT_B * 8);
            crc_left_q <= crc_left_q - 16'(BEAT_B);
          end
        end
        ST_LCRC: begin
          frame_q <= insert_lcrc(frame_q, lcrc_idx0_q, lcrc_idx1_q,
                                 lcrc_idx2_q, lcrc_idx3_q, crc_q);
          state_q <= ST_PUSH;
        end
        ST_PUSH: begin
          if (push_ready_i) begin
            automatic logic [15:0] flen = frame_len_q;
            rem_q       <= flen;
            emit_sop_q  <= 1'b1;
            emit_eop_q  <= (flen <= 9'(BEAT_B));
            emit_keep_q <= len_to_keep8(flen);
            state_q     <= ST_EMIT;
          end
        end
        ST_EMIT: begin
          if (beat_valid_o && beat_ready_i) begin
            if (emit_eop_q) begin
              state_q <= ST_IDLE;
            end else begin
              automatic logic [15:0] nrem = rem_q - 16'(BEAT_B);
              rem_q       <= nrem;
              emit_sop_q  <= 1'b0;
              emit_eop_q  <= (nrem <= 9'(BEAT_B));
              emit_keep_q <= len_to_keep8(nrem);
              frame_q     <= frame_q >> (BEAT_B * 8);
            end
          end
        end
        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_dll_tlp_tx
