// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 x1: cfg_mgmt Vendor/Device stable read + Command RMW.

class smoke_cfg_mgmt_gen2_x1 extends rivet_base_test;
  `uvm_component_utils(smoke_cfg_mgmt_gen2_x1)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 1;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "cfg_mgmt_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_cfg_mgmt_vseq vseq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Gen2 x1 cfg_mgmt R/W smoke", UVM_LOW)
    vseq = rivet_cfg_mgmt_vseq::type_id::create("cfg_vseq");
    vseq.start(env.vsqr);
    #200ns;
    phase.drop_objection(this);
  endtask
endclass : smoke_cfg_mgmt_gen2_x1
