// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// RC x4: Gen3 L0, one RQ MemRd, one peer CplD. Compile with RIVET_TB_MODE=1.

class smoke_gen3_cpld_rc_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_gen3_cpld_rc_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 3;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_gen3", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_upstream", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "tlp_cpld_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "tlp_mode", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "tlp_require_rc", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen3_l0_vseq   l0;
    rivet_tlp_rq_rc_vseq rc;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "RC Gen3 x4 CplD after L0", UVM_LOW)
    l0 = rivet_gen3_l0_vseq::type_id::create("gen3_l0");
    rc = rivet_tlp_rq_rc_vseq::type_id::create("rq_rc");
    l0.start(env.vsqr);
    rc.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_gen3_cpld_rc_x4
