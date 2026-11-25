// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Replay buffer. Frame bytes are stored as 64-bit words, one write per
// cycle, so the retry image is not a SLOT_BYTES-wide vector on pclk.
// A cumulative ACK retires one head slot per cycle.

module rivet_dll_replay #(
  parameter int unsigned TLP_SLOTS  = 16,
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        clear_i,

  input  logic        cap_valid_i,
  output logic        cap_ready_o,
  input  logic [63:0] cap_data_i,
  input  logic        cap_last_i,
  // Second word of a 16-byte capture. Stays low on the 8-byte path.
  input  logic        cap_hi_valid_i = 1'b0,
  input  logic [63:0] cap_hi_data_i  = '0,
  // Words 2 and 3 of a 32-byte capture. Idle unless cap_ex_valid_i.
  input  logic        cap_ex_valid_i = 1'b0,
  input  logic [63:0] cap_ex0_i      = '0,
  input  logic [63:0] cap_ex1_i      = '0,
  input  logic [11:0] cap_seq_i,
  input  logic [15:0] cap_len_i,

  input  logic        ack_valid_i,
  input  logic [11:0] ack_seq_i,

  input  logic                       replay_start_i,
  output logic                       replay_active_o,
  output logic                       replay_done_o,
  output logic                       replay_valid_o,
  input  logic                       replay_ready_i,
  output logic [11:0]                replay_seq_o,
  input  logic [15:0]                replay_word_idx_i,
  output logic [63:0]                replay_word_o,
  output logic [15:0]                replay_len_o,

  output logic        full_o,
  output logic        empty_o,
  output logic [15:0] occupancy_o
);

  localparam int unsigned IDX_W  = (TLP_SLOTS <= 1) ? 1 : $clog2(TLP_SLOTS);
  localparam int unsigned WORDS  = SLOT_BYTES / 8;
  localparam int unsigned WORD_W = (WORDS <= 1) ? 1 : $clog2(WORDS);
  // Power-of-two word stride so the RAM address is a concatenation.
  localparam int unsigned RAM_WORDS = TLP_SLOTS * (1 << WORD_W);

  logic        valid_q [TLP_SLOTS];
  logic [11:0] seq_q   [TLP_SLOTS];
  logic [15:0] len_q   [TLP_SLOTS];
  logic        filling_q;

  function automatic bit seq_acked(input logic [11:0] a, input logic [11:0] s);
    return ((s - a) < 12'd2048);
  endfunction

  logic [IDX_W-1:0]  wr_q, rd_q, replay_idx_q;
  logic [WORD_W-1:0] wr_word_q;
  logic [15:0]       count_q;
  logic              replay_active_q;
  logic              replay_done_q;
  logic              replay_valid_q;
  logic              ack_hold_q;
  logic [11:0]       ack_seq_q;
  logic [63:0]       word_rdata [4];
  localparam int unsigned RAM_AW = $clog2(RAM_WORDS);
  logic [RAM_AW-1:0] word_waddr [4];
  logic [RAM_AW-1:0] word_raddr [4];

  logic [11:0]      ack_seq_eff;
  logic             ack_live;
  logic             head_ack;
  logic [IDX_W-1:0] rd_next;
  logic             cap_fire;

  assign ack_seq_eff = ack_valid_i ? ack_seq_i : ack_seq_q;
  assign ack_live    = ack_valid_i || ack_hold_q;
  assign rd_next     = rd_q + 1'b1;
  assign head_ack    = ack_live && (count_q != 16'd0) && valid_q[rd_q] &&
                       seq_acked(seq_q[rd_q], ack_seq_eff);

  assign full_o      = (count_q == TLP_SLOTS[15:0]);
  assign empty_o     = (count_q == 16'd0);
  assign occupancy_o = count_q;
  assign cap_ready_o = !replay_active_q && (filling_q || !full_o);
  assign cap_fire    = cap_valid_i && cap_ready_o;

  assign replay_active_o = replay_active_q;
  assign replay_done_o   = replay_done_q;
  assign replay_valid_o  = replay_valid_q;
  assign replay_seq_o    = seq_q[replay_idx_q];
  assign replay_len_o    = len_q[replay_idx_q];
  assign replay_word_o   = word_rdata[0];

  assign word_waddr[0] = {wr_q, wr_word_q};
  assign word_waddr[1] = {wr_q, WORD_W'(wr_word_q + 1'b1)};
  assign word_waddr[2] = {wr_q, WORD_W'(wr_word_q + 2'd2)};
  assign word_waddr[3] = {wr_q, WORD_W'(wr_word_q + 2'd3)};
  assign word_raddr[0] = {replay_idx_q, replay_word_idx_i[WORD_W-1:0]};
  assign word_raddr[1] = word_raddr[0];
  assign word_raddr[2] = word_raddr[0];
  assign word_raddr[3] = word_raddr[0];

  rivet_ram_lane4 #(.DEPTH(RAM_WORDS)) u_word (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .we_i    ({cap_fire && cap_ex_valid_i, cap_fire && cap_ex_valid_i,
               cap_fire && cap_hi_valid_i, cap_fire}),
    .waddr_i (word_waddr),
    .wdata_i ('{cap_data_i, cap_hi_data_i, cap_ex0_i, cap_ex1_i}),
    .re_i    (1'b1),
    .raddr_i (word_raddr),
    .rdata_o (word_rdata)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_q            <= '0;
      wr_word_q       <= '0;
      rd_q            <= '0;
      count_q         <= '0;
      replay_idx_q    <= '0;
      replay_active_q <= 1'b0;
      replay_done_q   <= 1'b0;
      replay_valid_q  <= 1'b0;
      ack_hold_q      <= 1'b0;
      ack_seq_q       <= '0;
      filling_q       <= 1'b0;
      for (int unsigned i = 0; i < TLP_SLOTS; i++) begin
        valid_q[i] <= 1'b0;
        seq_q[i]   <= '0;
        len_q[i]   <= '0;
      end
    end else if (clear_i) begin
      wr_q            <= '0;
      wr_word_q       <= '0;
      rd_q            <= '0;
      count_q         <= '0;
      replay_idx_q    <= '0;
      replay_active_q <= 1'b0;
      replay_done_q   <= 1'b0;
      replay_valid_q  <= 1'b0;
      ack_hold_q      <= 1'b0;
      ack_seq_q       <= '0;
      filling_q       <= 1'b0;
      for (int unsigned i = 0; i < TLP_SLOTS; i++) valid_q[i] <= 1'b0;
    end else begin
      logic             ack_hold_d;
      logic [11:0]      ack_seq_d;
      logic             purge_d;
      replay_done_q <= 1'b0;
      ack_hold_d = ack_hold_q;
      ack_seq_d  = ack_seq_q;
      if (ack_valid_i) begin
        ack_hold_d = 1'b1;
        ack_seq_d  = ack_seq_i;
      end
      purge_d = head_ack && !(cap_fire && cap_last_i);

      if (cap_fire && cap_last_i) begin
        valid_q[wr_q] <= 1'b1;
        seq_q[wr_q]   <= cap_seq_i;
        len_q[wr_q]   <= cap_len_i;
        wr_q          <= wr_q + 1'b1;
        wr_word_q     <= '0;
        filling_q     <= 1'b0;
        if (!filling_q)
          count_q <= count_q + 16'd1;
      end else if (cap_fire) begin
        wr_word_q <= wr_word_q + (cap_ex_valid_i ? WORD_W'(4) :
                                  cap_hi_valid_i ? WORD_W'(2) : WORD_W'(1));
        if (!filling_q) begin
          filling_q <= 1'b1;
          count_q   <= count_q + 16'd1;
        end
      end else if (purge_d) begin
        valid_q[rd_q] <= 1'b0;
        rd_q          <= rd_next;
        count_q       <= count_q - 16'd1;
        if ((count_q == 16'd1) || !valid_q[rd_next] ||
            !seq_acked(seq_q[rd_next], ack_seq_eff))
          ack_hold_d = 1'b0;
      end else if (!head_ack) begin
        ack_hold_d = 1'b0;
      end
      ack_hold_q <= ack_hold_d;
      ack_seq_q  <= ack_seq_d;

      if (replay_active_q && (count_q == 16'd0)) begin
        replay_active_q <= 1'b0;
        replay_done_q   <= 1'b1;
        replay_valid_q  <= 1'b0;
      end else if (replay_start_i && !replay_active_q && (count_q != 16'd0) && !head_ack) begin
        replay_active_q <= 1'b1;
        replay_idx_q    <= rd_q;
        replay_valid_q  <= 1'b0;
      end else if (replay_active_q && (!replay_valid_q || !valid_q[replay_idx_q])) begin
        if (!valid_q[replay_idx_q]) begin
          if ((replay_idx_q + 1'b1) == wr_q) begin
            replay_active_q <= 1'b0;
            replay_done_q   <= 1'b1;
          end else begin
            replay_idx_q <= replay_idx_q + 1'b1;
          end
          replay_valid_q <= 1'b0;
        end else begin
          replay_valid_q <= 1'b1;
        end
      end else if (replay_active_q && replay_valid_q && replay_ready_i) begin
        replay_valid_q <= 1'b0;
        if ((replay_idx_q + 1'b1) == wr_q) begin
          replay_active_q <= 1'b0;
          replay_done_q   <= 1'b1;
        end else begin
          replay_idx_q <= replay_idx_q + 1'b1;
        end
      end
    end
  end

endmodule : rivet_dll_replay
