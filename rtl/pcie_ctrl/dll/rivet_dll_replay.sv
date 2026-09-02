// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Replay (retry) buffer: store TX TLP images until ACK; retransmit on NAK.
// Payload stored as a packed vector per slot for tool friendliness.

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
  logic [DATA_W-1:0] data_q [TLP_SLOTS];

  logic [IDX_W-1:0] wr_q, rd_q, replay_idx_q;
  logic [15:0]      count_q;
  logic             replay_active_q;
  logic             replay_done_q;

  function automatic bit seq_acked(input logic [11:0] a, input logic [11:0] s);
    return ((s - a) < 12'd2048);
  endfunction

  assign full_o      = (count_q == TLP_SLOTS[15:0]);
  assign empty_o     = (count_q == 16'd0);
  assign occupancy_o = count_q;
  assign push_ready_o = !full_o && !replay_active_q;

  assign replay_active_o = replay_active_q;
  assign replay_done_o   = replay_done_q;
  assign replay_valid_o  = replay_active_q && valid_q[replay_idx_q];
  assign replay_seq_o    = seq_q[replay_idx_q];
  assign replay_len_o    = len_q[replay_idx_q];
  assign replay_data_o   = data_q[replay_idx_q];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_q            <= '0;
      rd_q            <= '0;
      count_q         <= '0;
      replay_idx_q    <= '0;
      replay_active_q <= 1'b0;
      replay_done_q   <= 1'b0;
      for (int unsigned i = 0; i < TLP_SLOTS; i++) begin
        valid_q[i] <= 1'b0;
        seq_q[i]   <= '0;
        len_q[i]   <= '0;
        data_q[i]  <= '0;
      end
    end else if (clear_i) begin
      wr_q            <= '0;
      rd_q            <= '0;
      count_q         <= '0;
      replay_idx_q    <= '0;
      replay_active_q <= 1'b0;
      replay_done_q   <= 1'b0;
      for (int unsigned i = 0; i < TLP_SLOTS; i++) valid_q[i] <= 1'b0;
    end else begin
      replay_done_q <= 1'b0;

      if (push_valid_i && push_ready_o) begin
        valid_q[wr_q] <= 1'b1;
        seq_q[wr_q]   <= push_seq_i;
        len_q[wr_q]   <= push_len_i;
        data_q[wr_q]  <= push_data_i;
        wr_q          <= wr_q + 1'b1;
        count_q       <= count_q + 16'd1;
      end else if (ack_valid_i && (count_q != 16'd0)) begin
        // Purge all consecutive head slots covered by this ACK in one cycle.
        begin
          logic [IDX_W-1:0] rd_tmp;
          logic [15:0]      cnt_tmp;
          rd_tmp  = rd_q;
          cnt_tmp = count_q;
          for (int unsigned pi = 0; pi < TLP_SLOTS; pi++) begin
            if ((cnt_tmp != 16'd0) && valid_q[rd_tmp] &&
                seq_acked(seq_q[rd_tmp], ack_seq_i)) begin
              valid_q[rd_tmp] <= 1'b0;
              rd_tmp  = rd_tmp + 1'b1;
              cnt_tmp = cnt_tmp - 16'd1;
            end
          end
          rd_q    <= rd_tmp;
          count_q <= cnt_tmp;
        end
      end

      if (replay_start_i && !replay_active_q && (count_q != 16'd0)) begin
        replay_active_q <= 1'b1;
        replay_idx_q    <= rd_q;
      end else if (replay_active_q && replay_valid_o && replay_ready_i) begin
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
