// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Publishes idle samples and completed cfg_mgmt transactions (done rising).

class rivet_cfg_mgmt_monitor extends uvm_monitor;
  `uvm_component_utils(rivet_cfg_mgmt_monitor)

  rivet_cfg_mgmt_vif vif;
  uvm_analysis_port #(rivet_cfg_mgmt_item) ap;
  bit prev_done;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(rivet_cfg_mgmt_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_cfg_mgmt_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    rivet_cfg_mgmt_item item;
    wait (vif.aresetn === 1'b1);
    prev_done = 1'b0;
    forever begin
      @(posedge vif.aclk);
      item = rivet_cfg_mgmt_item::type_id::create("cfg_mon");
      item.addr            = vif.addr;
      item.function_number = vif.function_number;
      item.write           = vif.write;
      item.read            = vif.read;
      item.write_data      = vif.write_data;
      item.byte_enable     = vif.byte_enable;
      item.debug_access    = vif.debug_access;
      item.read_data       = vif.read_data;
      item.read_write_done = vif.read_write_done;

      // Rising edge of done marks a completed access for scoreboard/coverage.
      if (vif.read_write_done && !prev_done)
        item.txn_complete = 1'b1;
      else
        item.txn_complete = 1'b0;

      prev_done = vif.read_write_done;
      ap.write(item);
    end
  endtask
endclass : rivet_cfg_mgmt_monitor
