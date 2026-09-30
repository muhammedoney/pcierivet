// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2: DUT ×4 port, peer offers ×1 → negotiate width 1 and reach L0.

class smoke_linkwidth_peer_x1_dut_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_linkwidth_peer_x1_dut_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(int unsigned)::set(this, "*", "peer_lanes", 1);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_linkwidth_narrow_vseq vseq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Gen2 DUT x4 / peer x1 link-width negotiate", UVM_LOW)
    vseq = rivet_linkwidth_narrow_vseq::type_id::create("linkwidth_vseq");
    vseq.expect_width = 1;
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_linkwidth_peer_x1_dut_x4
