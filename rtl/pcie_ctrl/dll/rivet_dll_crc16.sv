// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// DLLP CRC-16 (Base 2.1 §3.4.1): poly 100Bh, seed FFFFh, bit0-of-byte0 first,
// complement, then Table 3-2 bit mapping into the CRC field.

module rivet_dll_crc16 (
  input  logic [47:0] body_i,   // DLLP bytes 0..5, byte0 in [7:0]
  output logic [15:0] crc_o     // wire-order CRC field (byte6=[7:0], byte7=[15:8])
);

  import rivet_pkg::*;

  // Combinational CRC over six body bytes.
  function automatic logic [15:0] rivet_dllp_crc16_calc(input logic [47:0] body);
    logic [15:0] crc;
    logic [7:0]  b;
    logic        din;
    logic        fb;
    int unsigned bi;
    int unsigned bit_i;
    crc = 16'hFFFF;
    for (bi = 0; bi < 6; bi++) begin
      b = body[8*bi +: 8];
      for (bit_i = 0; bit_i < 8; bit_i++) begin
        din = b[bit_i];
        fb  = crc[0] ^ din;
        crc = {1'b0, crc[15:1]};
        if (fb) crc = crc ^ 16'hD008; // bit-reversed 100Bh for LSB-first shift
      end
    end
    crc = ~crc;
    // Table 3-2: reverse bits within each byte of the remainder.
    return {crc[8],  crc[9],  crc[10], crc[11], crc[12], crc[13], crc[14], crc[15],
            crc[0],  crc[1],  crc[2],  crc[3],  crc[4],  crc[5],  crc[6],  crc[7]};
  endfunction

  assign crc_o = rivet_dllp_crc16_calc(body_i);

endmodule : rivet_dll_crc16
