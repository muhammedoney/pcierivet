// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Phase 1: Gen2 AXI-ST agent for CQ/CC/RQ/RC.

class rivet_axi_st_agent extends uvm_agent;
  `uvm_component_utils(rivet_axi_st_agent)

  string                 channel_name;
  bit                    is_master;
  rivet_axi_st_driver    driver;
  rivet_axi_st_monitor   monitor;
  rivet_axi_st_sequencer sequencer;
  uvm_analysis_port #(rivet_axi_st_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    channel_name = "cq";
    is_master    = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(string)::get(this, "", "channel_name", channel_name));
    void'(uvm_config_db#(bit)::get(this, "", "is_master", is_master));
    // Propagate to children
    uvm_config_db#(string)::set(this, "*", "channel_name", channel_name);
    uvm_config_db#(bit)::set(this, "*", "is_master", is_master);

    monitor = rivet_axi_st_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = rivet_axi_st_sequencer::type_id::create("sequencer", this);
      driver    = rivet_axi_st_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = monitor.ap;
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass : rivet_axi_st_agent
