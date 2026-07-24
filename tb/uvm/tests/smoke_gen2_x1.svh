// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// First smoke: Gen2 x1. Next targets: smoke_gen2_x2, smoke_gen2_x4.

class smoke_gen2_x1 extends rivet_base_test;
  `uvm_component_utils(smoke_gen2_x1)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 1;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "", "gen", gen);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "smoke_gen2_x1: Phase 0 compile/elaborate smoke", UVM_LOW)
    #1000ns;
    phase.drop_objection(this);
  endtask
endclass : smoke_gen2_x1
