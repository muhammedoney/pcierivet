// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// EP x4: Gen3 L0, then one RQ MemWr32 in a 128b/130b data block.

class smoke_gen3_memwr_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_gen3_memwr_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 3;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_gen3", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "dllp_fc_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "tlp_mode", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen3_l0_vseq     l0;
    rivet_tlp_rq_memwr_vseq wr;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Gen3 x4 MemWr32 after L0", UVM_LOW)
    l0 = rivet_gen3_l0_vseq::type_id::create("gen3_l0");
    wr = rivet_tlp_rq_memwr_vseq::type_id::create("memwr");
    l0.start(env.vsqr);
    wr.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_gen3_memwr_x4
