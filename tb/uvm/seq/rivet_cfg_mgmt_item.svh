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
  bit             txn_complete; // monitor: rising edge of done

  constraint c_mutex_rw {
    !(read && write);
  }

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
    read_data       = '0;
    read_write_done = 1'b0;
    txn_complete    = 1'b0;
  endfunction

  function void set_read(bit [9:0] a, bit [7:0] fn = 8'h0);
    set_idle();
    addr            = a;
    function_number = fn;
    read            = 1'b1;
    byte_enable     = 4'hF;
  endfunction

  function void set_write(bit [9:0] a, bit [31:0] data, bit [3:0] be = 4'hF,
                          bit [7:0] fn = 8'h0);
    set_idle();
    addr            = a;
    function_number = fn;
    write           = 1'b1;
    write_data      = data;
    byte_enable     = be;
  endfunction

  function string convert2string();
    return $sformatf("cfg a=0x%0h fn=%0d r=%0b w=%0b be=%0h wd=0x%08h rd=0x%08h done=%0b",
                     addr, function_number, read, write, byte_enable,
                     write_data, read_data, read_write_done);
  endfunction
endclass : rivet_cfg_mgmt_item
