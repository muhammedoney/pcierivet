// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// DLLP CRC-16 (Base 2.1 §3.4.1): poly 100Bh, seed FFFFh, bit0-of-byte0 first,
// then complement. LSB-first already yields wire bit order — do not remap.

module rivet_dll_crc16 (
  input  logic [47:0] body_i,   // info bytes 1..4 in [31:0]; [47:32] unused
  output logic [15:0] crc_o     // wire CRC in bytes 5..6 (byte5=[7:0], byte6=[15:8])
);

  import rivet_pkg::*;

  // Combinational CRC over the 32-bit DLLP (four info bytes).
  function automatic logic [15:0] rivet_dllp_crc16_calc(input logic [47:0] body);
    logic [15:0] crc;
    logic [7:0]  b;
    logic        din;
    logic        fb;
    int unsigned bi;
    int unsigned bit_i;
    crc = 16'hFFFF;
    for (bi = 0; bi < 4; bi++) begin
      b = body[8*bi +: 8];
      for (bit_i = 0; bit_i < 8; bit_i++) begin
        din = b[bit_i];
        fb  = crc[0] ^ din;
        crc = {1'b0, crc[15:1]};
        if (fb) crc = crc ^ 16'hD008; // bit-reversed 100Bh for LSB-first shift
      end
    end
    crc = ~crc;
    return crc;
  endfunction

  assign crc_o = rivet_dllp_crc16_calc(body_i);

endmodule : rivet_dll_crc16
