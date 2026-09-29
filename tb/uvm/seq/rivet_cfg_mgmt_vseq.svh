// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// cfg_mgmt R/W smoke vseq: keep AXI quiet + PIPE idle while exercising cfg.

class rivet_cfg_mgmt_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_cfg_mgmt_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned axi_idle_cycles = 80;

  function new(string name = "rivet_cfg_mgmt_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_pipe_idle_seq     pipe_idle;
    rivet_axi_st_idle_seq   cc_idle, rq_idle, cq_rdy, rc_rdy;
    rivet_cfg_mgmt_rw_seq   cfg_rw;
    rivet_companion_grant_seq comp_grant;

    pipe_idle  = rivet_pipe_idle_seq::type_id::create("pipe_idle");
    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle    = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");

    pipe_idle.cycles = axi_idle_cycles;
    cc_idle.cycles   = axi_idle_cycles;
    rq_idle.cycles   = axi_idle_cycles;
    cq_rdy.cycles    = axi_idle_cycles;
    rc_rdy.cycles    = axi_idle_cycles;
    comp_grant.cycles = axi_idle_cycles;

    fork
      pipe_idle.start(p_sequencer.pipe_sqr);
      cc_idle.start(p_sequencer.cc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        cfg_rw.start(p_sequencer.cfg_sqr);
      end
    join
  endtask
endclass : rivet_cfg_mgmt_vseq
