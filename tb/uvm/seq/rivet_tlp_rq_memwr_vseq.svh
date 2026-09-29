// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Reach L0, settle FC, enable Bus Master via cfg_mgmt, drive one RQ MemWr32.

class rivet_tlp_rq_memwr_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_tlp_rq_memwr_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned fc_settle_cycles = 40_000;
  int unsigned post_rq_cycles  = 200;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_tlp_rq_memwr_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;
    rivet_axi_st_idle_seq   cc_idle, cq_rdy, rc_rdy;
    rivet_companion_grant_seq comp_grant;
    rivet_cfg_mgmt_rw_seq   cfg_rw;
    rivet_axi_rq_memwr32_seq rq_wr;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")

    wait (status_vif.preset_n === 1'b1);
    prev    = 6'h3F;
    reached = 1'b0;

    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h (link_up=%0b) @%0d",
                            prev, status_vif.cfg_ltssm_state, status_vif.link_up, cyc),
                  UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1;
        break;
      end
    end

    if (!reached)
      `uvm_fatal(get_type_name(),
                 $sformatf("Did not reach L0 with link_up in %0d cycles (state=0x%02h)",
                           watchdog_cycles, status_vif.cfg_ltssm_state))

    `uvm_info(get_type_name(),
              $sformatf("Reached L0 @%0d — FC settle then RQ MemWr", cyc), UVM_LOW)

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);
    repeat (fc_settle_cycles) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state != 6'h10)
        `uvm_fatal(get_type_name(),
                   $sformatf("Left L0 during FC settle (state=0x%02h)",
                             status_vif.cfg_ltssm_state))
    end

    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    rq_wr      = rivet_axi_rq_memwr32_seq::type_id::create("rq_wr");

    cc_idle.cycles    = post_rq_cycles + 400;
    cq_rdy.cycles     = post_rq_cycles + 400;
    rc_rdy.cycles     = post_rq_cycles + 400;
    comp_grant.cycles = post_rq_cycles + 400;

    fork
      cc_idle.start(p_sequencer.cc_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        cfg_rw.start(p_sequencer.cfg_sqr);
        rq_wr.start(p_sequencer.rq_sqr);
        repeat (post_rq_cycles) @(posedge status_vif.pclk);
        if (status_vif.cfg_ltssm_state != 6'h10)
          `uvm_fatal(get_type_name(),
                     $sformatf("Left L0 after RQ MemWr (state=0x%02h)",
                               status_vif.cfg_ltssm_state))
      end
    join

    `uvm_info(get_type_name(), "TLP RQ MemWr vseq complete", UVM_LOW)
  endtask
endclass : rivet_tlp_rq_memwr_vseq
