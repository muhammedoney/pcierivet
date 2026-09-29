// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Active companion: drives cq_np_req; monitor still samples credit/tag sideband.

class rivet_companion_driver extends uvm_driver #(rivet_companion_item);
  `uvm_component_utils(rivet_companion_driver)

  rivet_companion_vif vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rivet_companion_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_companion_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    rivet_companion_item req;
    vif.cq_np_req <= 2'b01;
    wait (vif.aresetn === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.aclk);
      vif.cq_np_req <= req.cq_np_req;
      seq_item_port.item_done();
    end
  endtask
endclass : rivet_companion_driver
