// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Drive RQ MemRd32 (2 descriptor beats).

class rivet_axi_rq_memrd32_seq extends uvm_sequence #(rivet_axi_st_item);
  `uvm_object_utils(rivet_axi_rq_memrd32_seq)

  bit [31:0] addr = 32'h0000_1000;
  // Nonzero selects a 64-bit-address MemRd (TLP type 0x20).
  bit [31:0] addr_hi = 32'h0;
  bit [7:0]  tag  = 8'h11;
  bit [15:0] requester_id = 16'h0100;
  bit [3:0]  first_be = 4'hF;
  // 1 keeps the original 1 DW request. 1024 is the PCIe length encoding 0.
  bit [10:0] payload_dw = 11'd1;

  function new(string name = "rivet_axi_rq_memrd32_seq");
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
    logic [63:0] b0, b1;
    logic [87:0] u;
    int unsigned axi_w;
    if (!uvm_config_db#(int unsigned)::get(m_sequencer, "", "axi_data_width", axi_w))
      axi_w = 64;
    rivet_axi_tlp_util::pack_mem_desc_2beat(
      addr, payload_dw, rivet_pkg::RIVET_CQ_REQ_MEMRD, tag, requester_id, b0, b1,
      addr_hi);
    u = rivet_axi_tlp_util::rq_tuser(first_be, (payload_dw > 11'd1) ? 4'hF : 4'h0);
    if (axi_w >= 128) begin
      rivet_axi_st_item item;
      item = rivet_axi_st_item::type_id::create("rq_beat");
      start_item(item);
      item.channel = "rq";
      item.tdata   = {b1, b0};
      item.tkeep   = 4'hF;
      item.tlast   = 1'b1;
      item.tvalid  = 1'b1;
      item.tuser   = u;
      item.tready  = 4'hF;
      finish_item(item);
    end else begin
      send_beat(b0, 2'b11, 1'b0, u);
      send_beat(b1, 2'b11, 1'b1, u);
    end
    `uvm_info(get_type_name(),
      $sformatf("RQ MemRd addr=0x%08h_%08h tag=0x%02h dw=%0d", addr_hi, addr, tag, payload_dw),
      UVM_MEDIUM)
  endtask
endclass : rivet_axi_rq_memrd32_seq
