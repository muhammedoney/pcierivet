// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 x4 performance sequences. Numbers come from rivet_perf_mon on the
// AXI-ST and pcie_tfc_* ports. The window starts after L0 and FC settle.

class rivet_perf_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_perf_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles  = 200_000;
  int unsigned hold_l0_cycles   = 200;
  int unsigned fc_settle_cycles = 40_000;

  rivet_link_status_vif status_vif;
  rivet_perf_mon        perf;

  function new(string name = "rivet_perf_vseq");
    super.new(name);
  endfunction

  task wait_l0();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")
    if (!uvm_config_db#(rivet_perf_mon)::get(null, "uvm_test_top", "perf_mon", perf))
      `uvm_fatal(get_type_name(), "rivet_perf_mon not set")

    wait (status_vif.preset_n === 1'b1);
    prev = 6'h3F;
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
        $sformatf("Did not reach L0 in %0d cycles (state=0x%02h)",
                  watchdog_cycles, status_vif.cfg_ltssm_state))

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);
    repeat (fc_settle_cycles) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state != 6'h10)
        `uvm_fatal(get_type_name(),
          $sformatf("Left L0 during FC settle (state=0x%02h)",
                    status_vif.cfg_ltssm_state))
    end
  endtask

  task start_sidebands(int unsigned cycles, bit drive_rq, bit drive_cc);
    rivet_axi_st_idle_seq cq_rdy, rc_rdy, cc_idle, rq_idle;
    rivet_companion_grant_seq comp_grant;
    cq_rdy  = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy  = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    cc_idle = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    cq_rdy.cycles = cycles;
    rc_rdy.cycles = cycles;
    cc_idle.cycles = cycles;
    rq_idle.cycles = cycles;
    comp_grant.cycles = cycles;
    fork
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      if (drive_cc) cc_idle.start(p_sequencer.cc_sqr);
      if (drive_rq) rq_idle.start(p_sequencer.rq_sqr);
    join_none
  endtask

  task body();
    `uvm_fatal(get_type_name(), "rivet_perf_vseq is a base; start a perf_* sequence")
  endtask
endclass : rivet_perf_vseq


// 64 posted 1DW MemWr. Payload is 4 bytes per TLP (the data beat).
class rivet_perf_rq_memwr_vseq extends rivet_perf_vseq;
  `uvm_object_utils(rivet_perf_rq_memwr_vseq)

  // Peer InitFC advertises 32 posted header credits and does not raise that limit.
  int unsigned n_tlp = 16;

  function new(string name = "rivet_perf_rq_memwr_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_cfg_mgmt_rw_seq cfg_rw;
    int unsigned i;
    wait_l0();
    start_sidebands(n_tlp * 40 + 4_000, 1'b0, 1'b1);
    cfg_rw = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cfg_rw.start(p_sequencer.cfg_sqr);
    perf.arm(4, 0);
    for (i = 0; i < n_tlp; i++) begin
      rivet_axi_rq_memwr32_seq wr;
      wr = rivet_axi_rq_memwr32_seq::type_id::create($sformatf("wr_%0d", i));
      wr.addr = 32'h0000_1000 + (i << 2);
      wr.data = 32'hA5A5_0000 + i;
      wr.tag  = i[7:0];
      wr.start(p_sequencer.rq_sqr);
    end
    perf.disarm();
    repeat (200) @(posedge status_vif.pclk);
    if (status_vif.cfg_ltssm_state != 6'h10)
      `uvm_fatal(get_type_name(), "Left L0 during posted-write burst")
    if (perf.rq_tlast != n_tlp)
      `uvm_error(get_type_name(),
        $sformatf("Expected %0d RQ tlast, saw %0d", n_tlp, perf.rq_tlast))
    perf.report_perf("rq_memwr");
    wait fork;
  endtask
endclass : rivet_perf_rq_memwr_vseq


// Eight RQ MemRd32 to RC CplD round trips. Latency includes the PIPE peer.
class rivet_perf_rq_rc_lat_vseq extends rivet_perf_vseq;
  `uvm_object_utils(rivet_perf_rq_rc_lat_vseq)

  int unsigned n_tlp = 8;

  function new(string name = "rivet_perf_rq_rc_lat_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_cfg_mgmt_rw_seq cfg_rw;
    int unsigned i;
    wait_l0();
    start_sidebands(n_tlp * 80_000, 1'b0, 1'b1);
    cfg_rw = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cfg_rw.start(p_sequencer.cfg_sqr);
    perf.arm(0, 0);
    for (i = 0; i < n_tlp; i++) begin
      rivet_axi_rq_memrd32_seq rd;
      bit peer_done;
      int unsigned cyc;
      int unsigned lat_before;
      uvm_config_db#(bit)::set(null, "*", "peer_cpld_rearm", 1'b1);
      uvm_config_db#(bit [7:0])::set(null, "*", "peer_cpld_tag", i[7:0] + 8'h11);
      peer_done = 1'b1;
      for (cyc = 0; cyc < 2_000; cyc++) begin
        @(posedge status_vif.pclk);
        void'(uvm_config_db#(bit)::get(null, "*", "peer_cpld_rearm", peer_done));
        if (!peer_done)
          break;
      end
      rd = rivet_axi_rq_memrd32_seq::type_id::create($sformatf("rd_%0d", i));
      rd.tag = i[7:0] + 8'h11;
      rd.start(p_sequencer.rq_sqr);
      lat_before = perf.lat_n;
      uvm_config_db#(bit)::set(null, "*", "peer_cpld_go", 1'b1);
      peer_done = 1'b0;
      for (cyc = 0; cyc < 80_000; cyc++) begin
        @(posedge status_vif.pclk);
        void'(uvm_config_db#(bit)::get(null, "*", "peer_tlp_cpld_done", peer_done));
        if (peer_done)
          break;
      end
      if (!peer_done)
        `uvm_fatal(get_type_name(), $sformatf("Peer CplD %0d was not injected", i))
      for (cyc = 0; cyc < 20_000; cyc++) begin
        @(posedge status_vif.pclk);
        if (perf.lat_n > lat_before)
          break;
      end
      if (perf.lat_n == lat_before)
        `uvm_error(get_type_name(), $sformatf("RC CplD %0d did not complete", i))
    end
    if (status_vif.cfg_ltssm_state != 6'h10)
      `uvm_fatal(get_type_name(), "Left L0 during read-latency loop")
    perf.disarm();
    perf.report_perf("rq_rc_lat");
    wait fork;
  endtask
endclass : rivet_perf_rq_rc_lat_vseq


// Eight peer MemRd32, each answered with a 1DW CC CplD (4 payload bytes).
class rivet_perf_cq_cc_vseq extends rivet_perf_vseq;
  `uvm_object_utils(rivet_perf_cq_cc_vseq)

  int unsigned n_tlp = 8;

  function new(string name = "rivet_perf_cq_cc_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_cfg_mgmt_rw_seq cfg_rw;
    int unsigned i;
    wait_l0();
    start_sidebands(n_tlp * 80_000, 1'b1, 1'b0);
    cfg_rw = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cfg_rw.start(p_sequencer.cfg_sqr);
    perf.arm(0, 4);
    for (i = 0; i < n_tlp; i++) begin
      rivet_axi_cc_cpld_seq cc;
      bit peer_done;
      int unsigned cyc;
      int unsigned cc_before;
      int unsigned cq_before;
      uvm_config_db#(bit)::set(null, "*", "peer_memrd_go", 1'b0);
      uvm_config_db#(bit [7:0])::set(null, "*", "peer_memrd_tag", i[7:0] + 8'h30);
      peer_done = 1'b1;
      for (cyc = 0; cyc < 4_000; cyc++) begin
        @(posedge status_vif.pclk);
        void'(uvm_config_db#(bit)::get(null, "*", "peer_tlp_memrd_done", peer_done));
        if (!peer_done)
          break;
      end
      if (peer_done)
        `uvm_fatal(get_type_name(), $sformatf("Peer MemRd %0d did not rearm", i))
      cq_before = perf.cq_tlast;
      uvm_config_db#(bit)::set(null, "*", "peer_memrd_go", 1'b1);
      peer_done = 1'b0;
      for (cyc = 0; cyc < 80_000; cyc++) begin
        @(posedge status_vif.pclk);
        void'(uvm_config_db#(bit)::get(null, "*", "peer_tlp_memrd_done", peer_done));
        if (peer_done && (perf.cq_tlast > cq_before))
          break;
      end
      if (!(peer_done && (perf.cq_tlast > cq_before)))
        `uvm_fatal(get_type_name(), $sformatf("Peer MemRd %0d did not reach CQ", i))
      cc_before = perf.cc_tlast;
      cc = rivet_axi_cc_cpld_seq::type_id::create($sformatf("cc_%0d", i));
      cc.tag = i[7:0] + 8'h30;
      cc.requester_id = 16'h0001;
      cc.completer_id = 16'h0100;
      cc.data = 32'hA5A5_0000 + i;
      cc.lower_addr = 7'h10;
      cc.start(p_sequencer.cc_sqr);
      for (cyc = 0; cyc < 4_000; cyc++) begin
        @(posedge status_vif.pclk);
        if (perf.cc_tlast > cc_before)
          break;
      end
    end
    if (status_vif.cfg_ltssm_state != 6'h10)
      `uvm_fatal(get_type_name(), "Left L0 during CQ-CC loop")
    perf.disarm();
    if (perf.cc_tlast != n_tlp)
      `uvm_error(get_type_name(),
        $sformatf("Expected %0d CC tlast, saw %0d", n_tlp, perf.cc_tlast))
    perf.report_perf("cq_cc");
    wait fork;
  endtask
endclass : rivet_perf_cq_cc_vseq


// Non-posted MemRd32 while sampling pcie_tfc_nph_av. Reports the share of
// armed cycles where RQ is stalled and NPH credits read 0.
class rivet_perf_credit_stall_vseq extends rivet_perf_vseq;
  `uvm_object_utils(rivet_perf_credit_stall_vseq)

  // Peer InitFC advertises 16 non-posted header credits. Stay under that
  // so the last beat is accepted and the test can report tfc_nph_min.
  int unsigned n_tlp = 12;

  function new(string name = "rivet_perf_credit_stall_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_cfg_mgmt_rw_seq cfg_rw;
    rivet_companion_vif comp_vif;
    int unsigned i;
    if (!uvm_config_db#(rivet_companion_vif)::get(null, "uvm_test_top", "comp_vif", comp_vif))
      `uvm_fatal(get_type_name(), "companion vif not set")
    wait_l0();
    start_sidebands(n_tlp * 40 + 4_000, 1'b0, 1'b1);
    cfg_rw = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cfg_rw.start(p_sequencer.cfg_sqr);
    perf.arm(0, 0);
    for (i = 0; i < n_tlp; i++) begin
      rivet_axi_rq_memrd32_seq rd;
      rd = rivet_axi_rq_memrd32_seq::type_id::create($sformatf("np_%0d", i));
      rd.tag = i[7:0];
      rd.start(p_sequencer.rq_sqr);
      if (comp_vif.tfc_nph_av == 4'h0)
        break;
    end
    repeat (400) @(posedge status_vif.pclk);
    if (status_vif.cfg_ltssm_state != 6'h10)
      `uvm_fatal(get_type_name(), "Left L0 during credit-stall loop")
    perf.disarm();
    if (perf.rq_tlast == 0)
      `uvm_error(get_type_name(), "No RQ MemRd accepted")
    perf.report_perf("credit_stall");
    wait fork;
  endtask
endclass : rivet_perf_credit_stall_vseq


// Posted-write throughput versus payload size. The PIPE peer is in
// performance mode: infinite credits and an ACK per TLP, so the replay
// buffer does not cap the burst. Each PERF line is one payload size.
class rivet_perf_rq_sweep_vseq extends rivet_perf_vseq;
  `uvm_object_utils(rivet_perf_rq_sweep_vseq)

  // PCIe Max Payload Size steps, 128 B through 4096 B.
  int unsigned n_tlp = 8;

  function new(string name = "rivet_perf_rq_sweep_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_cfg_mgmt_rw_seq cfg_rw;
    int unsigned sizes[$];
    int unsigned s;
    // 1 DW = 4 B. Max Payload Size steps start at 32 DW (128 B) and
    // end at 1024 DW (4096 B). Length 1024 is the PCIe wire encoding 0.
    sizes = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024};
    wait_l0();
    start_sidebands(800_000, 1'b0, 1'b1);
    cfg_rw = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cfg_rw.start(p_sequencer.cfg_sqr);
    for (s = 0; s < sizes.size(); s++) begin
      int unsigned dw, i;
      dw = sizes[s];
      // Let the previous size's replay and ACKs finish so this PERF
      // line is the payload size, not leftover backpressure.
      repeat (8_000) @(posedge status_vif.pclk);
      perf.arm(dw * 4, 0);
      for (i = 0; i < n_tlp; i++) begin
        rivet_axi_rq_memwr_seq wr;
        wr = rivet_axi_rq_memwr_seq::type_id::create(
          $sformatf("wr_dw%0d_%0d", dw, i));
        wr.payload_dw = dw;
        wr.addr = 32'h0000_1000 + (i << 6);
        wr.tag  = i[7:0];
        wr.start(p_sequencer.rq_sqr);
      end
      perf.disarm();
      if (status_vif.cfg_ltssm_state != 6'h10)
        `uvm_fatal(get_type_name(),
          $sformatf("Left L0 during %0dDW burst", dw))
      if (perf.rq_tlast != n_tlp)
        `uvm_error(get_type_name(),
          $sformatf("%0dDW: expected %0d RQ tlast, saw %0d",
                    dw, n_tlp, perf.rq_tlast))
      perf.report_perf($sformatf("rq_dw%0d", dw));
    end
    wait fork;
  endtask
endclass : rivet_perf_rq_sweep_vseq


// Posted MemWr64 (address above 4 GB) over the same payload steps as MemWr32.
class rivet_perf_rq_memwr64_vseq extends rivet_perf_vseq;
  `uvm_object_utils(rivet_perf_rq_memwr64_vseq)

  int unsigned n_tlp = 8;

  function new(string name = "rivet_perf_rq_memwr64_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_cfg_mgmt_rw_seq cfg_rw;
    int unsigned sizes[$];
    int unsigned s;
    sizes = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024};
    wait_l0();
    start_sidebands(800_000, 1'b0, 1'b1);
    cfg_rw = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cfg_rw.start(p_sequencer.cfg_sqr);
    for (s = 0; s < sizes.size(); s++) begin
      int unsigned dw, i;
      dw = sizes[s];
      repeat (8_000) @(posedge status_vif.pclk);
      perf.arm(dw * 4, 0);
      for (i = 0; i < n_tlp; i++) begin
        rivet_axi_rq_memwr_seq wr;
        wr = rivet_axi_rq_memwr_seq::type_id::create(
          $sformatf("wr64_dw%0d_%0d", dw, i));
        wr.payload_dw = dw;
        wr.addr       = 32'h0000_1000 + (i << 6);
        wr.addr_hi    = 32'h0000_0001;
        wr.tag        = i[7:0];
        wr.start(p_sequencer.rq_sqr);
      end
      perf.disarm();
      if (status_vif.cfg_ltssm_state != 6'h10)
        `uvm_fatal(get_type_name(),
          $sformatf("Left L0 during MemWr64 %0dDW burst", dw))
      if (perf.rq_tlast != n_tlp)
        `uvm_error(get_type_name(),
          $sformatf("MemWr64 %0dDW: expected %0d RQ tlast, saw %0d",
                    dw, n_tlp, perf.rq_tlast))
      perf.report_perf($sformatf("rq64_dw%0d", dw));
    end
    wait fork;
  endtask
endclass : rivet_perf_rq_memwr64_vseq


// MemRd32 then MemRd64, one PERF line per payload. The peer answers each
// request with a CplD of that size. Bytes are the completion payload.
class rivet_perf_rq_memrd_vseq extends rivet_perf_vseq;
  `uvm_object_utils(rivet_perf_rq_memrd_vseq)

  int unsigned n_tlp = 8;

  function new(string name = "rivet_perf_rq_memrd_vseq");
    super.new(name);
  endfunction

  task automatic burst(input bit addr64, input int unsigned dw);
    int unsigned i, cyc;
    int unsigned bytes_per;
    string tag;
    bytes_per = (dw >= 1024) ? 4096 : (dw * 4);
    tag = addr64 ? $sformatf("rd64_dw%0d", dw) : $sformatf("rd_dw%0d", dw);
    uvm_config_db#(int unsigned)::set(null, "*", "peer_cpld_dw", dw);
    repeat (8_000) @(posedge status_vif.pclk);
    perf.arm(0, 0, bytes_per);
    for (i = 0; i < n_tlp; i++) begin
      rivet_axi_rq_memrd32_seq rd;
      rd = rivet_axi_rq_memrd32_seq::type_id::create($sformatf("%s_%0d", tag, i));
      rd.payload_dw = dw[10:0];
      rd.addr_hi    = addr64 ? 32'h1 : 32'h0;
      rd.tag        = i[7:0] + 8'h11;
      rd.start(p_sequencer.rq_sqr);
    end
    for (cyc = 0; cyc < 400_000; cyc++) begin
      @(posedge status_vif.pclk);
      if (perf.rc_tlast == n_tlp)
        break;
    end
    perf.disarm();
    if (status_vif.cfg_ltssm_state != 6'h10)
      `uvm_fatal(get_type_name(),
        $sformatf("Left L0 during MemRd %0dDW", dw))
    if (perf.rc_tlast != n_tlp)
      `uvm_fatal(get_type_name(),
        $sformatf("%s: expected %0d RC tlast, saw %0d", tag, n_tlp, perf.rc_tlast))
    perf.report_perf(tag);
  endtask

  task body();
    rivet_cfg_mgmt_rw_seq cfg_rw;
    int unsigned sizes[$];
    int unsigned s;
    sizes = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024};
    wait_l0();
    start_sidebands(500_000, 1'b0, 1'b1);
    cfg_rw = rivet_cfg_mgmt_rw_seq::type_id::create("cfg_rw");
    cfg_rw.start(p_sequencer.cfg_sqr);
    for (s = 0; s < sizes.size(); s++)
      burst(1'b0, sizes[s]);
    for (s = 0; s < sizes.size(); s++)
      burst(1'b1, sizes[s]);
    wait fork;
  endtask
endclass : rivet_perf_rq_memrd_vseq
