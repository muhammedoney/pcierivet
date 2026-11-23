// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// DSP is a Downstream port: Type 1 header, and it does not accept a config
// RQ descriptor. Link training is the PG213 Endpoint bench with MODE=DSP.
// Compile with RIVET_TB_MODE=3.

class ltssm_l0_gen2_dsp_x4 extends rivet_base_test;
  `uvm_component_utils(ltssm_l0_gen2_dsp_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 2;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b0);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "cfg_mgmt_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_cfg_type1_vseq  hdr;
    rivet_cfg_mgmt_rw_seq bme;
    rivet_link_status_vif status_vif;
    int unsigned guard;
    phase.raise_objection(this);
    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")
    hdr = rivet_cfg_type1_vseq::type_id::create("dsp_hdr");
    bme = rivet_cfg_mgmt_rw_seq::type_id::create("dsp_bme");
    hdr.start(env.vsqr);
    bme.start(env.vsqr.cfg_sqr);
    status_vif.rq_stall_done = 1'b0;
    status_vif.rq_stall_go   = 1'b1;
    guard = 0;
    while ((status_vif.rq_stall_done !== 1'b1) && (guard < 10000)) begin
      @(posedge status_vif.pclk);
      guard++;
    end
    status_vif.rq_stall_go = 1'b0;
    if (status_vif.rq_stall_done !== 1'b1 || status_vif.rq_stall_pass !== 1'b1)
      `uvm_error(get_type_name(), "DSP accepted a config RQ beat or the check timed out")
    else
      `uvm_info(get_type_name(), "DSP held RQ tready low for CfgWr1", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass : ltssm_l0_gen2_dsp_x4
