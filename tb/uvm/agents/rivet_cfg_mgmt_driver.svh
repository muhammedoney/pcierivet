// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_cfg_mgmt_driver extends uvm_driver #(rivet_cfg_mgmt_item);
  `uvm_component_utils(rivet_cfg_mgmt_driver)

  rivet_cfg_mgmt_vif vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rivet_cfg_mgmt_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_cfg_mgmt_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    rivet_cfg_mgmt_item req;
    drive_idle();
    wait (vif.aresetn === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.aclk);
      vif.addr            <= req.addr;
      vif.function_number <= req.function_number;
      vif.write           <= req.write;
      vif.read            <= req.read;
      vif.write_data      <= req.write_data;
      vif.byte_enable     <= req.byte_enable;
      vif.debug_access    <= req.debug_access;
      seq_item_port.item_done();
    end
  endtask

  task drive_idle();
    vif.addr            <= '0;
    vif.function_number <= '0;
    vif.write           <= 1'b0;
    vif.read            <= 1'b0;
    vif.write_data      <= '0;
    vif.byte_enable     <= '0;
    vif.debug_access    <= 1'b0;
  endtask
endclass : rivet_cfg_mgmt_driver
