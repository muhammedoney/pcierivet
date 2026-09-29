// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Phase 1 coverage: PIPE idle + cfg_mgmt txn + AXI channel activity.

class rivet_coverage extends uvm_component;
  `uvm_component_utils(rivet_coverage)

  uvm_analysis_imp_pipe #(rivet_pipe_item, rivet_coverage)     pipe_imp;
  uvm_analysis_imp_cfg  #(rivet_cfg_mgmt_item, rivet_coverage) cfg_imp;
  uvm_analysis_imp_axi  #(rivet_axi_st_item, rivet_coverage)   axi_imp;
  uvm_analysis_imp_dllp #(rivet_dllp_item, rivet_coverage)     dllp_imp;

  int unsigned lanes = 1;
  bit          cg_txelecidle;
  bit [1:0]    cg_powerdown;
  bit [2:0]    cg_rate;

  bit          cg_cfg_read;
  bit          cg_cfg_write;
  bit [9:0]    cg_cfg_addr;
  bit [3:0]    cg_cfg_be;

  bit [1:0]    cg_axi_ch_id; // 0=cq 1=cc 2=rq 3=rc
  bit          cg_axi_valid;
  bit          cg_axi_last;

  bit          cg_dllp_from_dut;
  bit [3:0]    cg_dllp_fc_kind;

  covergroup cg_pipe_idle;
    option.per_instance = 1;
    cp_lanes: coverpoint lanes { bins x1 = {1}; bins x2 = {2}; bins x4 = {4}; }
    cp_txei:  coverpoint cg_txelecidle;
    cp_pd:    coverpoint cg_powerdown { bins p1 = {2'b10}; }
    cp_rate:  coverpoint cg_rate { bins gen2 = {3'd1}; }
  endgroup

  covergroup cg_cfg_mgmt;
    option.per_instance = 1;
    cp_rd: coverpoint cg_cfg_read { bins pulse = {1}; }
    cp_wr: coverpoint cg_cfg_write { bins pulse = {1}; }
    cp_addr: coverpoint cg_cfg_addr {
      bins id      = {10'h000};
      bins cmd_sts = {10'h001};
      bins other   = default;
    }
    cp_be: coverpoint cg_cfg_be {
      bins full   = {4'hF};
      bins cmd_lo = {4'b0011};
      bins other  = default;
    }
  endgroup

  covergroup cg_axi_activity;
    option.per_instance = 1;
    cp_ch: coverpoint cg_axi_ch_id {
      bins cq = {2'd0};
      bins cc = {2'd1};
      bins rq = {2'd2};
      bins rc = {2'd3};
    }
    cp_valid: coverpoint cg_axi_valid;
    cp_last:  coverpoint cg_axi_last;
  endgroup


  covergroup cg_dllp_fc;
    option.per_instance = 1;
    cp_src: coverpoint cg_dllp_from_dut { bins dut = {1}; bins peer = {0}; }
    cp_kind: coverpoint cg_dllp_fc_kind {
      bins init1_p   = {4'h4};
      bins init1_np  = {4'h5};
      bins init1_cpl = {4'h6};
      bins upd_p     = {4'h8};
      bins upd_np    = {4'h9};
      bins upd_cpl   = {4'hA};
      bins init2_p   = {4'hC};
      bins init2_np  = {4'hD};
      bins init2_cpl = {4'hE};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_pipe_idle    = new();
    cg_cfg_mgmt     = new();
    cg_axi_activity = new();
    cg_dllp_fc      = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    pipe_imp = new("pipe_imp", this);
    cfg_imp  = new("cfg_imp", this);
    axi_imp  = new("axi_imp", this);
    dllp_imp = new("dllp_imp", this);
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
  endfunction

  function void write_pipe(rivet_pipe_item t);
    cg_txelecidle = t.txelecidle;
    cg_powerdown  = t.powerdown;
    cg_rate       = t.rate;
    cg_pipe_idle.sample();
  endfunction

  function void write_cfg(rivet_cfg_mgmt_item t);
    if (!t.txn_complete) return;
    cg_cfg_read  = t.read;
    cg_cfg_write = t.write;
    cg_cfg_addr  = t.addr;
    cg_cfg_be    = t.byte_enable;
    cg_cfg_mgmt.sample();
  endfunction

  function void write_axi(rivet_axi_st_item t);
    if (!t.tvalid) return;
    case (t.channel)
      "cq": cg_axi_ch_id = 2'd0;
      "cc": cg_axi_ch_id = 2'd1;
      "rq": cg_axi_ch_id = 2'd2;
      "rc": cg_axi_ch_id = 2'd3;
      default: cg_axi_ch_id = 2'd0;
    endcase
    cg_axi_valid = t.tvalid;
    cg_axi_last  = t.tlast;
    cg_axi_activity.sample();
  endfunction

  function void write_dllp(rivet_dllp_item t);
    if (!t.is_fc || !t.crc_ok) return;
    cg_dllp_from_dut = t.from_dut;
    cg_dllp_fc_kind  = t.fc_kind;
    cg_dllp_fc.sample();
  endfunction
endclass : rivet_coverage
