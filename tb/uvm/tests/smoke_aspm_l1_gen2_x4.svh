// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 x4: L0 → EIOS → L1.Entry → L1.Idle (P1) → Detect.Quiet → L0 (forced aspm_l1_req).

class smoke_aspm_l1_gen2_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_aspm_l1_gen2_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_aspm_vseq vseq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Gen2 x4 ASPM L1 round-trip", UVM_LOW)
    vseq = rivet_aspm_vseq::type_id::create("aspm_l1_vseq");
    vseq.l1_mode = 1'b1;
    vseq.start(env.vsqr);
    phase.drop_objection(this);
  endtask
endclass : smoke_aspm_l1_gen2_x4
