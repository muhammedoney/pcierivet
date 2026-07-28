// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// is_master=1: app->core (CC/RQ). is_master=0: core->app (CQ/RC), drive tready.

class rivet_axi_st_driver extends uvm_driver #(rivet_axi_st_item);
  `uvm_component_utils(rivet_axi_st_driver)

  rivet_axi_st_vif vif;
  bit              is_master;
  string           channel_name;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    is_master    = 0;
    channel_name = "cq";
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rivet_axi_st_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_axi_st_vif not set")
    void'(uvm_config_db#(bit)::get(this, "", "is_master", is_master));
    void'(uvm_config_db#(string)::get(this, "", "channel_name", channel_name));
  endfunction

  task run_phase(uvm_phase phase);
    rivet_axi_st_item req;
    drive_reset_idle();
    wait (vif.aresetn === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_reset_idle();
    if (is_master) begin
      vif.tdata  <= '0;
      vif.tkeep  <= '0;
      vif.tlast  <= 1'b0;
      vif.tvalid <= 1'b0;
      vif.tuser  <= '0;
    end else begin
      vif.tready <= 4'hF;
    end
  endtask

  task drive_item(rivet_axi_st_item req);
    @(posedge vif.aclk);
    if (is_master) begin
      vif.tdata  <= req.tdata;
      vif.tkeep  <= req.tkeep;
      vif.tlast  <= req.tlast;
      vif.tvalid <= req.tvalid;
      vif.tuser  <= req.tuser;
    end else begin
      vif.tready <= req.tready;
    end
  endtask
endclass : rivet_axi_st_driver
