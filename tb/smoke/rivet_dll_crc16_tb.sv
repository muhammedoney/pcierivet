// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Directed Verilator TB for rivet_dll_crc16 (DLLP body → wire CRC field).

`timescale 1ns/1ps

module rivet_dll_crc16_tb;
  import rivet_pkg::*;

  logic [47:0] body;
  logic [15:0] crc;

  rivet_dll_crc16 u_dut (
    .body_i (body),
    .crc_o  (crc)
  );

  // Independent reference (same algorithm as DUT) for self-check.
  function automatic logic [15:0] ref_crc(input logic [47:0] b);
    logic [15:0] c;
    logic [7:0]  byte_v;
    logic        din, fb;
    c = 16'hFFFF;
    for (int unsigned bi = 0; bi < 4; bi++) begin
      byte_v = b[8*bi +: 8];
      for (int unsigned bit_i = 0; bit_i < 8; bit_i++) begin
        din = byte_v[bit_i];
        fb  = c[0] ^ din;
        c   = {1'b0, c[15:1]};
        if (fb) c = c ^ 16'hD008;
      end
    end
    c = ~c;
    return c;
  endfunction

  initial begin
    // All-zero body
    body = 48'h0;
    #1;
    if (crc !== ref_crc(body)) begin
      $error("CRC mismatch zero body: dut=%04h ref=%04h", crc, ref_crc(body));
      $fatal(1);
    end

    // Ack DLLP type + reserved zeros (seq in info bytes 2-3 unused here)
    body = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00}; // byte5..byte0 packing
    // body[7:0]=byte0 type Ack
    body = 48'h00_00_00_00_00_00;
    #1;
    if (crc !== ref_crc(body)) $fatal(1, "ack-zero");

    // InitFC1-P VC0, HdrFC=1, DataFC=0
    // byte0=0x40, byte1=0x00, byte2=0x01, byte3=0x00, byte4=0x00, byte5=0x00
    body = {8'h00, 8'h00, 8'h00, 8'h01, 8'h00, 8'h40};
    #1;
    if (crc !== ref_crc(body)) begin
      $error("InitFC1-P mismatch dut=%04h ref=%04h", crc, ref_crc(body));
      $fatal(1);
    end

    // Captured PG213 InitFC1-P: 40 08 00 e0 → wire CRC 06F5.
    body = 48'h00_00_E0_00_08_40;
    #1;
    if (crc !== 16'h06F5) begin
      $error("PG213 InitFC1-P CRC dut=%04h exp=06F5", crc);
      $fatal(1);
    end

    $display("PASS: rivet_dll_crc16_tb (CRC=%04h for InitFC1-P sample)", crc);
    $finish;
  end
endmodule : rivet_dll_crc16_tb
