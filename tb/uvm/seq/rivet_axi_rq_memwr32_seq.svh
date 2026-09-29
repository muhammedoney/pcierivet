// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Drive RQ Mem32 1DW write (posted) on 64-bit AXI-ST.

class rivet_axi_rq_memwr32_seq extends uvm_sequence #(rivet_axi_st_item);
  `uvm_object_utils(rivet_axi_rq_memwr32_seq)

  bit [31:0] addr = 32'h0000_1000;
  bit [31:0] data = 32'hA5A5_5A5A;
  bit [7:0]  tag  = 8'h11;
  bit [15:0] requester_id = 16'h0100;
  bit [3:0]  first_be = 4'hF;
  bit [3:0]  last_be  = 4'h0;

  function new(string name = "rivet_axi_rq_memwr32_seq");
    super.new(name);
  endfunction

  task send_beat(logic [63:0] tdata, logic [1:0] tkeep, bit tlast, logic [87:0] tuser);
    rivet_axi_st_item item;
    item = rivet_axi_st_item::type_id::create("rq_beat");
    start_item(item);
    item.channel = "rq";
    item.tdata   = tdata;
    item.tkeep   = tkeep;
    item.tlast   = tlast;
    item.tvalid  = 1'b1;
    item.tuser   = tuser;
    item.tready  = 4'hF;
    finish_item(item);
  endtask

  task body();
    logic [63:0] b0, b1, b2;
    logic [87:0] u;

    rivet_axi_tlp_util::pack_mem_desc_2beat(
      addr, 11'd1, rivet_pkg::RIVET_CQ_REQ_MEMWR, tag, requester_id, b0, b1);
    b2 = {32'h0, data};
    u  = rivet_axi_tlp_util::rq_tuser(first_be, last_be);

    send_beat(b0, 2'b11, 1'b0, u);
    send_beat(b1, 2'b11, 1'b0, u);
    send_beat(b2, 2'b01, 1'b1, u);

    `uvm_info(get_type_name(),
      $sformatf("RQ MemWr32 addr=0x%08h data=0x%08h tag=0x%02h", addr, data, tag),
      UVM_MEDIUM)
  endtask
endclass : rivet_axi_rq_memwr32_seq
