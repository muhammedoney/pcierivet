// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// USP trains with the Downstream PIPE peer and keeps the Type 0 header.
// Compile with RIVET_TB_MODE=2.

class ltssm_l0_gen2_usp_x4 extends rivet_base_test;
  `uvm_component_utils(ltssm_l0_gen2_usp_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "cfg_mgmt_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_cfg_mgmt_after_l0_vseq l0;
    rivet_cfg_header_seq         hdr;
    phase.raise_objection(this);
    l0 = rivet_cfg_mgmt_after_l0_vseq::type_id::create("usp_l0");
    hdr = rivet_cfg_header_seq::type_id::create("usp_hdr");
    hdr.exp_class = 24'h120000;
    hdr.exp_hdr   = 8'h00;
    l0.start(env.vsqr);
    hdr.start(env.vsqr.cfg_sqr);
    phase.drop_objection(this);
  endtask
endclass : ltssm_l0_gen2_usp_x4
