// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PG213 stage-3 board: Xilinx RP model ↔ Rivet EP+PG239.
// Module name MUST be `board` and RP instance `RP` — usrapp_* uses board.RP.*.

`timescale 1ps/1ps

module board;

  localparam int unsigned LINK_WIDTH         = 4;
  localparam int unsigned REF_CLK_HALF_CYCLE = 5000; // ps → 100 MHz (sys_clk_gen is 1ps)

  logic sys_rst_n;
  logic ep_sys_clk_p, ep_sys_clk_n;
  logic rp_sys_clk_p, rp_sys_clk_n;

  logic [LINK_WIDTH-1:0] ep_pci_exp_txn, ep_pci_exp_txp;
  logic [LINK_WIDTH-1:0] rp_pci_exp_txn, rp_pci_exp_txp;
  logic [11:0]           rp_txn, rp_txp;

  logic ep_phy_ready, ep_link_up;
  logic [5:0] ep_ltssm;

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE),
    .offset    (0)
  ) CLK_GEN_RP (
    .sys_clk_p (rp_sys_clk_p),
    .sys_clk_n (rp_sys_clk_n)
  );

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE),
    .offset    (0)
  ) CLK_GEN_EP (
    .sys_clk_p (ep_sys_clk_p),
    .sys_clk_n (ep_sys_clk_n)
  );

  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge rp_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

  // Rivet EP+PG239 (pin-compatible swap for xilinx_pcie4_uscale_ep)
  rivet_pg213_ep_swap #(
    .PL_LINK_CAP_MAX_LINK_WIDTH (5'(LINK_WIDTH)),
    .C_DATA_WIDTH               (64)
  ) EP (
    .pci_exp_txp   (ep_pci_exp_txp),
    .pci_exp_txn   (ep_pci_exp_txn),
    .pci_exp_rxp   (rp_pci_exp_txp),
    .pci_exp_rxn   (rp_pci_exp_txn),
    .led_0         (),
    .led_1         (),
    .led_2         (),
    .led_3         (),
    .led_4         (),
    .led_5         (),
    .led_6         (),
    .led_7         (),
    .clk_300MHz_p  (1'b0),
    .clk_300MHz_n  (1'b0),
    .sys_clk_p     (ep_sys_clk_p),
    .sys_clk_n     (ep_sys_clk_n),
    .sys_rst_n     (sys_rst_n),
    .phy_ready_o   (ep_phy_ready),
    .link_up_o     (ep_link_up),
    .ltssm_state_o (ep_ltssm)
  );

  // Stock PG213 Root Port model (×16 ports; lower ×4 wired)
  xilinx_pcie4_uscale_rp #(
    .PL_LINK_CAP_MAX_LINK_SPEED (2), // Gen2
    .PL_LINK_CAP_MAX_LINK_WIDTH (16),
    .PF0_DEV_CAP_MAX_PAYLOAD_SIZE (3'b011)
  ) RP (
    .sys_clk_n (rp_sys_clk_n),
    .sys_clk_p (rp_sys_clk_p),
    .sys_rst_n (sys_rst_n),
    .pci_exp_txn ({rp_txn, rp_pci_exp_txn}),
    .pci_exp_txp ({rp_txp, rp_pci_exp_txp}),
    .pci_exp_rxn ({12'b0, ep_pci_exp_txn}),
    .pci_exp_rxp ({12'b0, ep_pci_exp_txp})
  );

  initial begin
    wait (sys_rst_n === 1'b1);
    $display("[%t] : Waiting for Rivet EP phy_ready...", $realtime);
    wait (ep_phy_ready === 1'b1);
    $display("[%t] : EP phy_ready - waiting link_up (EP) + RP user_lnk_up", $realtime);

    wait (ep_link_up === 1'b1);
    wait (RP.user_lnk_up === 1'b1);
    #10000;
    $display("[%t] : EP ltssm=%0h link_up=%0b | RP user_lnk_up=%0b",
             $realtime, ep_ltssm, ep_link_up, RP.user_lnk_up);
    $display("[%t] : Test Completed Successfully (PG213 RP + Rivet EP link_up)",
             $realtime);

    begin
      automatic logic ep_fc, ep_dl;
      automatic int unsigned i;
      ep_fc = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done;
      ep_dl = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up;
      for (i = 0; i < 200000; i++) begin
        @(posedge EP.u_rivet_ep.pipe_clk_o);
        ep_fc = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done;
        ep_dl = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up;
        if (ep_fc && ep_dl) break;
      end
      $display("[%t] : FC@EP       fc_init=%0b dl_up=%0b", $realtime, ep_fc, ep_dl);
      $display("[%t] : TLP note    RP usrapp will attempt Cfg after link_up; Rivet TL still stub",
               $realtime);
    end
    $finish;
  end

  // Early fail: Detect(0)→…→Polling.Cfg(4)→Detect without link_up (same as dual-Rivet PG239).
  // Prefer this over #delay watchdogs — large delays are unreliable under vopt here.
  logic seen_poll_cfg;
  initial seen_poll_cfg = 1'b0;
  always @(ep_ltssm) begin
    if (ep_ltssm == 6'h4)
      seen_poll_cfg = 1'b1;
    if (seen_poll_cfg && ep_ltssm == 6'h0 && !ep_link_up && ep_phy_ready) begin
      $display("[%t] : TIMEOUT - Detect/Polling cycle (no link_up) ep_ltssm=%0h RP lnk=%0b",
               $realtime, ep_ltssm, RP.user_lnk_up);
      $display("[%t] : PG213 RP + Rivet EP link training timeout", $realtime);
      $finish(2);
    end
  end

  always @(ep_ltssm or ep_link_up or RP.user_lnk_up) begin
    $display("[%t] : LTSSM ep=%0h ep_link=%0b rp_lnk=%0b",
             $realtime, ep_ltssm, ep_link_up, RP.user_lnk_up);
  end

endmodule : board
