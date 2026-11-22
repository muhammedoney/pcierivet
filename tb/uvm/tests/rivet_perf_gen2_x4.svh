// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 x4 performance tests. Scoreboard stays in L0 mode; the PERF line is the result.

// Payload sweep. peer_perf_rc must be set before the peer sends InitFC.
class perf_rq_sweep_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(perf_rq_sweep_gen2_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(null, "*", "peer_perf_rc", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_perf_rq_sweep_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_perf_rq_sweep_vseq::type_id::create("perf_rq_sweep");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_rq_sweep_gen2_x4


// MemWr64 payload sweep. Same peer performance mode as the MemWr32 sweep.
class perf_rq_memwr64_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(perf_rq_memwr64_gen2_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(null, "*", "peer_perf_rc", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_perf_rq_memwr64_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_perf_rq_memwr64_vseq::type_id::create("perf_rq_memwr64");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_rq_memwr64_gen2_x4


// 1DW MemRd32 and MemRd64, each answered with a 4-byte CplD.
class perf_rq_memrd_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(perf_rq_memrd_gen2_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "tlp_cpld_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_perf_rq_memrd_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_perf_rq_memrd_vseq::type_id::create("perf_rq_memrd");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_rq_memrd_gen2_x4


class perf_rq_memwr_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(perf_rq_memwr_gen2_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_perf_rq_memwr_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_perf_rq_memwr_vseq::type_id::create("perf_rq_memwr");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_rq_memwr_gen2_x4


class perf_rq_rc_lat_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(perf_rq_rc_lat_gen2_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "tlp_cpld_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_perf_rq_rc_lat_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_perf_rq_rc_lat_vseq::type_id::create("perf_rq_rc_lat");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_rq_rc_lat_gen2_x4


class perf_cq_cc_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(perf_cq_cc_gen2_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "tlp_memrd_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_perf_cq_cc_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_perf_cq_cc_vseq::type_id::create("perf_cq_cc");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_cq_cc_gen2_x4


class perf_credit_stall_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(perf_credit_stall_gen2_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_perf_credit_stall_vseq vseq;
    phase.raise_objection(this);
    vseq = rivet_perf_credit_stall_vseq::type_id::create("perf_credit");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_credit_stall_gen2_x4
