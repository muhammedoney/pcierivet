// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_env extends uvm_env;
  `uvm_component_utils(rivet_env)

  rivet_pipe_agent         pipe_agent;
  rivet_axi_st_agent       cq_agent, cc_agent, rq_agent, rc_agent;
  rivet_cfg_mgmt_agent     cfg_agent;
  rivet_companion_monitor  companion_mon;
  rivet_virtual_sequencer  vsqr;
  rivet_scoreboard         scoreboard;
  rivet_coverage           coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    uvm_config_db#(string)::set(this, "cq_agent*", "channel_name", "cq");
    uvm_config_db#(string)::set(this, "cc_agent*", "channel_name", "cc");
    uvm_config_db#(string)::set(this, "rq_agent*", "channel_name", "rq");
    uvm_config_db#(string)::set(this, "rc_agent*", "channel_name", "rc");
    uvm_config_db#(bit)::set(this, "cq_agent*", "is_master", 1'b0);
    uvm_config_db#(bit)::set(this, "rc_agent*", "is_master", 1'b0);
    uvm_config_db#(bit)::set(this, "cc_agent*", "is_master", 1'b1);
    uvm_config_db#(bit)::set(this, "rq_agent*", "is_master", 1'b1);

    pipe_agent    = rivet_pipe_agent::type_id::create("pipe_agent", this);
    cq_agent      = rivet_axi_st_agent::type_id::create("cq_agent", this);
    cc_agent      = rivet_axi_st_agent::type_id::create("cc_agent", this);
    rq_agent      = rivet_axi_st_agent::type_id::create("rq_agent", this);
    rc_agent      = rivet_axi_st_agent::type_id::create("rc_agent", this);
    cfg_agent     = rivet_cfg_mgmt_agent::type_id::create("cfg_agent", this);
    companion_mon = rivet_companion_monitor::type_id::create("companion_mon", this);
    vsqr          = rivet_virtual_sequencer::type_id::create("vsqr", this);
    scoreboard    = rivet_scoreboard::type_id::create("scoreboard", this);
    coverage      = rivet_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    vsqr.pipe_sqr = pipe_agent.sequencer;
    vsqr.cq_sqr   = cq_agent.sequencer;
    vsqr.cc_sqr   = cc_agent.sequencer;
    vsqr.rq_sqr   = rq_agent.sequencer;
    vsqr.rc_sqr   = rc_agent.sequencer;
    vsqr.cfg_sqr  = cfg_agent.sequencer;

    pipe_agent.ap.connect(scoreboard.pipe_imp);
    pipe_agent.ap.connect(coverage.pipe_imp);
    cq_agent.ap.connect(scoreboard.axi_imp);
    cc_agent.ap.connect(scoreboard.axi_imp);
    rq_agent.ap.connect(scoreboard.axi_imp);
    rc_agent.ap.connect(scoreboard.axi_imp);
    cfg_agent.ap.connect(scoreboard.cfg_imp);
    companion_mon.ap.connect(scoreboard.comp_imp);
  endfunction
endclass : rivet_env
