// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// First smoke: Gen2 x1 — PIPE + AXI-ST idle against controller stub.

class smoke_gen2_x1 extends rivet_base_test;
  `uvm_component_utils(smoke_gen2_x1)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 1;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_pipe_idle_seq   pipe_idle;
    rivet_axi_st_idle_seq cc_idle;
    rivet_axi_st_idle_seq rq_idle;
    rivet_axi_st_idle_seq cq_rdy;
    rivet_axi_st_idle_seq rc_rdy;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "smoke_gen2_x1: Gen2 x1 PIPE+AXI idle smoke", UVM_LOW)

    pipe_idle = rivet_pipe_idle_seq::type_id::create("pipe_idle");
    cc_idle   = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle   = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy    = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy    = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    pipe_idle.cycles = 40;
    cc_idle.cycles   = 40;
    rq_idle.cycles   = 40;
    cq_rdy.cycles    = 40;
    rc_rdy.cycles    = 40;

    fork
      pipe_idle.start(env.pipe_agent.sequencer);
      cc_idle.start(env.cc_agent.sequencer);
      rq_idle.start(env.rq_agent.sequencer);
      cq_rdy.start(env.cq_agent.sequencer);
      rc_rdy.start(env.rc_agent.sequencer);
    join

    #200ns;
    phase.drop_objection(this);
  endtask
endclass : smoke_gen2_x1
