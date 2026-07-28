// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_cfg_mgmt_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_cfg_mgmt_item)

  rand bit [9:0]  addr;
  rand bit [7:0]  function_number;
  rand bit        write;
  rand bit        read;
  rand bit [31:0] write_data;
  rand bit [3:0]  byte_enable;
  rand bit        debug_access;
  bit [31:0]      read_data;
  bit             read_write_done;

  function new(string name = "rivet_cfg_mgmt_item");
    super.new(name);
  endfunction

  function void set_idle();
    addr            = '0;
    function_number = '0;
    write           = 1'b0;
    read            = 1'b0;
    write_data      = '0;
    byte_enable     = '0;
    debug_access    = 1'b0;
  endfunction
endclass : rivet_cfg_mgmt_item
