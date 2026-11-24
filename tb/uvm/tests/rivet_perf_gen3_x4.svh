// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen3 x4 posted-write sweep. Same PERF line as the Gen2 sweep, after L0 at 8 GT/s.

class perf_rq_sweep_gen3_x4 extends rivet_base_test;
  `uvm_component_utils(perf_rq_sweep_gen3_x4)

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
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(null, "*", "peer_perf_rc", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen3_l0_vseq       l0;
    rivet_perf_rq_sweep_vseq sweep;
    phase.raise_objection(this);
    l0    = rivet_gen3_l0_vseq::type_id::create("gen3_l0");
    sweep = rivet_perf_rq_sweep_vseq::type_id::create("perf_rq_sweep");
    l0.start(env.vsqr);
    sweep.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : perf_rq_sweep_gen3_x4
