// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_dllp_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_dllp_item)

  bit from_dut; // 1 = observed on DUT TX PIPE
  bit crc_ok;
  bit is_fc;
  bit is_ack;
  bit is_nak;
  rivet_pkg::rivet_dllp_fc_kind_e fc_kind;
  bit [2:0]  vc;
  bit [7:0]  hdr_fc;
  bit [11:0] data_fc;
  bit [11:0] ack_seq;
  bit [7:0]  type_byte;

  function new(string name = "rivet_dllp_item");
    super.new(name);
  endfunction

  function string convert2string();
    if (is_fc)
      return $sformatf("%s FC kind=0x%0h vc=%0d hdr=%0h data=%0h crc_ok=%0b",
                       from_dut ? "DUT" : "PEER", fc_kind, vc, hdr_fc, data_fc, crc_ok);
    if (is_ack)
      return $sformatf("%s ACK seq=%0h crc_ok=%0b", from_dut ? "DUT" : "PEER", ack_seq, crc_ok);
    if (is_nak)
      return $sformatf("%s NAK seq=%0h crc_ok=%0b", from_dut ? "DUT" : "PEER", ack_seq, crc_ok);
    return $sformatf("%s type=0x%02h crc_ok=%0b", from_dut ? "DUT" : "PEER", type_byte, crc_ok);
  endfunction
endclass : rivet_dllp_item
