// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_axi_st_monitor extends uvm_monitor;
  `uvm_component_utils(rivet_axi_st_monitor)

  rivet_axi_st_vif vif;
  string           channel_name;
  uvm_analysis_port #(rivet_axi_st_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    channel_name = "cq";
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(rivet_axi_st_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_axi_st_vif not set")
    void'(uvm_config_db#(string)::get(this, "", "channel_name", channel_name));
  endfunction

  task run_phase(uvm_phase phase);
    rivet_axi_st_item item;
    wait (vif.aresetn === 1'b1);
    forever begin
      @(posedge vif.aclk);
      item = rivet_axi_st_item::type_id::create("axi_mon");
      item.channel = channel_name;
      item.tdata   = vif.tdata;
      item.tkeep   = vif.tkeep;
      item.tlast   = vif.tlast;
      item.tvalid  = vif.tvalid;
      item.tready  = vif.tready;
      item.tuser   = vif.tuser;
      ap.write(item);
    end
  endtask
endclass : rivet_axi_st_monitor
