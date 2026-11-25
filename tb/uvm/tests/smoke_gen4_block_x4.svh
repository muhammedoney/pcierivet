// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen4 x4: two 16-byte blocks on a 64-bit pipe, no LTSSM.
// One block starts at rxstart_block 2'b10. Headers return on TX start.

class smoke_gen4_block_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_gen4_block_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "gen3_block_only", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "gen4_block_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen4_block_seq vseq;
    phase.raise_objection(this);
    vseq = rivet_gen4_block_seq::type_id::create("gen4_block_vseq");
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_gen4_block_x4
