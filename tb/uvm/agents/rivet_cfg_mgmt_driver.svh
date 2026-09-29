// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// PG213 cfg_mgmt: hold read/write until read_write_done, then sample read_data.

class rivet_cfg_mgmt_driver extends uvm_driver #(rivet_cfg_mgmt_item);
  `uvm_component_utils(rivet_cfg_mgmt_driver)

  rivet_cfg_mgmt_vif vif;
  int unsigned       done_timeout_cycles = 2000;

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
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_item(rivet_cfg_mgmt_item req);
    int unsigned waited;
    @(posedge vif.aclk);
    vif.addr            <= req.addr;
    vif.function_number <= req.function_number;
    vif.write_data      <= req.write_data;
    vif.byte_enable     <= req.byte_enable;
    vif.debug_access    <= req.debug_access;
    vif.write           <= req.write;
    vif.read            <= req.read;

    if (!(req.read || req.write))
      return;

    waited = 0;
    while (vif.read_write_done !== 1'b1) begin
      @(posedge vif.aclk);
      waited++;
      if (waited > done_timeout_cycles)
        `uvm_fatal(get_type_name(),
          $sformatf("cfg_mgmt timeout waiting for done (addr=0x%0h r=%0b w=%0b)",
                    req.addr, req.read, req.write))
    end

    req.read_data       = vif.read_data;
    req.read_write_done = 1'b1;

    // Drop request; hold address idle for one cycle after done.
    vif.write <= 1'b0;
    vif.read  <= 1'b0;
    @(posedge vif.aclk);
    drive_idle();
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
