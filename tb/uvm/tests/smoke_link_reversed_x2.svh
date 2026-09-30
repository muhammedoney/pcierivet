// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2: DUT ×2, peer assigns reversed Lane# (1,0) → L0 @ width 2.

class smoke_link_reversed_x2 extends rivet_base_test;
  `uvm_component_utils(smoke_link_reversed_x2)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 2;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(int unsigned)::set(this, "*", "peer_lanes", 2);
    uvm_config_db#(bit)::set(this, "*", "peer_lane_reverse", 1'b1);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_linkwidth_narrow_vseq vseq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Gen2 DUT x2 / peer lane-reversed train", UVM_LOW)
    vseq = rivet_linkwidth_narrow_vseq::type_id::create("rev_vseq");
    vseq.expect_width = 2;
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_link_reversed_x2
