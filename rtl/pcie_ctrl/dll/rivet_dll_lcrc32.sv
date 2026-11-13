// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// TLP LCRC-32 (Base 2.1 §3.5): poly 04C11DB7, seed FFFF_FFFF, LSB-first per
// byte over Sequence Number (2 B) + TLP, then complement. Do not remap bits
// (same PG213 lesson as DLLP CRC-16).
//
// One registered byte per cycle. The byte update is a flat XOR
// (rivet_crc32_fold), not an 8-step serial LFSR.

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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      crc_q <= 32'hFFFF_FFFF;
    end else if (clear_i) begin
      crc_q <= 32'hFFFF_FFFF;
    end else if (valid_i) begin
      crc_q <= rivet_crc32_fold(crc_q, {56'd0, data_i}, 4'd1);
    end
  end

  assign crc_o = ~crc_q;

endmodule : rivet_dll_lcrc32
