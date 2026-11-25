// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// EP x4: Gen1 L0, Gen2 L0, Gen3 L0, then a second EQ and L0 at 16 GT/s.

class smoke_gen4_l0_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_gen4_l0_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 4;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_gen4", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen4_l0_vseq vseq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Gen4 x4 L0 through a second equalization", UVM_LOW)
    vseq = rivet_gen4_l0_vseq::type_id::create("gen4_l0_vseq");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_gen4_l0_x4
