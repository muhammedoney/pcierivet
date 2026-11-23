// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// cfg_mgmt check of class code and header type.

class rivet_cfg_header_seq extends uvm_sequence #(rivet_cfg_mgmt_item);
  `uvm_object_utils(rivet_cfg_header_seq)

  bit [23:0] exp_class = 24'h120000;
  bit [7:0]  exp_hdr   = 8'h00;

  function new(string name = "rivet_cfg_header_seq");
    super.new(name);
  endfunction

  task do_read(bit [9:0] a, output bit [31:0] data);
    rivet_cfg_mgmt_item item;
    item = rivet_cfg_mgmt_item::type_id::create("cfg_rd");
    start_item(item);
    item.set_read(a);
    finish_item(item);
    if (!item.read_write_done)
      `uvm_error(get_type_name(), $sformatf("Read addr=0x%0h missing done", a))
    data = item.read_data;
  endtask

  task body();
    bit [31:0] dw2, dw3;
    do_read(10'd2, dw2);
    if (dw2[31:8] !== exp_class)
      `uvm_error(get_type_name(),
        $sformatf("class 0x%06h, expected 0x%06h", dw2[31:8], exp_class))
    do_read(10'd3, dw3);
    if (dw3[23:16] !== exp_hdr)
      `uvm_error(get_type_name(),
        $sformatf("header type 0x%02h, expected 0x%02h", dw3[23:16], exp_hdr))
    else
      `uvm_info(get_type_name(),
        $sformatf("header class 0x%06h type 0x%02h", exp_class, exp_hdr), UVM_LOW)
  endtask
endclass : rivet_cfg_header_seq
