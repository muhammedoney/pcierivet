// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Companion depth: CQ NP grant/count, RQ tag/seq, pcie_tfc_* after L0+FC.

class rivet_companion_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_companion_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles  = 200_000;
  int unsigned hold_l0_cycles   = 200;
  int unsigned fc_settle_cycles = 40_000;
  int unsigned post_cycles      = 1_000;

  bit [7:0]  tag = 8'h11;
  bit [15:0] requester_id = 16'h0100;
  bit [31:0] addr = 32'h0000_2000;

  rivet_link_status_vif status_vif;
  rivet_companion_vif   comp_vif;

  function new(string name = "rivet_companion_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    bit          reached;
    bit          saw_tfc, saw_tag_drop, saw_seq, saw_tag_vld;
    bit          saw_np_delta, peer_done;
    bit [5:0]    np_base, np_now;
    bit [3:0]    tag_av_base, tag_av_now;
    rivet_axi_st_idle_seq     cq_rdy, rc_rdy, cc_idle;
    rivet_companion_grant_seq comp_hold, comp_grant;
    rivet_cfg_mgmt_rw_seq     cfg_rw;
    rivet_axi_rq_memrd32_seq  rq_rd;
    rivet_axi_cc_cpld_seq     cc_cpl;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "status_vif not set")
    if (!uvm_config_db#(rivet_companion_vif)::get(null, "uvm_test_top", "comp_vif", comp_vif))
      `uvm_fatal(get_type_name(), "comp_vif not set")

    wait (status_vif.preset_n === 1'b1);
    reached = 1'b0;
    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1; break;
      end
    end
    if (!reached)
      `uvm_fatal(get_type_name(), "Did not reach L0")

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);
    repeat (fc_settle_cycles) @(posedge status_vif.pclk);

    @(posedge comp_vif.aclk);
    tag_av_base = comp_vif.rq_tag_av;
    np_base     = comp_vif.cq_np_req_count;
    if (tag_av_base != 4'd8)
      `uvm_error(get_type_name(),
        $sformatf("Expected rq_tag_av=8 after reset, got %0d", tag_av_base))
    if (np_base == 6'd0)
      `uvm_error(get_type_name(), "cq_np_req_count still 0 after settle (grants idle?)")

    saw_tfc = 1'b0;
    for (cyc = 0; cyc < 2_000; cyc++) begin
      @(posedge comp_vif.aclk);
      if ((comp_vif.tfc_nph_av != 4'h0) || (comp_vif.tfc_npd_av != 4'h0)) begin
        saw_tfc = 1'b1;
        break;
      end
    end
    if (!saw_tfc)
      `uvm_error(get_type_name(), "pcie_tfc_nph/npd_av stayed 0 after FC settle")

    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    comp_hold  = rivet_companion_grant_seq::type_id::create("comp_hold");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cfg_rw     = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    rq_rd      = rivet_axi_rq_memrd32_seq::type_id::create("rq_rd");
    cc_cpl     = rivet_axi_cc_cpld_seq::type_id::create("cc_cpl");

    cq_rdy.cycles     = post_cycles + 2_000;
    rc_rdy.cycles     = post_cycles + 2_000;
    cc_idle.cycles    = 200;
    comp_hold.cycles  = 800;
    comp_hold.grant   = 2'b00;
    comp_grant.cycles = post_cycles + 1_200;
    comp_grant.grant  = 2'b11;

    rq_rd.addr = addr;
    rq_rd.tag  = tag;
    rq_rd.requester_id = requester_id;

    cc_cpl.tag          = 8'h23;
    cc_cpl.requester_id = 16'h0001;
    cc_cpl.completer_id = 16'h0100;
    cc_cpl.data         = 32'hA5A5_5A5A;
    cc_cpl.lower_addr   = 7'h10;

    saw_np_delta = 1'b0;
    saw_tag_drop = 1'b0;
    saw_seq = 1'b0;
    saw_tag_vld = 1'b0;

    fork
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      begin
        cfg_rw.start(p_sequencer.cfg_sqr);

        // Freeze grants, consume one NP via peer MemRd → CQ
        comp_hold.start(p_sequencer.comp_sqr);
        np_base = comp_vif.cq_np_req_count;
        uvm_config_db#(bit)::set(null, "*", "peer_memrd_go", 1'b1);
        peer_done = 1'b0;
        for (cyc = 0; cyc < 80_000; cyc++) begin
          @(posedge status_vif.pclk);
          void'(uvm_config_db#(bit)::get(null, "*", "peer_tlp_memrd_done", peer_done));
          if (peer_done) break;
        end
        if (!peer_done)
          `uvm_fatal(get_type_name(), "Peer did not inject MemRd TLP")

        for (cyc = 0; cyc < 5_000; cyc++) begin
          @(posedge comp_vif.aclk);
          np_now = comp_vif.cq_np_req_count;
          if (np_now < np_base) begin
            saw_np_delta = 1'b1;
            break;
          end
        end
        if (!saw_np_delta)
          `uvm_error(get_type_name(),
            $sformatf("cq_np_req_count did not drop on CQ MemRd (was %0d)", np_base))

        cc_cpl.start(p_sequencer.cc_sqr);

        // Re-grant and expect count to grow
        np_base = comp_vif.cq_np_req_count;
        saw_np_delta = 1'b0;
        fork
          comp_grant.start(p_sequencer.comp_sqr);
          begin
            for (cyc = 0; cyc < 2_000; cyc++) begin
              @(posedge comp_vif.aclk);
              if (comp_vif.cq_np_req_count > np_base) begin
                saw_np_delta = 1'b1;
                break;
              end
            end
          end
        join
        if (!saw_np_delta)
          `uvm_error(get_type_name(),
            $sformatf("cq_np_req_count did not grow after grant (base=%0d)", np_base))

        fork
          rq_rd.start(p_sequencer.rq_sqr);
          begin
            for (cyc = 0; cyc < 20_000; cyc++) begin
              @(posedge comp_vif.aclk);
              if (comp_vif.rq_seq_num_vld0)
                saw_seq = 1'b1;
              if (comp_vif.rq_tag_vld0)
                saw_tag_vld = 1'b1;
              tag_av_now = comp_vif.rq_tag_av;
              if (tag_av_now < tag_av_base)
                saw_tag_drop = 1'b1;
              if (saw_seq && saw_tag_vld && saw_tag_drop)
                break;
            end
          end
        join

        if (!saw_seq)
          `uvm_error(get_type_name(), "pcie_rq_seq_num_vld0 never pulsed")
        if (!saw_tag_vld)
          `uvm_error(get_type_name(), "pcie_rq_tag_vld0 never pulsed")
        if (!saw_tag_drop)
          `uvm_error(get_type_name(), "pcie_rq_tag_av did not decrease after MemRd")

        // Keep CC quiet while waiting for peer CplD
        cc_idle.start(p_sequencer.cc_sqr);

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

        for (cyc = 0; cyc < 5_000; cyc++) begin
          @(posedge comp_vif.aclk);
          if (comp_vif.rq_tag_av >= tag_av_base)
            break;
        end
        if (comp_vif.rq_tag_av < tag_av_base)
          `uvm_error(get_type_name(),
            $sformatf("tag_av did not recover after RC (now=%0d base=%0d)",
                      comp_vif.rq_tag_av, tag_av_base))

        `uvm_info(get_type_name(),
          $sformatf("Companion OK tfc nph=%0d npd=%0d np=%0d tag_av=%0d",
                    comp_vif.tfc_nph_av, comp_vif.tfc_npd_av,
                    comp_vif.cq_np_req_count, comp_vif.rq_tag_av), UVM_LOW)
        repeat (post_cycles) @(posedge status_vif.pclk);
      end
    join

    `uvm_info(get_type_name(), "Companion vseq complete", UVM_LOW)
  endtask
endclass : rivet_companion_vseq
