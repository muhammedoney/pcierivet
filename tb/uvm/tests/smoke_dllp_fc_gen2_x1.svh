// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 x1: L0 + peer InitFC/UpdateFC over PIPE; scoreboard checks DUT FC DLLPs.

class smoke_dllp_fc_gen2_x1 extends rivet_base_test;
  `uvm_component_utils(smoke_dllp_fc_gen2_x1)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 1;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.dllp_mon", "dllp_mon_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "dllp_fc_mode", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_dllp_fc_vseq vseq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Gen2 x1 DLLP FC after L0", UVM_LOW)
    vseq = rivet_dllp_fc_vseq::type_id::create("dllp_fc_vseq");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_dllp_fc_gen2_x1
