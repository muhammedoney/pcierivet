// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// TLP LCRC-32 (Base 2.1 §3.5): poly 04C11DB7, seed FFFF_FFFF, LSB-first per
// byte over Sequence Number (2 B) + TLP, complement, then byte-wise bit reverse
// into the on-wire LCRC field (same remainder mapping style as DLLP CRC-16).

module rivet_dll_lcrc32 (
  // One byte per cycle (clear_i loads seed before first data byte).
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        clear_i,
  input  logic        valid_i,
  input  logic [7:0]  data_i,
  output logic [31:0] crc_o   // wire-order LCRC after invert + byte bit-reverse
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

  function automatic logic [31:0] wire_map(input logic [31:0] crc_in);
    logic [31:0] c;
    c = ~crc_in;
    // Reverse bits within each byte for the LCRC field.
    return {
      c[24], c[25], c[26], c[27], c[28], c[29], c[30], c[31],
      c[16], c[17], c[18], c[19], c[20], c[21], c[22], c[23],
      c[ 8], c[ 9], c[10], c[11], c[12], c[13], c[14], c[15],
      c[ 0], c[ 1], c[ 2], c[ 3], c[ 4], c[ 5], c[ 6], c[ 7]
    };
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

  assign crc_o = wire_map(crc_q);

endmodule : rivet_dll_lcrc32
