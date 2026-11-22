// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Replay buffer: one-word capture → ACK purge; capture → replay word read.

`timescale 1ns/1ps

module rivet_dll_replay_tb;
  localparam int unsigned SLOTS = 4;
  localparam int unsigned BYTES = 16;

  logic clk, rst_n, clear;
  logic cap_v, cap_r, cap_last;
  logic [63:0] cap_data;
  logic [11:0] cap_seq;
  logic [15:0] cap_len;
  logic ack_v;
  logic [11:0] ack_seq;
  logic replay_start, replay_active, replay_done, replay_v, replay_r;
  logic [11:0] replay_seq;
  logic [15:0] replay_idx;
  logic [63:0] replay_word;
  logic [15:0] replay_len;
  logic full, empty;
  logic [15:0] occ;

  rivet_dll_replay #(.TLP_SLOTS(SLOTS), .SLOT_BYTES(BYTES)) u_dut (
    .clk_i(clk), .rst_ni(rst_n), .clear_i(clear),
    .cap_valid_i(cap_v), .cap_ready_o(cap_r),
    .cap_data_i(cap_data), .cap_last_i(cap_last),
    .cap_seq_i(cap_seq), .cap_len_i(cap_len),
    .ack_valid_i(ack_v), .ack_seq_i(ack_seq),
    .replay_start_i(replay_start), .replay_active_o(replay_active),
    .replay_done_o(replay_done), .replay_valid_o(replay_v),
    .replay_ready_i(replay_r), .replay_seq_o(replay_seq),
    .replay_word_idx_i(replay_idx), .replay_word_o(replay_word),
    .replay_len_o(replay_len),
    .full_o(full), .empty_o(empty), .occupancy_o(occ)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic push_one(input logic [11:0] seq, input logic [7:0] tag);
    @(negedge clk);
    cap_seq  = seq;
    cap_len  = 16'd4;
    cap_data = {56'h0, tag};
    cap_last = 1'b1;
    cap_v    = 1'b1;
    @(negedge clk);
    while (!cap_r) @(negedge clk);
    cap_v = 1'b0;
    cap_last = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    int unsigned got;
    logic [7:0] tag0;
    rst_n = 1'b0;
    clear = 1'b0;
    cap_v = 1'b0;
    cap_last = 1'b0;
    ack_v = 1'b0;
    replay_start = 1'b0;
    replay_r = 1'b1;
    replay_idx = '0;
    cap_seq = '0;
    cap_len = '0;
    cap_data = '0;
    ack_seq = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    push_one(12'h1, 8'hA1);
    push_one(12'h2, 8'hA2);
    push_one(12'h3, 8'hA3);
    if (occ !== 16'd3) begin
      $error("occ=%0d after 3 pushes", occ);
      $fatal(1);
    end

    ack_seq = 12'h2;
    ack_v = 1'b1;
    @(posedge clk);
    ack_v = 1'b0;
    @(posedge clk);
    if (occ !== 16'd1) begin
      $error("after ACK2 occ=%0d", occ);
      $fatal(1);
    end

    push_one(12'h4, 8'hA4);
    if (occ !== 16'd2) begin
      $error("occ=%0d after push4", occ);
      $fatal(1);
    end

    @(negedge clk);
    replay_start = 1'b1;
    @(negedge clk);
    replay_start = 1'b0;

    got = 0;
    while (got < 2) begin
      @(posedge clk);
      if (replay_v) begin
        tag0 = replay_word[7:0];
        if (got == 0 && (replay_seq !== 12'h3 || tag0 !== 8'hA3)) begin
          $error("replay[0] seq=%h tag=%h", replay_seq, tag0);
          $fatal(1);
        end
        if (got == 1 && (replay_seq !== 12'h4 || tag0 !== 8'hA4)) begin
          $error("replay[1] seq=%h tag=%h", replay_seq, tag0);
          $fatal(1);
        end
        got++;
      end
    end
    repeat (2) @(posedge clk);
    if (replay_active) begin
      $error("replay still active");
      $fatal(1);
    end

    $display("PASS: rivet_dll_replay_tb");
    $finish;
  end

  initial begin
    #100000;
    $error("timeout active=%0b valid=%0b occ=%0d got stuck", replay_active, replay_v, occ);
    $fatal(1);
  end
endmodule : rivet_dll_replay_tb
