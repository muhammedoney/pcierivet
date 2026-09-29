// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// L0 + FC + BME, RQ MemRd, peer CplD on PIPE, scoreboard RQ-RC match.

class rivet_tlp_rq_rc_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_tlp_rq_rc_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned fc_settle_cycles = 40_000;
  int unsigned post_cycles     = 800;

  bit [7:0]  tag = 8'h11;
  bit [15:0] requester_id = 16'h0100;
  bit [31:0] addr = 32'h0000_1000;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_tlp_rq_rc_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;
    bit          peer_done;
    rivet_axi_st_idle_seq     cq_rdy, rc_rdy, cc_idle;
    rivet_companion_grant_seq comp_grant;
    rivet_cfg_mgmt_rw_seq     cfg_rw;
    rivet_axi_rq_memrd32_seq  rq_rd;

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
    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    rq_rd      = rivet_axi_rq_memrd32_seq::type_id::create("rq_rd");

    cq_rdy.cycles     = post_cycles + 400;
    rc_rdy.cycles     = post_cycles + 400;
    cc_idle.cycles    = post_cycles + 400;
    comp_grant.cycles = post_cycles + 400;

    rq_rd.addr = addr;
    rq_rd.tag  = tag;
    rq_rd.requester_id = requester_id;

    fork
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      cc_idle.start(p_sequencer.cc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        cfg_rw.start(p_sequencer.cfg_sqr);
        rq_rd.start(p_sequencer.rq_sqr);
        repeat (200) @(posedge status_vif.pclk);
        uvm_config_db#(bit)::set(null, "*", "peer_cpld_go", 1'b1);
        peer_done = 1'b0;
        for (cyc = 0; cyc < 80_000; cyc++) begin
          @(posedge status_vif.pclk);
          void'(uvm_config_db#(bit)::get(null, "*", "peer_tlp_cpld_done", peer_done));
          if (peer_done) break;
        end
        if (!peer_done)
          `uvm_fatal(get_type_name(), "Peer did not inject CplD TLP")
        repeat (post_cycles) @(posedge status_vif.pclk);
      end
    join

    `uvm_info(get_type_name(), "RQ-RC vseq complete", UVM_LOW)
  endtask
endclass : rivet_tlp_rq_rc_vseq
