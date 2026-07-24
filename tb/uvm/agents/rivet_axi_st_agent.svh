// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_axi_st_agent extends uvm_agent;
  `uvm_component_utils(rivet_axi_st_agent)

  string channel_name;
  uvm_analysis_port #(rivet_axi_st_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    channel_name = "cq";
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(string)::get(this, "", "channel_name", channel_name));
    ap = new("ap", this);
  endfunction
endclass : rivet_axi_st_agent
