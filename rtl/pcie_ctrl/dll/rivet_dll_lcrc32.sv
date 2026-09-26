// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// TLP LCRC-32 (Base 2.1 §3.5): poly 04C11DB7, seed FFFF_FFFF, LSB-first per
// byte over Sequence Number (2 B) + TLP, then complement. Do not remap bits
// (same PG213 lesson as DLLP CRC-16).

module rivet_dll_lcrc32 (
  // One byte per cycle (clear_i loads seed before first data byte).
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        clear_i,
  input  logic        valid_i,
  input  logic [7:0]  data_i,
  output logic [31:0] crc_o   // wire-order LCRC after invert
);

  import rivet_pkg::*;

  logic [31:0] crc_q;

  function automatic logic [31:0] step_byte(input logic [31:0] crc_in, input logic [7:0] b);
    logic [31:0] crc;
    logic        din;
    logic        fb;
    int unsigned bit_i;
    crc = crc_in;
    for (bit_i = 0; bit_i < 8; bit_i++) begin
      din = b[bit_i];
      fb  = crc[0] ^ din;
      crc = {1'b0, crc[31:1]};
      if (fb) crc = crc ^ 32'hEDB88320; // reflected 04C11DB7
    end
    return crc;
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      crc_q <= 32'hFFFF_FFFF;
    end else if (clear_i) begin
      crc_q <= 32'hFFFF_FFFF;
    end else if (valid_i) begin
      crc_q <= step_byte(crc_q, data_i);
    end
  end

  assign crc_o = ~crc_q;

endmodule : rivet_dll_lcrc32
