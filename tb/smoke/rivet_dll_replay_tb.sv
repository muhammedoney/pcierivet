// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Replay buffer: push → ACK purge; push → NAK replay stream.

`timescale 1ns/1ps

module rivet_dll_replay_tb;
  localparam int unsigned SLOTS = 4;
  localparam int unsigned BYTES = 16;
  localparam int unsigned DATA_W = BYTES * 8;

  logic clk, rst_n, clear;
  logic push_v, push_r;
  logic [11:0] push_seq;
  logic [DATA_W-1:0] push_data;
  logic [15:0] push_len;
  logic ack_v;
  logic [11:0] ack_seq;
  logic replay_start, replay_active, replay_done, replay_v, replay_r;
  logic [11:0] replay_seq;
  logic [DATA_W-1:0] replay_data;
  logic [15:0] replay_len;
  logic full, empty;
  logic [15:0] occ;

  rivet_dll_replay #(.TLP_SLOTS(SLOTS), .SLOT_BYTES(BYTES)) u_dut (
    .clk_i(clk), .rst_ni(rst_n), .clear_i(clear),
    .push_valid_i(push_v), .push_ready_o(push_r),
    .push_seq_i(push_seq), .push_data_i(push_data), .push_len_i(push_len),
    .ack_valid_i(ack_v), .ack_seq_i(ack_seq),
    .replay_start_i(replay_start), .replay_active_o(replay_active),
    .replay_done_o(replay_done), .replay_valid_o(replay_v),
    .replay_ready_i(replay_r), .replay_seq_o(replay_seq),
    .replay_data_o(replay_data), .replay_len_o(replay_len),
    .full_o(full), .empty_o(empty), .occupancy_o(occ)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic push_one(input logic [11:0] seq, input logic [7:0] tag);
    @(negedge clk);
    push_seq  = seq;
    push_len  = 16'd4;
    push_data = { {(DATA_W-8){1'b0}}, tag };
    push_v    = 1'b1;
    @(negedge clk);
    while (!push_r) @(negedge clk);
    push_v = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    int unsigned got;
    logic [7:0] tag0;
    rst_n = 1'b0;
    clear = 1'b0;
    push_v = 1'b0;
    ack_v = 1'b0;
    replay_start = 1'b0;
    replay_r = 1'b1;
    push_seq = '0;
    push_len = '0;
    push_data = '0;
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
    repeat (4) @(posedge clk);
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
        tag0 = replay_data[7:0];
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
