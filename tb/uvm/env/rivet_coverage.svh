// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Phase 1 coverage: lanes + PIPE idle stub fields (grow with LTSSM).

class rivet_coverage extends uvm_component;
  `uvm_component_utils(rivet_coverage)

  uvm_analysis_imp_pipe #(rivet_pipe_item, rivet_coverage) pipe_imp;

  int unsigned lanes = 1;
  bit          cg_txelecidle;
  bit [1:0]    cg_powerdown;
  bit [2:0]    cg_rate;

  covergroup cg_pipe_idle;
    option.per_instance = 1;
    cp_lanes: coverpoint lanes { bins x1 = {1}; bins x2 = {2}; bins x4 = {4}; }
    cp_txei:  coverpoint cg_txelecidle;
    cp_pd:    coverpoint cg_powerdown { bins p1 = {2'b10}; }
    cp_rate:  coverpoint cg_rate { bins gen2 = {3'd1}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_pipe_idle = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    pipe_imp = new("pipe_imp", this);
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
  endfunction

  function void write_pipe(rivet_pipe_item t);
    cg_txelecidle = t.txelecidle;
    cg_powerdown  = t.powerdown;
    cg_rate       = t.rate;
    cg_pipe_idle.sample();
  endfunction
endclass : rivet_coverage
