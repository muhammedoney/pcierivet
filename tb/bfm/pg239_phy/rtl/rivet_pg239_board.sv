// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// BFM stage-2 board: two rivet_pg239_ep instances (each = PG239 + rivet_pcie_ctrl)
// linked over serial ×4. PASS when both report link_up (Config.Idle / L0 path).

`timescale 1ps/1ps

module rivet_pg239_board;

  localparam int unsigned LANES = 4;
  // Example refclk half-period: 100 MHz differential (5 ns half = 10 ns period).
  localparam int unsigned REF_CLK_HALF_CYCLE = 5000; // ps

  logic sys_rst_n;
  logic ep_sys_clk_p, ep_sys_clk_n;
  logic rp_sys_clk_p, rp_sys_clk_n;

  logic [LANES-1:0] ep_txp, ep_txn, ep_rxp, ep_rxn;
  logic [LANES-1:0] rp_txp, rp_txn, rp_rxp, rp_rxn;

  logic ep_phy_ready, rp_phy_ready;
  logic ep_link_up, rp_link_up;
  logic [5:0] ep_ltssm, rp_ltssm;

  // Serial cross-connect
  assign ep_rxp = rp_txp;
  assign ep_rxn = rp_txn;
  assign rp_rxp = ep_txp;
  assign rp_rxn = ep_txn;

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE)
  ) u_clk_ep (
    .sys_clk_p (ep_sys_clk_p),
    .sys_clk_n (ep_sys_clk_n)
  );

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE)
  ) u_clk_rp (
    .sys_clk_p (rp_sys_clk_p),
    .sys_clk_n (rp_sys_clk_n)
  );

  rivet_pg239_ep #(
    .LANES (LANES)
  ) u_ep (
    .sys_clk_p       (ep_sys_clk_p),
    .sys_clk_n       (ep_sys_clk_n),
    .sys_rst_n       (sys_rst_n),
    .pci_exp_txp     (ep_txp),
    .pci_exp_txn     (ep_txn),
    .pci_exp_rxp     (ep_rxp),
    .pci_exp_rxn     (ep_rxn),
    .phy_ready       (ep_phy_ready),
    .link_up         (ep_link_up),
    .cfg_ltssm_state (ep_ltssm),
    .pipe_clk_o      (),
    .user_clk_o      ()
  );

  // Second Endpoint-shaped shell as serial peer (training peer until RP MODE exists).
  rivet_pg239_ep #(
    .LANES (LANES)
  ) u_peer (
    .sys_clk_p       (rp_sys_clk_p),
    .sys_clk_n       (rp_sys_clk_n),
    .sys_rst_n       (sys_rst_n),
    .pci_exp_txp     (rp_txp),
    .pci_exp_txn     (rp_txn),
    .pci_exp_rxp     (rp_rxp),
    .pci_exp_rxn     (rp_rxn),
    .phy_ready       (rp_phy_ready),
    .link_up         (rp_link_up),
    .cfg_ltssm_state (rp_ltssm),
    .pipe_clk_o      (),
    .user_clk_o      ()
  );

  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge ep_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

  initial begin
    wait (sys_rst_n === 1'b1);
    $display("[%t] : Waiting for both PHY ready...", $realtime);
    wait (ep_phy_ready && rp_phy_ready);
    $display("[%t] : Both PHY ready — Rivet LTSSM running", $realtime);

    fork
      begin
        wait (ep_link_up && rp_link_up);
        #10000;
        $display("[%t] : EP ltssm=%0h peer ltssm=%0h", $realtime, ep_ltssm, rp_ltssm);
        $display("[%t] : Test Completed Successfully (Rivet+PG239 link_up)", $realtime);
        $finish;
      end
      begin
        // 5 ms @ 1ps timescale.
        #(64'd5000000000);
        $display("[%t] : TIMEOUT — EP link_up=%0b ltssm=%0h peer link_up=%0b ltssm=%0h",
                 $realtime, ep_link_up, ep_ltssm, rp_link_up, rp_ltssm);
        $fatal(1, "Rivet+PG239 link training timeout");
      end
    join
  end

  always @(ep_ltssm or rp_ltssm) begin
    $display("[%t] : LTSSM ep=%0h peer=%0h link_up ep=%0b peer=%0b",
             $realtime, ep_ltssm, rp_ltssm, ep_link_up, rp_link_up);
  end

endmodule
