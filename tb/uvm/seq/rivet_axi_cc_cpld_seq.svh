// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Drive CC CplD 1DW completion on 64-bit AXI-ST.

class rivet_axi_cc_cpld_seq extends uvm_sequence #(rivet_axi_st_item);
  `uvm_object_utils(rivet_axi_cc_cpld_seq)

  bit [6:0]  lower_addr   = 7'h0;
  bit [12:0] byte_count   = 13'd4;
  bit [2:0]  cpl_status   = 3'b000; // SC
  bit [15:0] requester_id = 16'h0000;
  bit [7:0]  tag          = 8'h0;
  bit [15:0] completer_id = 16'h0100;
  bit [31:0] data         = 32'h0;

  function new(string name = "rivet_axi_cc_cpld_seq");
    super.new(name);
  endfunction

  task send_beat(logic [63:0] tdata, logic [1:0] tkeep, bit tlast, logic [87:0] tuser);
    rivet_axi_st_item item;
    item = rivet_axi_st_item::type_id::create("cc_beat");
    start_item(item);
    item.channel = "cc";
    item.tdata   = tdata;
    item.tkeep   = tkeep;
    item.tlast   = tlast;
    item.tvalid  = 1'b1;
    item.tuser   = tuser;
    item.tready  = 4'hF;
    finish_item(item);
  endtask

  task body();
    logic [63:0] b0, b1;
    logic [87:0] u;

    rivet_axi_tlp_util::pack_cc_cpld_1dw(
      lower_addr, byte_count, cpl_status, requester_id, tag, completer_id, data,
      b0, b1);
    u = {55'h0, rivet_axi_tlp_util::cc_tuser()};

    send_beat(b0, 2'b11, 1'b0, u);
    send_beat(b1, 2'b11, 1'b1, u);

    `uvm_info(get_type_name(),
      $sformatf("CC CplD tag=0x%02h req_id=0x%04h data=0x%08h",
                tag, requester_id, data), UVM_MEDIUM)
  endtask
endclass : rivet_axi_cc_cpld_seq
