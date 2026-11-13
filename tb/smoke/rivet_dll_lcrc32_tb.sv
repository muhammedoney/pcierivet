// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// LCRC-32: same message → same CRC; mutate one bit → CRC changes.

`timescale 1ns/1ps

module rivet_dll_lcrc32_tb;
  import rivet_pkg::*;

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

  function automatic logic [31:0] ref_byte(input logic [31:0] crc_in,
                                           input logic [7:0] b);
    logic [31:0] c;
    logic        fb;
    c = crc_in;
    for (int unsigned bit_i = 0; bit_i < 8; bit_i++) begin
      fb = c[0] ^ b[bit_i];
      c  = {1'b0, c[31:1]};
      if (fb) c = c ^ 32'hEDB88320;
    end
    return c;
  endfunction

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

    begin
      logic [31:0] exp;
      logic [7:0]  bytes [0:7];
      bytes[0]=8'h00; bytes[1]=8'h01; bytes[2]=8'h00; bytes[3]=8'h00;
      bytes[4]=8'h00; bytes[5]=8'h01; bytes[6]=8'hAA; bytes[7]=8'h55;
      exp = 32'hFFFF_FFFF;
      for (int unsigned i = 0; i < 8; i++) exp = ref_byte(exp, bytes[i]);
      exp = ~exp;
      if (rivet_crc32_fold(32'hFFFF_FFFF,
                           {bytes[7], bytes[6], bytes[5], bytes[4],
                            bytes[3], bytes[2], bytes[1], bytes[0]},
                           4'd8) != ~exp) begin
        $error("parallel fold8 != serial LCRC");
        $fatal(1);
      end
    end

    feed8(8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h55, c0);
    begin
      logic [31:0] exp;
      exp = ref_byte(32'hFFFF_FFFF, 8'h00);
      exp = ref_byte(exp, 8'h01);
      exp = ref_byte(exp, 8'h00);
      exp = ref_byte(exp, 8'h00);
      exp = ref_byte(exp, 8'h00);
      exp = ref_byte(exp, 8'h01);
      exp = ref_byte(exp, 8'hAA);
      exp = ref_byte(exp, 8'h55);
      if (c0 !== ~exp) begin
        $error("byte engine %08h != serial %08h", c0, ~exp);
        $fatal(1);
      end
    end
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
