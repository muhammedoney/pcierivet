// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(rivet_virtual_sequencer)

  rivet_pipe_sequencer     pipe_sqr;
  rivet_axi_st_sequencer   cq_sqr;
  rivet_axi_st_sequencer   cc_sqr;
  rivet_axi_st_sequencer   rq_sqr;
  rivet_axi_st_sequencer   rc_sqr;
  rivet_cfg_mgmt_sequencer cfg_sqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : rivet_virtual_sequencer
