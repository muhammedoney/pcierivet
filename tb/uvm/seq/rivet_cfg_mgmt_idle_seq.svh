// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_cfg_mgmt_idle_seq extends uvm_sequence #(rivet_cfg_mgmt_item);
  `uvm_object_utils(rivet_cfg_mgmt_idle_seq)

  int unsigned cycles = 40;

  function new(string name = "rivet_cfg_mgmt_idle_seq");
    super.new(name);
  endfunction

  task body();
    rivet_cfg_mgmt_item item;
    repeat (cycles) begin
      item = rivet_cfg_mgmt_item::type_id::create("cfg_idle");
      start_item(item);
      item.set_idle();
      finish_item(item);
    end
  endtask
endclass : rivet_cfg_mgmt_idle_seq
