// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Companion agent: active grant driver + passive sideband monitor.

class rivet_companion_agent extends uvm_agent;
  `uvm_component_utils(rivet_companion_agent)

  rivet_companion_driver    driver;
  rivet_companion_monitor   monitor;
  rivet_companion_sequencer sequencer;
  uvm_analysis_port #(rivet_companion_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = rivet_companion_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = rivet_companion_sequencer::type_id::create("sequencer", this);
      driver    = rivet_companion_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = monitor.ap;
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass : rivet_companion_agent
