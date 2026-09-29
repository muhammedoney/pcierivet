// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Directed cfg_mgmt: stable Device/Vendor read + Command RMW via byte enables.

class rivet_cfg_mgmt_rw_seq extends uvm_sequence #(rivet_cfg_mgmt_item);
  `uvm_object_utils(rivet_cfg_mgmt_rw_seq)

  // Type0 DW addresses (PG213 dword addr).
  bit [9:0] addr_id      = 10'h000; // Vendor/Device ID
  bit [9:0] addr_cmd_sts = 10'h001; // Command / Status

  bit [31:0] id_value;
  bit [31:0] cmd_before;
  bit [31:0] cmd_after;

  function new(string name = "rivet_cfg_mgmt_rw_seq");
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

  task do_write(bit [9:0] a, bit [31:0] data, bit [3:0] be);
    rivet_cfg_mgmt_item item;
    item = rivet_cfg_mgmt_item::type_id::create("cfg_wr");
    start_item(item);
    item.set_write(a, data, be);
    finish_item(item);
    if (!item.read_write_done)
      `uvm_error(get_type_name(), $sformatf("Write addr=0x%0h missing done", a))
  endtask

  task body();
    bit [31:0] id2;
    bit [15:0] cmd_w, cmd_r;

    // 1) Device/Vendor must be readable and stable.
    do_read(addr_id, id_value);
    do_read(addr_id, id2);
    if (id_value !== id2)
      `uvm_error(get_type_name(),
        $sformatf("Vendor/Device unstable: 0x%08h vs 0x%08h", id_value, id2))
    else
      `uvm_info(get_type_name(),
        $sformatf("cfg_mgmt ID DW0 = 0x%08h (stable)", id_value), UVM_LOW)

    // 2) Command RMW: write lower half only (Status is typically RO).
    do_read(addr_cmd_sts, cmd_before);
    cmd_w = cmd_before[15:0] | 16'h0006; // Memory Space + Bus Master Enable
    do_write(addr_cmd_sts, {16'h0, cmd_w}, 4'b0011);
    do_read(addr_cmd_sts, cmd_after);
    cmd_r = cmd_after[15:0];

    // Status may change independently; only check Command bits we set.
    if ((cmd_r & 16'h0006) !== 16'h0006)
      `uvm_error(get_type_name(),
        $sformatf("Command BME/MSE not set after write: cmd=0x%04h (before=0x%04h)",
                  cmd_r, cmd_before[15:0]))
    else
      `uvm_info(get_type_name(),
        $sformatf("cfg_mgmt Command RMW OK: 0x%04h -> 0x%04h",
                  cmd_before[15:0], cmd_r), UVM_LOW)
  endtask
endclass : rivet_cfg_mgmt_rw_seq
