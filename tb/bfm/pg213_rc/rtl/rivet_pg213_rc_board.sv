// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PG213 Endpoint model ↔ Rivet Root Port.
// The partner is xilinx_pcie4_uscale_ep (the example Endpoint + PIO).
// The DUT is rivet_pg239_ep with MODE=RC. Serial lanes cross-connect ×4.
// Module name is `board` so the Questa elaborate target stays the same.

`timescale 1ps/1ps

module board;
  localparam int unsigned LANES = 4;
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
    .MODE            (1), // RIVET_MODE_RC
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
        $display("[%t] : PASS: Rivet RC + PG213 EP link_up", $realtime);
        // Hold the request until the Endpoint is in Hot Reset. The scaled
        // Hot Reset timer is only a few microseconds; the level keeps Rivet
        // transmitting the bit until the vendor model has entered 6'h27.
        #1_000_000;
        hot_reset_req = 1'b1;
        wait (rc_ltssm == 6'h27 && ep_ltssm == 6'h27);
        $display("[%t] : both ports in Hot Reset", $realtime);
        hot_reset_req = 1'b0;
        wait (rc_link_up === 1'b1 && rc_ltssm == 6'h10 && ep_ltssm == 6'h10);
        $display("[%t] : PASS: Rivet RC + PG213 EP hot reset", $realtime);
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
        $display("[%t] : PASS: Rivet RC + PG213 EP link disable", $realtime);
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
