// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen3 x4: four TS1 blocks, no LTSSM. Lane number and rate ID must be captured.

class smoke_gen3_ts_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_gen3_ts_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "gen3_block_only", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "gen3_ts_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen3_ts_seq vseq;
    phase.raise_objection(this);
    vseq = rivet_gen3_ts_seq::type_id::create("gen3_ts_vseq");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_gen3_ts_x4
