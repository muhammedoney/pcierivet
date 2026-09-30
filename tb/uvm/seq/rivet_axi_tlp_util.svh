// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// AXI-ST TLP beat helpers (64-bit dword-aligned, PG213-style).

class rivet_axi_tlp_util;
  static function logic [87:0] cq_tuser(bit [3:0] first_be, bit [3:0] last_be,
                                        bit sop = 1'b1);
    return rivet_pkg::rivet_cq_tuser_pack(first_be, last_be, 32'h0, sop, 1'b0);
  endfunction

  static function logic [32:0] cc_tuser();
    return rivet_pkg::rivet_cc_tuser_pack(1'b0);
  endfunction

  // RQ tuser LSBs: [3:0] first_be, [7:4] last_be.
  static function logic [87:0] rq_tuser(bit [3:0] first_be, bit [3:0] last_be);
    return {80'h0, last_be, first_be};
  endfunction

  // CQ/RQ Mem descriptor beats: beat0={DW1,DW0}, beat1={DW3,DW2}.
  static function void pack_mem_desc_2beat(
      input  logic [31:0] addr,
      input  logic [10:0] dword_count,
      input  logic [3:0]  req_type,
      input  logic [7:0]  tag,
      input  logic [15:0] requester_id,
      output logic [63:0] beat0,
      output logic [63:0] beat1);
    logic [31:0] dw0, dw1, dw2, dw3;
    dw0 = {addr[31:2], 2'b00};
    dw1 = 32'h0;
    // DW2[10:0]=length, [14:11]=req_type; upper bits 0 for Phase-1 helpers.
    dw2 = {17'h0, req_type, dword_count};
    // DW3[7:0]=tag, [23:8]=requester_id; BAR/fn 0.
    dw3 = {8'h0, requester_id, tag};
    beat0 = {dw1, dw0};
    beat1 = {dw3, dw2};
  endfunction

  static function void unpack_mem_desc_2beat(
      input  logic [63:0] beat0,
      input  logic [63:0] beat1,
      output logic [31:0] addr,
      output logic [10:0] dword_count,
      output logic [3:0]  req_type,
      output logic [7:0]  tag,
      output logic [15:0] requester_id);
    logic [31:0] dw0, dw1, dw2, dw3;
    dw0 = beat0[31:0];
    dw1 = beat0[63:32];
    dw2 = beat1[31:0];
    dw3 = beat1[63:32];
    addr          = {dw0[31:2], 2'b00};
    dword_count   = dw2[10:0];
    req_type      = dw2[14:11];
    tag           = dw3[7:0];
    requester_id  = dw3[23:8];
  endfunction

  // CC CplD 1DW: beat0={DW1,DW0}, beat1={data,DW2}, tlast on beat1.
  static function void pack_cc_cpld_1dw(
      input  logic [6:0]  lower_addr,
      input  logic [12:0] byte_count,
      input  logic [2:0]  cpl_status,
      input  logic [15:0] requester_id,
      input  logic [7:0]  tag,
      input  logic [15:0] completer_id,
      input  logic [31:0] data,
      output logic [63:0] beat0,
      output logic [63:0] beat1);
    logic [31:0] dw0, dw1, dw2;
    // DW0: lower_addr[6:0], rsvd, at, rsvd, byte_count in [24:12] region.
    dw0 = {7'h0, byte_count, 2'b00, 2'b00, 1'b0, lower_addr};
    // DW1: dword_count, cpl_status, poisoned, rsvd, requester_id.
    dw1 = {requester_id, 1'b0, 1'b0, cpl_status, 11'd1};
    // DW2: tag, completer_id, completer_id_en, tc, attr, force_ecrc.
    dw2 = {1'b0, 3'b000, 3'b000, 1'b0, completer_id, tag};
    beat0 = {dw1, dw0};
    beat1 = {data, dw2};
  endfunction

  // Wire MemRd32 as two TL beats (exact layout from rivet_tl_cq_cc_tb).
  static function void pack_memrd32_tl_beats(
      input  logic [31:0] addr,
      input  logic [7:0]  tag,
      input  logic [15:0] requester_id,
      input  logic [3:0]  first_be,
      output logic [63:0] beat0,
      output logic [63:0] beat1);
    beat0 = {4'h0, first_be, tag, requester_id[15:8], requester_id[7:0],
             8'h00, 8'h01, 8'h00, rivet_pkg::RIVET_TLP_B0_MEMRD32};
    beat1 = {32'h0, addr[7:0], addr[15:8], addr[23:16], addr[31:24]};
  endfunction

  // Wire MemRd64: 4-DW header as two 64-bit beats (addr_hi then addr_lo).
  static function void pack_memrd64_tl_beats(
      input  logic [63:0] addr,
      input  logic [7:0]  tag,
      input  logic [15:0] requester_id,
      input  logic [3:0]  first_be,
      output logic [63:0] beat0,
      output logic [63:0] beat1);
    logic [31:0] alo, ahi;
    alo = addr[31:0];
    ahi = addr[63:32];
    beat0 = {4'h0, first_be, tag, requester_id[15:8], requester_id[7:0],
             8'h00, 8'h01, 8'h00, rivet_pkg::RIVET_TLP_B0_MEMRD64};
    // beat1 = {DW3=addr_lo, DW2=addr_hi} with same byte order as Mem32 addr field
    beat1 = {alo[7:0], alo[15:8], alo[23:16], alo[31:24],
             ahi[7:0], ahi[15:8], ahi[23:16], ahi[31:24]};
  endfunction

  // Wire CplD 1DW as two TL beats (exact layout from rivet_tl_rq_rc_tb).
  static function void pack_cpld_tl_beats(
      input  logic [15:0] requester_id,
      input  logic [7:0]  tag,
      input  logic [31:0] data,
      output logic [63:0] beat0,
      output logic [63:0] beat1);
    // smoke: {8'h04, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, 8'h00, CPLD}
    //         {data, 8'h00, tag, req_hi, req_lo}
    beat0 = {8'h04, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, 8'h00,
             rivet_pkg::RIVET_TLP_B0_CPLD};
    beat1 = {data, 8'h00, tag, requester_id[15:8], requester_id[7:0]};
  endfunction

  // DLL framed image: Seq# + TLP payload + LCRC (byte0 in [7:0]).
  static function void pack_dll_tlp_frame(
      input  logic [11:0] seq,
      input  logic [63:0] beat0,
      input  logic [63:0] beat1,
      input  int unsigned pld_bytes,
      output logic [8*32-1:0] frame,
      output int unsigned     frame_bytes);
    logic [8*160-1:0] crc_in;
    logic [15:0]      seq_w;
    logic [31:0]      lcrc;
    int unsigned      i, base;
    frame = '0;
    seq_w = rivet_pkg::rivet_tlp_seq_bytes(seq);
    frame[7:0]  = seq_w[7:0];
    frame[15:8] = seq_w[15:8];
    for (i = 0; i < 8 && i < pld_bytes; i++)
      frame[8*(2+i) +: 8] = beat0[8*i +: 8];
    for (i = 0; i < 8 && (8+i) < pld_bytes; i++)
      frame[8*(2+8+i) +: 8] = beat1[8*i +: 8];
    crc_in = '0;
    for (i = 0; i < 2 + pld_bytes; i++)
      crc_in[8*i +: 8] = frame[8*i +: 8];
    lcrc = rivet_pkg::rivet_lcrc32_calc(crc_in, 2 + pld_bytes);
    base = 2 + pld_bytes;
    frame[8*(base+0) +: 8] = lcrc[7:0];
    frame[8*(base+1) +: 8] = lcrc[15:8];
    frame[8*(base+2) +: 8] = lcrc[23:16];
    frame[8*(base+3) +: 8] = lcrc[31:24];
    frame_bytes = base + 4;
  endfunction

  // STP + payload + END (idx 0 = STP, idx nbytes+1 = END).
  static function logic [8:0] framed_tlp_sym(
      input int unsigned idx,
      input logic [8*32-1:0] payload,
      input int unsigned nbytes);
    if (idx == 0) return {1'b1, rivet_pkg::RIVET_SYM_STP};
    if (idx == nbytes + 1) return {1'b1, rivet_pkg::RIVET_SYM_END};
    if (idx >= 1 && idx <= nbytes)
      return {1'b0, payload[8*(idx-1) +: 8]};
    return {1'b0, 8'h00};
  endfunction
endclass : rivet_axi_tlp_util
