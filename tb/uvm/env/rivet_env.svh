// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_env extends uvm_env;
  `uvm_component_utils(rivet_env)

  rivet_pipe_agent    pipe_agent;
  rivet_axi_st_agent  cq_agent;
  rivet_axi_st_agent  cc_agent;
  rivet_axi_st_agent  rq_agent;
  rivet_axi_st_agent  rc_agent;
  rivet_scoreboard    scoreboard;
  rivet_coverage      coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    pipe_agent = rivet_pipe_agent::type_id::create("pipe_agent", this);
    cq_agent   = rivet_axi_st_agent::type_id::create("cq_agent", this);
    cc_agent   = rivet_axi_st_agent::type_id::create("cc_agent", this);
    rq_agent   = rivet_axi_st_agent::type_id::create("rq_agent", this);
    rc_agent   = rivet_axi_st_agent::type_id::create("rc_agent", this);
    scoreboard = rivet_scoreboard::type_id::create("scoreboard", this);
    coverage   = rivet_coverage::type_id::create("coverage", this);

    uvm_config_db#(string)::set(this, "cq_agent", "channel_name", "cq");
    uvm_config_db#(string)::set(this, "cc_agent", "channel_name", "cc");
    uvm_config_db#(string)::set(this, "rq_agent", "channel_name", "rq");
    uvm_config_db#(string)::set(this, "rc_agent", "channel_name", "rc");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    pipe_agent.ap.connect(scoreboard.pipe_imp);
  endfunction
endclass : rivet_env
