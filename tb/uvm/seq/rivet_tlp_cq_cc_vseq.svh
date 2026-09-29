// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// L0 + FC + BME/MSE, peer MemRd on PIPE, drive CC CplD for scoreboard match.

class rivet_tlp_cq_cc_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_tlp_cq_cc_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned fc_settle_cycles = 40_000;
  int unsigned post_cc_cycles  = 400;

  bit [7:0]  tag = 8'h23;
  bit [15:0] requester_id = 16'h0001;
  bit [31:0] data = 32'hA5A5_5A5A;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_tlp_cq_cc_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;
    bit          peer_done;
    rivet_axi_st_idle_seq   cq_rdy, rc_rdy, rq_idle;
    rivet_companion_grant_seq comp_grant;
    rivet_cfg_mgmt_rw_seq   cfg_rw;
    rivet_axi_cc_cpld_seq   cc_cpl;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")

    wait (status_vif.preset_n === 1'b1);
    prev = 6'h3F; reached = 1'b0;
    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h @%0d",
                            prev, status_vif.cfg_ltssm_state, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1; break;
      end
    end
    if (!reached)
      `uvm_fatal(get_type_name(), "Did not reach L0")

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);
    repeat (fc_settle_cycles) @(posedge status_vif.pclk);

    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    rq_idle    = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cc_cpl     = rivet_axi_cc_cpld_seq::type_id::create("cc_cpl");

    cq_rdy.cycles     = post_cc_cycles + 800;
    rc_rdy.cycles     = post_cc_cycles + 800;
    rq_idle.cycles    = post_cc_cycles + 800;
    comp_grant.cycles = post_cc_cycles + 800;

    cc_cpl.tag          = tag;
    cc_cpl.requester_id = requester_id;
    cc_cpl.completer_id = 16'h0100;
    cc_cpl.data         = data;
    cc_cpl.lower_addr   = 7'h10;

    fork
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        cfg_rw.start(p_sequencer.cfg_sqr);
        uvm_config_db#(bit)::set(null, "*", "peer_memrd_go", 1'b1);
        peer_done = 1'b0;
        for (cyc = 0; cyc < 80_000; cyc++) begin
          @(posedge status_vif.pclk);
          void'(uvm_config_db#(bit)::get(null, "*", "peer_tlp_memrd_done", peer_done));
          if (peer_done) break;
        end
        if (!peer_done)
          `uvm_fatal(get_type_name(), "Peer did not inject MemRd TLP")
        repeat (64) @(posedge status_vif.pclk);
        cc_cpl.start(p_sequencer.cc_sqr);
        repeat (post_cc_cycles) @(posedge status_vif.pclk);
      end
    join

    `uvm_info(get_type_name(), "CQ-CC vseq complete", UVM_LOW)
  endtask
endclass : rivet_tlp_cq_cc_vseq
