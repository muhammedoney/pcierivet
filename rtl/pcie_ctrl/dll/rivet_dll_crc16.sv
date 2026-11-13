// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// DLLP CRC-16 (Base 2.1 §3.4.1): poly 100Bh, seed FFFFh, bit0-of-byte0 first,
// then complement. LSB-first already yields wire bit order — do not remap.
//
// Flat 32-bit XOR (rivet_dllp_crc16_par). A bit-serial LFSR over the four
// info bytes is a 32-deep chain and does not close at Gen2 pclk (250 MHz).

module rivet_dll_crc16 (
  input  logic [47:0] body_i,   // info bytes 1..4 in [31:0]; [47:32] unused
  output logic [15:0] crc_o     // wire CRC in bytes 5..6 (byte5=[7:0], byte6=[15:8])
);

  import rivet_pkg::*;

  assign crc_o = rivet_dllp_crc16_par(body_i[31:0]);

endmodule : rivet_dll_crc16
