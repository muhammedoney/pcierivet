// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 x2 / x4 idle smokes — compile with +define+RIVET_TB_LANES=N.

class smoke_gen2_x2 extends rivet_base_test;
  `uvm_component_utils(smoke_gen2_x2)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 2;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    run_idle_smoke(phase, 40);
  endtask
endclass : smoke_gen2_x2

class smoke_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_gen2_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    run_idle_smoke(phase, 40);
  endtask
endclass : smoke_gen2_x4
