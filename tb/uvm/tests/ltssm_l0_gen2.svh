// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Questa UVM: Gen2 LTSSM Detect -> L0 (Downstream PIPE peer).

class ltssm_l0_gen2_x1 extends rivet_base_test;
  `uvm_component_utils(ltssm_l0_gen2_x1)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    run_ltssm_l0(phase);
  endtask
endclass : ltssm_l0_gen2_x1

class ltssm_l0_gen2_x2 extends rivet_base_test;
  `uvm_component_utils(ltssm_l0_gen2_x2)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    run_ltssm_l0(phase);
  endtask
endclass : ltssm_l0_gen2_x2

class ltssm_l0_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(ltssm_l0_gen2_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    run_ltssm_l0(phase);
  endtask
endclass : ltssm_l0_gen2_x4
