// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Phase 0: agent skeleton (driver/monitor filled in Phase 1).

class rivet_pipe_agent extends uvm_agent;
  `uvm_component_utils(rivet_pipe_agent)

  uvm_analysis_port #(rivet_pipe_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction
endclass : rivet_pipe_agent
