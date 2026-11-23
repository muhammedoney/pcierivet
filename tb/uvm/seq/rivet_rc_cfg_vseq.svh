// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// RC requester packs CfgWr1 / CfgRd1 / CfgRd0. The wire header is checked on
// rivet_tl_rq. The PG213 Endpoint bench is the link-level proof.

class rivet_rc_cfg_seq extends uvm_sequence #(rivet_axi_st_item);
  `uvm_object_utils(rivet_rc_cfg_seq)

  function new(string name = "rivet_rc_cfg_seq");
    super.new(name);
  endfunction

  task send_beat(logic [63:0] tdata, bit tlast, logic [87:0] tuser);
    rivet_axi_st_item item;
    item = rivet_axi_st_item::type_id::create("rq_beat");
    start_item(item);
    item.channel = "rq";
    item.tdata   = tdata;
    item.tkeep   = 2'b11;
    item.tlast   = tlast;
    item.tvalid  = 1'b1;
    item.tuser   = tuser;
    item.tready  = 4'hF;
    finish_item(item);
  endtask

  task send_cfg(bit [3:0] req, bit [7:0] tag, bit [15:0] completer,
                bit [9:0] reg_dw, bit has_data, bit [31:0] data, bit [7:0] exp_b0);
    logic [63:0] b0, b1, b2;
    logic [87:0] u;
    logic [31:0] addr;
    rivet_link_status_vif status_vif;
    int unsigned guard;
    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")
    addr = {20'h0, reg_dw, 2'b00};
    rivet_axi_tlp_util::pack_mem_desc_2beat(addr, 11'd1, req, tag, completer, b0, b1);
    // Completer ID sits at beat1[55:40], not in the memory requester-id field.
    b1[55:40] = completer;
    u = rivet_axi_tlp_util::rq_tuser(4'hF, 4'h0);
    status_vif.rq_watch_arm = 1'b0;
    @(posedge status_vif.pclk);
    status_vif.rq_watch_b0  = exp_b0;
    status_vif.rq_watch_arm = 1'b1;
    send_beat(b0, 1'b0, u);
    send_beat(b1, !has_data, u);
    if (has_data) begin
      b2 = {32'h0, data};
      send_beat(b2, 1'b1, u);
    end
    guard = 0;
    while ((status_vif.rq_watch_hit !== 1'b1) && (guard < 2000)) begin
      @(posedge status_vif.pclk);
      guard++;
    end
    status_vif.rq_watch_arm = 1'b0;
    if (status_vif.rq_watch_hit !== 1'b1)
      `uvm_error(get_type_name(),
        $sformatf("req %0h did not produce wire byte0 0x%02h", req, exp_b0))
    else
      `uvm_info(get_type_name(),
        $sformatf("req %0h wire byte0 0x%02h", req, exp_b0), UVM_LOW)
  endtask

  task body();
    send_cfg(rivet_pkg::RIVET_RQ_REQ_CFGWR1, 8'h01, 16'h0100, 10'd1, 1'b1,
             32'hA5A5_0001, rivet_pkg::RIVET_TLP_B0_CFGWR1);
    send_cfg(rivet_pkg::RIVET_RQ_REQ_CFGRD1, 8'h02, 16'h0100, 10'd1, 1'b0,
             32'h0, rivet_pkg::RIVET_TLP_B0_CFGRD1);
    send_cfg(rivet_pkg::RIVET_RQ_REQ_CFGRD0, 8'h03, 16'h0000, 10'd0, 1'b0,
             32'h0, rivet_pkg::RIVET_TLP_B0_CFGRD0);
    send_cfg(rivet_pkg::RIVET_RQ_REQ_CFGWR0, 8'h04, 16'h0000, 10'd1, 1'b1,
             32'h0000_0006, rivet_pkg::RIVET_TLP_B0_CFGWR0);
  endtask
endclass : rivet_rc_cfg_seq

class rivet_rc_cfg_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_rc_cfg_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  function new(string name = "rivet_rc_cfg_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_pipe_idle_seq       pipe_idle;
    rivet_axi_st_idle_seq     cc_idle, cq_rdy, rc_rdy;
    rivet_companion_grant_seq comp_grant;
    rivet_cfg_mgmt_rw_seq     cfg_rw;
    rivet_rc_cfg_seq          rq;

    pipe_idle  = rivet_pipe_idle_seq::type_id::create("pipe_idle");
    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_bme");
    rq         = rivet_rc_cfg_seq::type_id::create("rc_cfg");
    pipe_idle.cycles  = 20000;
    cc_idle.cycles    = 20000;
    cq_rdy.cycles     = 20000;
    rc_rdy.cycles     = 20000;
    comp_grant.cycles = 20000;

    fork
      pipe_idle.start(p_sequencer.pipe_sqr);
      cc_idle.start(p_sequencer.cc_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        cfg_rw.start(p_sequencer.cfg_sqr);
        rq.start(p_sequencer.rq_sqr);
      end
    join
  endtask
endclass : rivet_rc_cfg_vseq
