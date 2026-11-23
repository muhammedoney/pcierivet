// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// RC completer UR. Compile with RIVET_TB_MODE=1.

class smoke_cfg_ur_gen2_rc_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_cfg_ur_gen2_rc_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b0);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_cfg_ur_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_cfg_ur_vseq::type_id::create("cfg_ur_vseq");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_cfg_ur_gen2_rc_x4
