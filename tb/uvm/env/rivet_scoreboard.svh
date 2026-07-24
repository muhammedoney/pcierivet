// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Empty scoreboard stub — implement checks in Phase 1+.

class rivet_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rivet_scoreboard)

  uvm_analysis_imp #(rivet_pipe_item, rivet_scoreboard) pipe_imp;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    pipe_imp = new("pipe_imp", this);
  endfunction

  function void write(rivet_pipe_item t);
    // Phase 0: no checks yet
  endfunction
endclass : rivet_scoreboard
