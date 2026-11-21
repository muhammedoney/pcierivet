// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Samples AXI-ST accept/stall and pcie_tfc_* while a performance sequence is armed.
// user_clk in rivet_tb_top is 8 ns. Gen2 x4 symbol data rate is 2000 MB/s.

class rivet_perf_mon extends uvm_component;
  `uvm_component_utils(rivet_perf_mon)

  rivet_axi_st_vif     rq_vif, rc_vif, cq_vif, cc_vif;
  rivet_companion_vif  comp_vif;

  protected bit armed;
  int unsigned window_cycles;
  int unsigned rq_accept, rq_stall, rq_tlast;
  int unsigned rc_accept, rc_tlast;
  int unsigned cq_accept, cq_tlast;
  int unsigned cc_accept, cc_tlast;
  int unsigned rq_payload_bytes, cc_payload_bytes;
  int unsigned credit_stall, tfc_zero;
  int unsigned tfc_nph_min;
  int unsigned lat_min, lat_max, lat_sum, lat_n;
  int unsigned rq_payload_per_tlast;
  int unsigned cc_payload_per_tlast;
  protected int unsigned cyc;
  protected int unsigned pending_rq[$];

  localparam real USER_CLK_NS   = 8.0;
  localparam real GEN2_X4_MB_S  = 2000.0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tfc_nph_min = 15;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (!uvm_config_db#(rivet_axi_st_vif)::get(get_parent(), "rq_agent", "vif", rq_vif))
      `uvm_fatal(get_type_name(), "RQ vif not set")
    if (!uvm_config_db#(rivet_axi_st_vif)::get(get_parent(), "rc_agent", "vif", rc_vif))
      `uvm_fatal(get_type_name(), "RC vif not set")
    if (!uvm_config_db#(rivet_axi_st_vif)::get(get_parent(), "cq_agent", "vif", cq_vif))
      `uvm_fatal(get_type_name(), "CQ vif not set")
    if (!uvm_config_db#(rivet_axi_st_vif)::get(get_parent(), "cc_agent", "vif", cc_vif))
      `uvm_fatal(get_type_name(), "CC vif not set")
    if (!uvm_config_db#(rivet_companion_vif)::get(null, "uvm_test_top", "comp_vif", comp_vif))
      `uvm_fatal(get_type_name(), "companion vif not set")
  endfunction

  function void arm(int unsigned rq_bytes_per_tlast = 0,
                    int unsigned cc_bytes_per_tlast = 0);
    armed = 1'b0;
    window_cycles = 0;
    rq_accept = 0; rq_stall = 0; rq_tlast = 0;
    rc_accept = 0; rc_tlast = 0;
    cq_accept = 0; cq_tlast = 0;
    cc_accept = 0; cc_tlast = 0;
    rq_payload_bytes = 0; cc_payload_bytes = 0;
    credit_stall = 0; tfc_zero = 0;
    tfc_nph_min = 15;
    lat_min = 32'hffff_ffff; lat_max = 0; lat_sum = 0; lat_n = 0;
    cyc = 0;
    pending_rq.delete();
    rq_payload_per_tlast = rq_bytes_per_tlast;
    cc_payload_per_tlast = cc_bytes_per_tlast;
    armed = 1'b1;
  endfunction

  function void disarm();
    armed = 1'b0;
  endfunction

  function void report_perf(string tag);
    int unsigned bytes, span, lat_avg;
    real mb_s, pct, stall_pct;
    bytes = rq_payload_bytes + cc_payload_bytes;
    span  = (window_cycles == 0) ? 1 : window_cycles;
    // bytes/s / 1e6 at an 8 ns user clock: bytes * 125 / cycles.
    mb_s = (bytes * 125.0) / span;
    pct  = (100.0 * mb_s) / GEN2_X4_MB_S;
    stall_pct = (100.0 * credit_stall) / span;
    lat_avg = (lat_n == 0) ? 0 : (lat_sum / lat_n);
    if (lat_n == 0)
      lat_min = 0;
    `uvm_info(get_type_name(),
      $sformatf("PERF tag=%s bytes=%0d cycles=%0d rq_accept=%0d rq_stall=%0d rq_tlast=%0d rc_accept=%0d rc_tlast=%0d cq_accept=%0d cq_tlast=%0d cc_accept=%0d cc_tlast=%0d credit_stall=%0d tfc_zero=%0d tfc_nph_min=%0d lat_n=%0d lat_min=%0d lat_avg=%0d lat_max=%0d mb_s=%0.3f pct_gen2x4=%0.3f credit_stall_pct=%0.3f user_clk_ns=%0.1f",
                tag, bytes, window_cycles,
                rq_accept, rq_stall, rq_tlast,
                rc_accept, rc_tlast,
                cq_accept, cq_tlast,
                cc_accept, cc_tlast,
                credit_stall, tfc_zero, tfc_nph_min,
                lat_n, lat_min, lat_avg, lat_max,
                mb_s, pct, stall_pct, USER_CLK_NS),
      UVM_LOW)
  endfunction

  protected function bit accepted(logic tvalid, logic [3:0] tready);
    return tvalid && ((tready & 4'hF) != 4'h0);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge rq_vif.aclk);
      #1ps;
      if (!armed || (rq_vif.aresetn !== 1'b1))
        continue;
      cyc++;
      window_cycles++;
      if ((comp_vif.tfc_nph_av == 4'h0) || (comp_vif.tfc_npd_av == 4'h0))
        tfc_zero++;
      if (comp_vif.tfc_nph_av < tfc_nph_min[3:0])
        tfc_nph_min = comp_vif.tfc_nph_av;

      if (accepted(rq_vif.tvalid, rq_vif.tready)) begin
        rq_accept++;
        if (rq_vif.tlast) begin
          rq_tlast++;
          rq_payload_bytes += rq_payload_per_tlast;
          pending_rq.push_back(cyc);
        end
      end else if (rq_vif.tvalid) begin
        rq_stall++;
        if (comp_vif.tfc_nph_av == 4'h0)
          credit_stall++;
      end

      if (accepted(rc_vif.tvalid, rc_vif.tready)) begin
        rc_accept++;
        if (rc_vif.tlast) begin
          int unsigned issued;
          rc_tlast++;
          if (pending_rq.size() != 0) begin
            int unsigned d;
            issued = pending_rq.pop_front();
            d = cyc - issued;
            if (d < lat_min) lat_min = d;
            if (d > lat_max) lat_max = d;
            lat_sum += d;
            lat_n++;
          end
        end
      end

      if (accepted(cq_vif.tvalid, cq_vif.tready)) begin
        cq_accept++;
        if (cq_vif.tlast)
          cq_tlast++;
      end

      if (accepted(cc_vif.tvalid, cc_vif.tready)) begin
        cc_accept++;
        if (cc_vif.tlast) begin
          cc_tlast++;
          cc_payload_bytes += cc_payload_per_tlast;
        end
      end
    end
  endtask
endclass : rivet_perf_mon
