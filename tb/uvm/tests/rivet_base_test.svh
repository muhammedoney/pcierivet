// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_base_test extends uvm_test;
  `uvm_component_utils(rivet_base_test)

  rivet_env env;
  int unsigned lanes = 1;
  int unsigned gen   = 2;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
    void'(uvm_config_db#(int unsigned)::get(this, "", "gen", gen));
    uvm_config_db#(int unsigned)::set(this, "env*", "lanes", lanes);
    env = rivet_env::type_id::create("env", this);
  endfunction

  // Shared Gen2 idle smoke used by smoke_gen2_x1/x2/x4.
  task run_idle_smoke(uvm_phase phase, int unsigned cycles = 40);
    rivet_idle_smoke_vseq vseq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(),
              $sformatf("Gen%0d x%0d idle smoke (%0d cycles)", gen, lanes, cycles), UVM_LOW)
    vseq = rivet_idle_smoke_vseq::type_id::create("idle_vseq");
    vseq.cycles = cycles;
    vseq.start(env.vsqr);
    #200ns;
    phase.drop_objection(this);
  endtask

  task run_phase(uvm_phase phase);
    run_idle_smoke(phase, 20);
  endtask
endclass : rivet_base_test
