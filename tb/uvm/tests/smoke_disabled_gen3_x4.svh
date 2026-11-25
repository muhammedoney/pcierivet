// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Link Disable from L0 at 8 GT/s and 16 GT/s.
// Upstream: the peer sets TS training-control bit 1.
// Downstream: the port originates the bit.

class smoke_disabled_gen3_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_disabled_gen3_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "disable_link_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen3_l0_vseq  l0;
    rivet_disabled_vseq dis;
    phase.raise_objection(this);
    l0  = rivet_gen3_l0_vseq::type_id::create("gen3_l0");
    dis = rivet_disabled_vseq::type_id::create("disabled");
    l0.start(env.vsqr);
    dis.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_disabled_gen3_x4

class smoke_disabled_gen3_rc_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_disabled_gen3_rc_x4)

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
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen3_l0_vseq  l0;
    rivet_dn_reset_vseq dis;
    phase.raise_objection(this);
    l0  = rivet_gen3_l0_vseq::type_id::create("gen3_l0");
    dis = rivet_dn_reset_vseq::type_id::create("disabled");
    dis.link_disable = 1'b1;
    l0.start(env.vsqr);
    dis.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_disabled_gen3_rc_x4

class smoke_disabled_gen4_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_disabled_gen4_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "disable_link_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen4_l0_vseq  l0;
    rivet_disabled_vseq dis;
    phase.raise_objection(this);
    l0  = rivet_gen4_l0_vseq::type_id::create("gen4_l0");
    dis = rivet_disabled_vseq::type_id::create("disabled");
    l0.start(env.vsqr);
    dis.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_disabled_gen4_x4

class smoke_disabled_gen4_rc_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_disabled_gen4_rc_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_upstream", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen4_l0_vseq  l0;
    rivet_dn_reset_vseq dis;
    phase.raise_objection(this);
    l0  = rivet_gen4_l0_vseq::type_id::create("gen4_l0");
    dis = rivet_dn_reset_vseq::type_id::create("disabled");
    dis.link_disable = 1'b1;
    l0.start(env.vsqr);
    dis.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_disabled_gen4_rc_x4
