// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Shared Gen2 idle smoke: PIPE PHY idle + AXI quiet + cfg_mgmt idle.

class rivet_idle_smoke_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_idle_smoke_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned cycles = 40;

  function new(string name = "rivet_idle_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_pipe_idle_seq      pipe_idle;
    rivet_axi_st_idle_seq    cc_idle, rq_idle, cq_rdy, rc_rdy;
    rivet_cfg_mgmt_idle_seq  cfg_idle;

    pipe_idle = rivet_pipe_idle_seq::type_id::create("pipe_idle");
    cc_idle   = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle   = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy    = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy    = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    cfg_idle  = rivet_cfg_mgmt_idle_seq::type_id::create("cfg_idle");
    pipe_idle.cycles = cycles;
    cc_idle.cycles   = cycles;
    rq_idle.cycles   = cycles;
    cq_rdy.cycles    = cycles;
    rc_rdy.cycles    = cycles;
    cfg_idle.cycles  = cycles;

    fork
      pipe_idle.start(p_sequencer.pipe_sqr);
      cc_idle.start(p_sequencer.cc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      cfg_idle.start(p_sequencer.cfg_sqr);
    join
  endtask
endclass : rivet_idle_smoke_vseq
