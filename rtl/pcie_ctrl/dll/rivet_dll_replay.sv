// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Replay (retry) buffer: store TX TLP images until ACK; retransmit on NAK.
// Payload stored as a packed vector per slot for tool friendliness.
//
// A cumulative ACK retires one head slot per cycle. Retiring every slot in
// one cycle is a TLP_SLOTS-deep dependent chain on pclk.

module rivet_dll_replay #(
  parameter int unsigned TLP_SLOTS  = 16,
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        clear_i,

  input  logic                       push_valid_i,
  output logic                       push_ready_o,
  input  logic [11:0]                push_seq_i,
  input  logic [SLOT_BYTES*8-1:0]    push_data_i,
  input  logic [15:0]                push_len_i,

  input  logic        ack_valid_i,
  input  logic [11:0] ack_seq_i,

  input  logic                       replay_start_i,
  output logic                       replay_active_o,
  output logic                       replay_done_o,
  output logic                       replay_valid_o,
  input  logic                       replay_ready_i,
  output logic [11:0]                replay_seq_o,
  output logic [SLOT_BYTES*8-1:0]    replay_data_o,
  output logic [15:0]                replay_len_o,

  output logic        full_o,
  output logic        empty_o,
  output logic [15:0] occupancy_o
);

  localparam int unsigned IDX_W = (TLP_SLOTS <= 1) ? 1 : $clog2(TLP_SLOTS);
  localparam int unsigned DATA_W = SLOT_BYTES * 8;

  logic        valid_q [TLP_SLOTS];
  logic [11:0] seq_q   [TLP_SLOTS];
  logic [15:0] len_q   [TLP_SLOTS];
  // One slot is 1280 bits. A flip-flop array with a combo read does not
  // close at Gen2 pclk. The read data is the slot addressed last cycle,
  // and replay_valid_o is held off for that fetch cycle.
  (* ram_style = "block" *) logic [DATA_W-1:0] data_q [0:TLP_SLOTS-1];
  logic [DATA_W-1:0] replay_data_q;
  logic              replay_valid_q;

  function automatic bit seq_acked(input logic [11:0] a, input logic [11:0] s);
    return ((s - a) < 12'd2048);
  endfunction

  logic [IDX_W-1:0] wr_q, rd_q, replay_idx_q;
  logic [15:0]      count_q;
  logic             replay_active_q;
  logic             replay_done_q;
  logic             ack_hold_q;
  logic [11:0]      ack_seq_q;

  logic [11:0]      ack_seq_eff;
  logic             ack_live;
  logic             head_ack;
  logic [IDX_W-1:0] rd_next;

  assign ack_seq_eff = ack_valid_i ? ack_seq_i : ack_seq_q;
  assign ack_live    = ack_valid_i || ack_hold_q;
  assign rd_next     = rd_q + 1'b1;
  assign head_ack    = ack_live && (count_q != 16'd0) && valid_q[rd_q] &&
                       seq_acked(seq_q[rd_q], ack_seq_eff);

  assign full_o      = (count_q == TLP_SLOTS[15:0]);
  assign empty_o     = (count_q == 16'd0);
  assign occupancy_o = count_q;
  assign push_ready_o = !full_o && !replay_active_q;

  assign replay_active_o = replay_active_q;
  assign replay_done_o   = replay_done_q;
  assign replay_valid_o  = replay_valid_q;
  assign replay_seq_o    = seq_q[replay_idx_q];
  assign replay_len_o    = len_q[replay_idx_q];
  assign replay_data_o   = replay_data_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni)
      replay_data_q <= '0;
    else
      replay_data_q <= data_q[replay_idx_q];
    if (rst_ni && !clear_i && push_valid_i && push_ready_o)
      data_q[wr_q] <= push_data_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_q            <= '0;
      rd_q            <= '0;
      count_q         <= '0;
      replay_idx_q    <= '0;
      replay_active_q <= 1'b0;
      replay_done_q   <= 1'b0;
      replay_valid_q  <= 1'b0;
      ack_hold_q      <= 1'b0;
      ack_seq_q       <= '0;
      for (int unsigned i = 0; i < TLP_SLOTS; i++) begin
        valid_q[i] <= 1'b0;
        seq_q[i]   <= '0;
        len_q[i]   <= '0;
      end
    end else if (clear_i) begin
      wr_q            <= '0;
      rd_q            <= '0;
      count_q         <= '0;
      replay_idx_q    <= '0;
      replay_active_q <= 1'b0;
      replay_done_q   <= 1'b0;
      replay_valid_q  <= 1'b0;
      ack_hold_q      <= 1'b0;
      ack_seq_q       <= '0;
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
      // A same-cycle push keeps the latched ACK and retires on a later cycle.
      purge_d = head_ack && !(push_valid_i && push_ready_o);

      if (push_valid_i && push_ready_o) begin
        valid_q[wr_q] <= 1'b1;
        seq_q[wr_q]   <= push_seq_i;
        len_q[wr_q]   <= push_len_i;
        wr_q          <= wr_q + 1'b1;
        count_q       <= count_q + 16'd1;
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
        // ACKs retired every slot before the walk finished. A cleared
        // valid bit must not leave replay_active stuck.
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
