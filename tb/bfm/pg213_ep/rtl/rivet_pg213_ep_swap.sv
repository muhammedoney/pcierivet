// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pin-compatible swap for xilinx_pcie4_uscale_ep: serial EP = rivet_pcie_ctrl + PG239.
// Used by rivet_pg213_board (PG213 RP + usrapp Class A/C/D).
// GEN=2 soft ctrl; Speed Change off so TS advertises Gen1 toward Gen1-capped RP
// (negotiated Gen2 Speed = UVM smoke_recovery_speed_gen2_x4).

`timescale 1ps/1ps

module rivet_pg213_ep_swap #(
  parameter [4:0] PL_LINK_CAP_MAX_LINK_WIDTH = 4,
  parameter       C_DATA_WIDTH               = 64
) (
  output [(PL_LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_txp,
  output [(PL_LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_txn,
  input  [(PL_LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_rxp,
  input  [(PL_LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_rxn,

  output led_0,
  output led_1,
  output led_2,
  output led_3,
  output led_4,
  output led_5,
  output led_6,
  output led_7,

  input  clk_300MHz_p,
  input  clk_300MHz_n,

  input  sys_clk_p,
  input  sys_clk_n,
  input  sys_rst_n,

  // Board probes (not on stock Xilinx EP pin list)
  output phy_ready_o,
  output link_up_o,
  output [5:0] ltssm_state_o
);

  // Unused board clocks in soft-PHY path (kept for pin compatibility).
  wire unused_clk_p = clk_300MHz_p;
  wire unused_clk_n = clk_300MHz_n;

  logic        phy_ready;
  logic        link_up;
  logic [5:0]  cfg_ltssm_state;

  // Gen2 soft ctrl; Speed Change disabled for PG213 RP Gen1-negotiated BFM.
  rivet_pg239_ep #(
    .MODE            (0),
    .GEN             (2),
    .SPEED_CHANGE_EN (1'b0),
    .LANES           (PL_LINK_CAP_MAX_LINK_WIDTH)
  ) u_rivet_ep (
    .sys_clk_p       (sys_clk_p),
    .sys_clk_n       (sys_clk_n),
    .sys_rst_n       (sys_rst_n),
    .pci_exp_txp     (pci_exp_txp),
    .pci_exp_txn     (pci_exp_txn),
    .pci_exp_rxp     (pci_exp_rxp),
    .pci_exp_rxn     (pci_exp_rxn),
    .phy_ready       (phy_ready),
    .link_up         (link_up),
    .cfg_ltssm_state (cfg_ltssm_state),
    .pipe_clk_o      (),
    .user_clk_o      ()
  );

  assign phy_ready_o   = phy_ready;
  assign link_up_o     = link_up;
  assign ltssm_state_o = cfg_ltssm_state;

  // LED map (example-compatible intent)
  assign led_0 = sys_rst_n;
  assign led_1 = 1'b0;
  assign led_2 = phy_ready;
  assign led_3 = link_up;
  assign led_4 = (cfg_ltssm_state == 6'h10); // L0 when encoded as such
  assign led_5 = 1'b0;
  assign led_6 = 1'b0;
  assign led_7 = 1'b0;

  // Next slice: expose AXI-ST / cfg_mgmt from rivet_pcie_ctrl and attach
  // imports/pcie_app_uscale + PIO like xilinx_pcie4_uscale_ep.

endmodule
