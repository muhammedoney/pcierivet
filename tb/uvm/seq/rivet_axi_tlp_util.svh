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
endclass : rivet_axi_tlp_util
