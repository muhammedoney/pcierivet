// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PG213 Endpoint model ↔ Rivet Root Port.
// The partner is xilinx_pcie4_uscale_ep (the example Endpoint + PIO).
// The DUT is rivet_pg239_ep with MODE=RC. Serial lanes cross-connect ×4.
// Module name is `board` so the Questa elaborate target stays the same.

`timescale 1ps/1ps

// 1 = Root Port (config master). 3 = Downstream Port (Type 1, no config master).
`ifndef RIVET_BFM_MODE
  `define RIVET_BFM_MODE 1
`endif

module board;
  localparam int unsigned LANES = 4;
  localparam int unsigned BFM_MODE = `RIVET_BFM_MODE;
  localparam string BFM_ROLE = (BFM_MODE == 3) ? "DSP" : "RC";
  localparam int unsigned REF_CLK_HALF_CYCLE = 5000; // ps → 100 MHz
  localparam int unsigned DRP_CLK_HALF_CYCLE = 1667; // ps → ~300 MHz

  logic sys_rst_n;
  logic ep_sys_clk_p, ep_sys_clk_n;
  logic rp_sys_clk_p, rp_sys_clk_n;
  logic ep_drp_clk_p, ep_drp_clk_n;

  logic [LANES-1:0] ep_pci_exp_txn, ep_pci_exp_txp;
  logic [LANES-1:0] rp_pci_exp_txn, rp_pci_exp_txp;

  logic        rc_phy_ready, rc_link_up;
  logic [5:0]  rc_ltssm;
  logic        hot_reset_req;
  logic        link_disable_req;
  logic        mgmt_wr;
  logic        mgmt_rd;
  logic [9:0]  mgmt_addr;
  logic [31:0] mgmt_wdata;
  wire  [5:0]  ep_ltssm = EP.pcie4_uscale_plus_0_i.inst.cfg_ltssm_state;

  function automatic string ltssm_name(input logic [5:0] s);
    case (s)
      6'h00: ltssm_name = "Detect.Quiet";
      6'h01: ltssm_name = "Detect.Active";
      6'h02: ltssm_name = "Polling.Active";
      6'h04: ltssm_name = "Polling.Configuration";
      6'h05: ltssm_name = "Cfg.Linkwidth.Start";
      6'h06: ltssm_name = "Cfg.Linkwidth.Accept";
      6'h07: ltssm_name = "Cfg.Lanenum.Accept";
      6'h08: ltssm_name = "Cfg.Lanenum.Wait";
      6'h09: ltssm_name = "Cfg.Complete";
      6'h0A: ltssm_name = "Cfg.Idle";
      6'h10: ltssm_name = "L0";
      6'h0B: ltssm_name = "Recovery.RcvrLock";
      6'h20: ltssm_name = "Disabled";
      6'h27: ltssm_name = "Hot Reset";
      default: ltssm_name = $sformatf("0x%0h", s);
    endcase
  endfunction

  sys_clk_gen_ds #(.halfcycle(REF_CLK_HALF_CYCLE), .offset(0)) clk_rc (
    .sys_clk_p(rp_sys_clk_p),
    .sys_clk_n(rp_sys_clk_n)
  );
  sys_clk_gen_ds #(.halfcycle(REF_CLK_HALF_CYCLE), .offset(0)) clk_ep (
    .sys_clk_p(ep_sys_clk_p),
    .sys_clk_n(ep_sys_clk_n)
  );
  sys_clk_gen_ds #(.halfcycle(DRP_CLK_HALF_CYCLE), .offset(0)) clk_ep_drp (
    .sys_clk_p(ep_drp_clk_p),
    .sys_clk_n(ep_drp_clk_n)
  );

  initial begin
    hot_reset_req    = 1'b0;
    link_disable_req = 1'b0;
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge rp_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

  // Same hook the UVM bench uses: the MAC ties this net to 0.
  always @* begin
    if (hot_reset_req === 1'b1) force RC.u_ctrl.u_mac.hot_reset_req = 1'b1;
    else                        release RC.u_ctrl.u_mac.hot_reset_req;
  end
  always @* begin
    if (link_disable_req === 1'b1) force RC.u_ctrl.u_mac.link_disable_req = 1'b1;
    else                           release RC.u_ctrl.u_mac.link_disable_req;
  end

  // Vendor Endpoint. Do not replace this with a Rivet peer.
  xilinx_pcie4_uscale_ep #(
    .PL_LINK_CAP_MAX_LINK_WIDTH(5'(LANES))
  ) EP (
    .sys_clk_n    (ep_sys_clk_n),
    .sys_clk_p    (ep_sys_clk_p),
    .sys_rst_n    (sys_rst_n),
    .led_0        (),
    .led_1        (),
    .led_2        (),
    .led_3        (),
    .led_4        (),
    .led_5        (),
    .led_6        (),
    .led_7        (),
    .clk_300MHz_p (ep_drp_clk_p),
    .clk_300MHz_n (ep_drp_clk_n),
    .pci_exp_txn  (ep_pci_exp_txn),
    .pci_exp_txp  (ep_pci_exp_txp),
    .pci_exp_rxn  (rp_pci_exp_txn),
    .pci_exp_rxp  (rp_pci_exp_txp)
  );

  // Rivet Root Port on the PG239 shell. Speed change stays off so the
  // first serial train matches the Gen1 cap used by the EP BFM path.
  rivet_pg239_ep #(
    .MODE            (BFM_MODE),
    .GEN             (2),
    .SPEED_CHANGE_EN (1'b0),
    .LANES           (LANES)
  ) RC (
    .sys_clk_p       (rp_sys_clk_p),
    .sys_clk_n       (rp_sys_clk_n),
    .sys_rst_n       (sys_rst_n),
    .pci_exp_txp     (rp_pci_exp_txp),
    .pci_exp_txn     (rp_pci_exp_txn),
    .pci_exp_rxp     (ep_pci_exp_txp),
    .pci_exp_rxn     (ep_pci_exp_txn),
    .phy_ready       (rc_phy_ready),
    .link_up         (rc_link_up),
    .cfg_ltssm_state (rc_ltssm),
    .pipe_clk_o      (),
    .user_clk_o      ()
  );

  task automatic cfg_mgmt_access(input logic wr, input logic [9:0] addr,
                                 input logic [31:0] wdata, output logic [31:0] rdata);
    integer k;
    rdata = 32'h0;
    mgmt_wr    = wr;
    mgmt_rd    = ~wr;
    mgmt_addr  = addr;
    mgmt_wdata = wdata;
    @(posedge RC.user_clk);
    force RC.u_ctrl.cfg_mgmt_addr            = mgmt_addr;
    force RC.u_ctrl.cfg_mgmt_function_number = 8'h00;
    force RC.u_ctrl.cfg_mgmt_byte_enable     = 4'hF;
    force RC.u_ctrl.cfg_mgmt_write_data      = mgmt_wdata;
    force RC.u_ctrl.cfg_mgmt_read            = mgmt_rd;
    force RC.u_ctrl.cfg_mgmt_write           = mgmt_wr;
    @(posedge RC.user_clk);
    force RC.u_ctrl.cfg_mgmt_read  = 1'b0;
    force RC.u_ctrl.cfg_mgmt_write = 1'b0;
    for (k = 0; k < 400; k++) begin
      @(posedge RC.user_clk);
      if (RC.u_ctrl.cfg_mgmt_read_write_done === 1'b1) begin
        rdata = RC.u_ctrl.cfg_mgmt_read_data;
        break;
      end
    end
    release RC.u_ctrl.cfg_mgmt_addr;
    release RC.u_ctrl.cfg_mgmt_function_number;
    release RC.u_ctrl.cfg_mgmt_byte_enable;
    release RC.u_ctrl.cfg_mgmt_write_data;
    release RC.u_ctrl.cfg_mgmt_read;
    release RC.u_ctrl.cfg_mgmt_write;
  endtask

  // One CfgRd0 of the Endpoint's vendor/device dword. Completer ID is 0.
  task automatic rc_cfg_rd0();
    integer      g;
    logic [31:0] ignored;
    logic [31:0] data;
    logic [2:0]  status;
    cfg_mgmt_access(1'b1, 10'd1, 32'h0000_0004, ignored);
    @(posedge RC.user_clk);
    force RC.u_ctrl.s_axis_rq_tvalid = 1'b1;
    force RC.u_ctrl.s_axis_rq_tlast  = 1'b0;
    force RC.u_ctrl.s_axis_rq_tkeep  = 2'b11;
    force RC.u_ctrl.s_axis_rq_tuser  = 85'hF;
    force RC.u_ctrl.s_axis_rq_tdata  = 64'h0;
    g = 0;
    while ((RC.u_ctrl.s_axis_rq_tready == 4'h0) && (g < 8000)) begin
      @(posedge RC.user_clk);
      g++;
    end
    if (RC.u_ctrl.s_axis_rq_tready == 4'h0) begin
      $display("[%t] : FAIL: Rivet RC RQ tready stayed low before CfgRd0", $realtime);
      release RC.u_ctrl.s_axis_rq_tvalid;
      release RC.u_ctrl.s_axis_rq_tlast;
      release RC.u_ctrl.s_axis_rq_tkeep;
      release RC.u_ctrl.s_axis_rq_tuser;
      release RC.u_ctrl.s_axis_rq_tdata;
      return;
    end
    @(posedge RC.user_clk);
    // beat1 = {DW3, DW2}. DW2 = {17'h0, CfgRd0, length 1}. Tag 1, completer 0.
    force RC.u_ctrl.s_axis_rq_tlast = 1'b1;
    force RC.u_ctrl.s_axis_rq_tdata = 64'h0000_0001_0000_4001;
    g = 0;
    while ((RC.u_ctrl.s_axis_rq_tready == 4'h0) && (g < 8000)) begin
      @(posedge RC.user_clk);
      g++;
    end
    if (RC.u_ctrl.s_axis_rq_tready == 4'h0) begin
      $display("[%t] : FAIL: Rivet RC did not accept the CfgRd0 descriptor", $realtime);
      force RC.u_ctrl.s_axis_rq_tvalid = 1'b0;
      release RC.u_ctrl.s_axis_rq_tvalid;
      release RC.u_ctrl.s_axis_rq_tlast;
      release RC.u_ctrl.s_axis_rq_tkeep;
      release RC.u_ctrl.s_axis_rq_tuser;
      release RC.u_ctrl.s_axis_rq_tdata;
      return;
    end
    @(posedge RC.user_clk);
    force RC.u_ctrl.s_axis_rq_tvalid = 1'b0;
    release RC.u_ctrl.s_axis_rq_tvalid;
    release RC.u_ctrl.s_axis_rq_tlast;
    release RC.u_ctrl.s_axis_rq_tkeep;
    release RC.u_ctrl.s_axis_rq_tuser;
    release RC.u_ctrl.s_axis_rq_tdata;
    force RC.u_ctrl.m_axis_rc_tready = 1'b1;
    g = 0;
    status = 3'h7;
    data = 32'h0;
    begin
      logic   got_sof;
      logic   got_last;
      got_sof = 1'b0;
      got_last = 1'b0;
      while ((g < 200000) && !got_last) begin
        @(posedge RC.user_clk);
        g++;
        if (RC.u_ctrl.m_axis_rc_tvalid === 1'b1) begin
          if (RC.u_ctrl.m_axis_rc_tuser[32] === 1'b1) begin
            status = RC.u_ctrl.m_axis_rc_tdata[45:43];
            got_sof = 1'b1;
          end
          if (got_sof && (RC.u_ctrl.m_axis_rc_tlast === 1'b1)) begin
            data = RC.u_ctrl.m_axis_rc_tdata[31:0];
            got_last = 1'b1;
          end
        end
      end
      if (!got_last) begin
        $display("[%t] : FAIL: Rivet RC got no completion for CfgRd0", $realtime);
        release RC.u_ctrl.m_axis_rc_tready;
        return;
      end
    end
    release RC.u_ctrl.m_axis_rc_tready;
    $display("[%t] : CfgRd0 cpl status=%0d data=0x%08h", $realtime, status, data);
    if ((status == 3'b000) && (data[15:0] == 16'h10EE))
      $display("[%t] : PASS: Rivet RC + PG213 EP cfg rd0", $realtime);
    else
      $display("[%t] : FAIL: Rivet RC CfgRd0 expected status 0 vendor 10ee, got status=%0d data=0x%08h",
               $realtime, status, data);
  endtask

  // DSP keeps the Type 1 image and must not accept a config descriptor.
  task automatic dsp_type1_and_stall();
    integer      g;
    integer      held;
    logic [31:0] dw2;
    logic [31:0] dw3;
    logic [31:0] ignored;
    cfg_mgmt_access(1'b0, 10'd2, 32'h0, dw2);
    cfg_mgmt_access(1'b0, 10'd3, 32'h0, dw3);
    $display("[%t] : DSP cfg DW2=0x%08h DW3=0x%08h", $realtime, dw2, dw3);
    if ((dw2[31:8] == 24'h060400) && (dw3[23:16] == 8'h01))
      $display("[%t] : PASS: Rivet DSP + PG213 EP type1", $realtime);
    else
      $display("[%t] : FAIL: Rivet DSP Type 1 header DW2=0x%08h DW3=0x%08h",
               $realtime, dw2, dw3);
    cfg_mgmt_access(1'b1, 10'd1, 32'h0000_0004, ignored);
    @(posedge RC.user_clk);
    force RC.u_ctrl.s_axis_rq_tvalid = 1'b1;
    force RC.u_ctrl.s_axis_rq_tlast  = 1'b0;
    force RC.u_ctrl.s_axis_rq_tkeep  = 2'b11;
    force RC.u_ctrl.s_axis_rq_tuser  = 85'hF;
    force RC.u_ctrl.s_axis_rq_tdata  = 64'h0;
    g = 0;
    while ((RC.u_ctrl.s_axis_rq_tready == 4'h0) && (g < 8000)) begin
      @(posedge RC.user_clk);
      g++;
    end
    if (RC.u_ctrl.s_axis_rq_tready == 4'h0) begin
      $display("[%t] : FAIL: Rivet DSP RQ tready stayed low on beat 0", $realtime);
      force RC.u_ctrl.s_axis_rq_tvalid = 1'b0;
      release RC.u_ctrl.s_axis_rq_tvalid;
      release RC.u_ctrl.s_axis_rq_tlast;
      release RC.u_ctrl.s_axis_rq_tkeep;
      release RC.u_ctrl.s_axis_rq_tuser;
      release RC.u_ctrl.s_axis_rq_tdata;
      return;
    end
    @(posedge RC.user_clk);
    // CfgWr1, length 1. Beat 1 must not be accepted.
    force RC.u_ctrl.s_axis_rq_tlast = 1'b1;
    force RC.u_ctrl.s_axis_rq_tdata = 64'h0000_0000_0000_5801;
    held = 0;
    repeat (50) begin
      @(posedge RC.user_clk);
      if (RC.u_ctrl.s_axis_rq_tready == 4'h0)
        held++;
    end
    force RC.u_ctrl.s_axis_rq_tvalid = 1'b0;
    release RC.u_ctrl.s_axis_rq_tvalid;
    release RC.u_ctrl.s_axis_rq_tlast;
    release RC.u_ctrl.s_axis_rq_tkeep;
    release RC.u_ctrl.s_axis_rq_tuser;
    release RC.u_ctrl.s_axis_rq_tdata;
    if (held == 50)
      $display("[%t] : PASS: Rivet DSP + PG213 EP rq stall", $realtime);
    else
      $display("[%t] : FAIL: Rivet DSP accepted a config RQ beat (held=%0d)", $realtime, held);
  endtask

  always @(rc_ltssm or ep_ltssm or rc_link_up) begin
    $display("[%t] : RC %s (0x%02h) link_up=%0b phy=%0b | EP %s (0x%02h)",
             $realtime, ltssm_name(rc_ltssm), rc_ltssm, rc_link_up, rc_phy_ready,
             ltssm_name(ep_ltssm), ep_ltssm);
  end

  initial begin
    wait (sys_rst_n === 1'b1);
    wait (rc_phy_ready === 1'b1);
    $display("[%t] : RC phy_ready — waiting L0 on both ports", $realtime);
    fork
      begin
        wait (rc_link_up === 1'b1 && rc_ltssm == 6'h10 && ep_ltssm == 6'h10);
        $display("[%t] : PASS: Rivet %s + PG213 EP link_up", $realtime, BFM_ROLE);
        // Hold the request until the Endpoint is in Hot Reset. The scaled
        // Hot Reset timer is only a few microseconds; the level keeps Rivet
        // transmitting the bit until the vendor model has entered 6'h27.
        #1_000_000;
        hot_reset_req = 1'b1;
        wait (rc_ltssm == 6'h27 && ep_ltssm == 6'h27);
        $display("[%t] : both ports in Hot Reset", $realtime);
        hot_reset_req = 1'b0;
        wait (rc_link_up === 1'b1 && rc_ltssm == 6'h10 && ep_ltssm == 6'h10);
        $display("[%t] : PASS: Rivet %s + PG213 EP hot reset", $realtime, BFM_ROLE);
        #1_000_000;
        link_disable_req = 1'b1;
        wait (rc_ltssm == 6'h20 && ep_ltssm == 6'h20);
        $display("[%t] : both ports Disabled", $realtime);
        #2_000_000;
        if (rc_ltssm != 6'h20) begin
          $display("[%t] : FAIL: Rivet RC left Disabled while the request was high (RC=0x%02h)",
                   $realtime, rc_ltssm);
          $finish;
        end
        link_disable_req = 1'b0;
        wait (rc_link_up === 1'b1 && rc_ltssm == 6'h10 && ep_ltssm == 6'h10);
        $display("[%t] : PASS: Rivet %s + PG213 EP link disable", $realtime, BFM_ROLE);
        if (BFM_MODE == 3)
          dsp_type1_and_stall();
        else
          rc_cfg_rd0();
        #10_000;
        $finish;
      end
      begin
        #1_500_000_000;
        $display("[%t] : FAIL: Rivet RC + PG213 EP link training timeout (RC=0x%02h EP=0x%02h)",
                 $realtime, rc_ltssm, ep_ltssm);
        $finish;
      end
    join_any
    disable fork;
  end
endmodule : board
