// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Reach L0, brief settle, then cfg_mgmt Vendor/Device + Command BME/MSE.

class rivet_cfg_mgmt_after_l0_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_cfg_mgmt_after_l0_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned settle_cycles   = 8_000;
  int unsigned axi_idle_cycles = 120;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_cfg_mgmt_after_l0_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;
    rivet_axi_st_idle_seq   cc_idle, rq_idle, cq_rdy, rc_rdy;
    rivet_companion_grant_seq comp_grant;
    rivet_cfg_mgmt_rw_seq   cfg_rw;

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
              $sformatf("Reached L0 @%0d — settle then cfg_mgmt", cyc), UVM_LOW)

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);
    repeat (settle_cycles) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state != 6'h10)
        `uvm_fatal(get_type_name(),
                   $sformatf("Left L0 during settle (state=0x%02h)",
                             status_vif.cfg_ltssm_state))
    end

    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle    = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");

    cc_idle.cycles    = axi_idle_cycles;
    rq_idle.cycles    = axi_idle_cycles;
    cq_rdy.cycles     = axi_idle_cycles;
    rc_rdy.cycles     = axi_idle_cycles;
    comp_grant.cycles = axi_idle_cycles;

    fork
      cc_idle.start(p_sequencer.cc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      cfg_rw.start(p_sequencer.cfg_sqr);
    join

    if (status_vif.cfg_ltssm_state != 6'h10)
      `uvm_fatal(get_type_name(),
                 $sformatf("Left L0 after cfg_mgmt (state=0x%02h)",
                           status_vif.cfg_ltssm_state))

    `uvm_info(get_type_name(), "cfg_mgmt after L0 complete", UVM_LOW)
  endtask
endclass : rivet_cfg_mgmt_after_l0_vseq
