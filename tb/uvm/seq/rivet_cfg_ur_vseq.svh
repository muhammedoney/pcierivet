// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Downstream completer: a config TLP for another bus is UR. A TLP for the
// primary bus is completed with data. No link partner.

class rivet_cfg_ur_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_cfg_ur_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_cfg_ur_vseq");
    super.new(name);
  endfunction

  task inject(bit [7:0] bus, bit [7:0] exp_b0, bit [2:0] exp_status);
    int unsigned guard;
    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")
    status_vif.cfg_inj_bus  = bus;
    status_vif.cfg_inj_done = 1'b0;
    status_vif.cfg_inj_go   = 1'b1;
    guard = 0;
    while ((status_vif.cfg_inj_done !== 1'b1) && (guard < 5000)) begin
      @(posedge status_vif.pclk);
      guard++;
    end
    status_vif.cfg_inj_go = 1'b0;
    if (status_vif.cfg_inj_done !== 1'b1)
      `uvm_error(get_type_name(), $sformatf("inject bus 0x%02h timed out", bus))
    else if (status_vif.cfg_inj_b0 !== exp_b0 || status_vif.cfg_inj_status !== exp_status)
      `uvm_error(get_type_name(),
        $sformatf("bus 0x%02h cpl b0=0x%02h status=%0d, expected b0=0x%02h status=%0d",
                  bus, status_vif.cfg_inj_b0, status_vif.cfg_inj_status, exp_b0, exp_status))
    else
      `uvm_info(get_type_name(),
        $sformatf("bus 0x%02h -> b0=0x%02h status=%0d", bus, exp_b0, exp_status), UVM_LOW)
    @(posedge status_vif.pclk);
  endtask

  task body();
    rivet_pipe_idle_seq       pipe_idle;
    rivet_axi_st_idle_seq     cc_idle, rq_idle, cq_rdy, rc_rdy;
    rivet_companion_grant_seq comp_grant;

    pipe_idle  = rivet_pipe_idle_seq::type_id::create("pipe_idle");
    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle    = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    pipe_idle.cycles  = 400;
    cc_idle.cycles    = 400;
    rq_idle.cycles    = 400;
    cq_rdy.cycles     = 400;
    rc_rdy.cycles     = 400;
    comp_grant.cycles = 400;

    fork
      pipe_idle.start(p_sequencer.pipe_sqr);
      cc_idle.start(p_sequencer.cc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      begin
        inject(8'h05, rivet_pkg::RIVET_TLP_B0_CPL, 3'b001);
        inject(8'h00, rivet_pkg::RIVET_TLP_B0_CPLD, 3'b000);
      end
    join
  endtask
endclass : rivet_cfg_ur_vseq
