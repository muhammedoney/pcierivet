// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// L0 + BME + MSI program + assert cfg_interrupt_msi_int → msi_sent.

class rivet_msi_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_msi_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned settle_cycles   = 8_000;
  int unsigned axi_idle_cycles = 4_000;
  bit [31:0]   msi_addr        = 32'hFEE0_0000;
  bit [15:0]   msi_data        = 16'h00A5;
  bit [4:0]    msi_vector      = 5'd3;

  rivet_link_status_vif status_vif;
  virtual rivet_interrupt_if intr_vif;

  function new(string name = "rivet_msi_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;
    bit          got_sent;
    bit          got_en;
    rivet_axi_st_idle_seq        cc_idle, rq_idle, cq_rdy, rc_rdy;
    rivet_companion_grant_seq    comp_grant;
    rivet_cfg_mgmt_msi_prog_seq  cfg_msi;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "status_vif not set")
    if (!uvm_config_db#(virtual rivet_interrupt_if)::get(null, "uvm_test_top", "intr_vif", intr_vif))
      `uvm_fatal(get_type_name(), "intr_vif not set")

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
    repeat (settle_cycles) @(posedge status_vif.pclk);

    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle    = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_msi    = rivet_cfg_mgmt_msi_prog_seq::type_id::create("cfg_msi");

    cc_idle.cycles    = axi_idle_cycles;
    rq_idle.cycles    = axi_idle_cycles;
    cq_rdy.cycles     = axi_idle_cycles;
    rc_rdy.cycles     = axi_idle_cycles;
    comp_grant.cycles = axi_idle_cycles;
    cfg_msi.msi_addr  = msi_addr;
    cfg_msi.msi_data  = msi_data;

    fork
      cc_idle.start(p_sequencer.cc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        cfg_msi.start(p_sequencer.cfg_sqr);

        got_en = 1'b0;
        for (cyc = 0; cyc < 2_000; cyc++) begin
          @(posedge intr_vif.aclk);
          if (intr_vif.msi_enable) begin
            got_en = 1'b1;
            break;
          end
        end
        if (!got_en)
          `uvm_fatal(get_type_name(), "cfg_interrupt_msi_enable never asserted")

        @(posedge intr_vif.aclk);
        intr_vif.msi_int = (32'h1 << msi_vector);
        repeat (8) @(posedge intr_vif.aclk);
        intr_vif.msi_int = '0;

        got_sent = 1'b0;
        for (cyc = 0; cyc < 20_000; cyc++) begin
          @(posedge intr_vif.aclk);
          if (intr_vif.msi_sent) begin
            got_sent = 1'b1;
            break;
          end
          if (intr_vif.msi_fail)
            `uvm_fatal(get_type_name(), "Unexpected msi_fail")
        end
        if (!got_sent)
          `uvm_fatal(get_type_name(), "cfg_interrupt_msi_sent never asserted")

        `uvm_info(get_type_name(),
                  $sformatf("MSI vector %0d sent OK", msi_vector), UVM_LOW)
        repeat (200) @(posedge status_vif.pclk);
      end
    join

    `uvm_info(get_type_name(), "MSI vseq complete", UVM_LOW)
  endtask
endclass : rivet_msi_vseq
