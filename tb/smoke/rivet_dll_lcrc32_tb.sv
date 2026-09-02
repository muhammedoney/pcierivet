// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// LCRC-32: same message → same CRC; mutate one bit → CRC changes.

`timescale 1ns/1ps

module rivet_dll_lcrc32_tb;
  logic clk;
  logic rst_n;
  logic clear;
  logic valid;
  logic [7:0] data;
  logic [31:0] crc;

  rivet_dll_lcrc32 u_dut (
    .clk_i(clk), .rst_ni(rst_n), .clear_i(clear),
    .valid_i(valid), .data_i(data), .crc_o(crc)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic feed8(input logic [7:0] b0, b1, b2, b3, b4, b5, b6, b7,
                       output logic [31:0] out_crc);
    logic [7:0] bytes [0:7];
    int unsigned i;
    bytes[0]=b0; bytes[1]=b1; bytes[2]=b2; bytes[3]=b3;
    bytes[4]=b4; bytes[5]=b5; bytes[6]=b6; bytes[7]=b7;
    @(posedge clk);
    clear = 1'b1;
    valid = 1'b0;
    @(posedge clk);
    clear = 1'b0;
    for (i = 0; i < 8; i++) begin
      data  = bytes[i];
      valid = 1'b1;
      @(posedge clk);
    end
    valid = 1'b0;
    @(posedge clk);
    out_crc = crc;
  endtask

  initial begin
    logic [31:0] c0, c1, c2;
    rst_n = 1'b0;
    clear = 1'b0;
    valid = 1'b0;
    data  = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    feed8(8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h55, c0);
    feed8(8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h55, c1);
    if (c0 !== c1) begin
      $error("LCRC not stable %08h vs %08h", c0, c1);
      $fatal(1);
    end

    feed8(8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h54, c2);
    if (c2 === c0) begin
      $error("LCRC did not change on data flip");
      $fatal(1);
    end

    $display("PASS: rivet_dll_lcrc32_tb crc=%08h", c0);
    $finish;
  end
endmodule : rivet_dll_lcrc32_tb
