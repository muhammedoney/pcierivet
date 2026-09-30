// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// L0 + BME + external MSI-X table request → msix_sent.

class rivet_msix_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_msix_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned settle_cycles   = 8_000;
  int unsigned axi_idle_cycles = 4_000;
  bit [63:0]   msix_addr       = 64'h0000_0000_FEE0_1000;
  bit [31:0]   msix_data       = 32'h0000_00B7;

  rivet_link_status_vif status_vif;
  virtual rivet_interrupt_if intr_vif;

  function new(string name = "rivet_msix_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;
    bit          got_sent;
    rivet_axi_st_idle_seq     cc_idle, rq_idle, cq_rdy, rc_rdy;
    rivet_companion_grant_seq comp_grant;
    rivet_cfg_mgmt_rw_seq     cfg_rw;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "status_vif not set")
    if (!uvm_config_db#(virtual rivet_interrupt_if)::get(null, "uvm_test_top", "intr_vif", intr_vif))
      `uvm_fatal(get_type_name(), "intr_vif not set")

    wait (status_vif.preset_n === 1'b1);
    prev = 6'h3F; reached = 1'b0;
    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1; break;
      end
    end
    if (!reached)
      `uvm_fatal(get_type_name(), "Did not reach L0")

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);
    repeat (settle_cycles) @(posedge status_vif.pclk);

    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle    = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");

    cc_idle.cycles = axi_idle_cycles;
    rq_idle.cycles = axi_idle_cycles;
    cq_rdy.cycles  = axi_idle_cycles;
    rc_rdy.cycles  = axi_idle_cycles;
    comp_grant.cycles = axi_idle_cycles;

    fork
      cc_idle.start(p_sequencer.cc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        cfg_rw.start(p_sequencer.cfg_sqr);

        @(posedge intr_vif.aclk);
        intr_vif.msix_address = msix_addr;
        intr_vif.msix_data    = msix_data;
        intr_vif.msix_int     = 1'b1;
        repeat (8) @(posedge intr_vif.aclk);
        intr_vif.msix_int     = 1'b0;

        got_sent = 1'b0;
        for (cyc = 0; cyc < 20_000; cyc++) begin
          @(posedge intr_vif.aclk);
          if (intr_vif.msix_sent) begin
            got_sent = 1'b1;
            break;
          end
          if (intr_vif.msix_fail)
            `uvm_fatal(get_type_name(), "Unexpected msix_fail")
        end
        if (!got_sent)
          `uvm_fatal(get_type_name(), "cfg_interrupt_msix_sent never asserted")

        `uvm_info(get_type_name(), "MSI-X sent OK", UVM_LOW)
        repeat (200) @(posedge status_vif.pclk);
      end
    join

    `uvm_info(get_type_name(), "MSI-X vseq complete", UVM_LOW)
  endtask
endclass : rivet_msix_vseq
