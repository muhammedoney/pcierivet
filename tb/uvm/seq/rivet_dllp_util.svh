// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// DLLP encode/decode helpers for UVM (CRC-16 + FC body layout from rivet_pkg).

class rivet_dllp_util;
  // Same algorithm as rivet_dll_crc16 (Base 2.1 §3.4.1).
  static function logic [15:0] crc16(input logic [31:0] info);
    logic [15:0] crc;
    logic [7:0]  b;
    logic        din, fb;
    int unsigned bi, bit_i;
    crc = 16'hFFFF;
    for (bi = 0; bi < 4; bi++) begin
      b = info[8*bi +: 8];
      for (bit_i = 0; bit_i < 8; bit_i++) begin
        din = b[bit_i];
        fb  = crc[0] ^ din;
        crc = {1'b0, crc[15:1]};
        if (fb) crc = crc ^ 16'hD008;
      end
    end
    return ~crc;
  endfunction

  static function logic [31:0] pack_fc_info(
      input rivet_pkg::rivet_dllp_fc_kind_e kind,
      input logic [2:0]  vc,
      input logic [7:0]  hdr_fc,
      input logic [11:0] data_fc);
    logic [7:0] t;
    t = rivet_pkg::rivet_dllp_fc_type_byte(kind, vc);
    return {4'h0, data_fc[11:8], data_fc[7:0], hdr_fc, t};
  endfunction

  // Wire bytes [47:0] = {crc_hi, crc_lo, b3, b2, b1, b0}
  static function logic [47:0] pack_fc_wire(
      input rivet_pkg::rivet_dllp_fc_kind_e kind,
      input logic [2:0]  vc,
      input logic [7:0]  hdr_fc,
      input logic [11:0] data_fc);
    logic [31:0] info;
    logic [15:0] c;
    info = pack_fc_info(kind, vc, hdr_fc, data_fc);
    c    = crc16(info);
    return {c[15:8], c[7:0], info[31:24], info[23:16], info[15:8], info[7:0]};
  endfunction

  // Framed 8 symbols: SDP + 6 wire bytes + END. Index 0 = SDP.
  static function logic [8:0] framed_sym(input int unsigned idx, input logic [47:0] wire6);
    if (idx == 0) return {1'b1, rivet_pkg::RIVET_SYM_SDP};
    if (idx == 7) return {1'b1, rivet_pkg::RIVET_SYM_END};
    if (idx >= 1 && idx <= 6)
      return {1'b0, wire6[8*(idx-1) +: 8]};
    return {1'b0, 8'h00};
  endfunction

  static function bit decode_fc(
      input  logic [47:0] wire6,
      output rivet_pkg::rivet_dllp_fc_kind_e kind,
      output logic [2:0]  vc,
      output logic [7:0]  hdr_fc,
      output logic [11:0] data_fc,
      output bit          crc_ok);
    logic [31:0] info;
    logic [15:0] c_rx, c_calc;
    logic [7:0]  t;
    info   = {wire6[31:24], wire6[23:16], wire6[15:8], wire6[7:0]};
    c_rx   = {wire6[47:40], wire6[39:32]};
    c_calc = crc16(info);
    crc_ok = (c_rx === c_calc);
    t      = info[7:0];
    vc     = t[2:0];
    hdr_fc = info[15:8];
    data_fc = {info[27:24], info[23:16]};
    kind = rivet_pkg::rivet_dllp_fc_kind_e'(t[7:4]);
    return crc_ok;
  endfunction

  static function bit is_ack_nak(input logic [7:0] type_b);
    return (type_b == rivet_pkg::RIVET_DLLP_TYPE_ACK) ||
           (type_b == rivet_pkg::RIVET_DLLP_TYPE_NAK);
  endfunction
endclass : rivet_dllp_util
