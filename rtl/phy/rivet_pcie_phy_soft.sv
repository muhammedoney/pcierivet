// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rivet soft PHY top. Simulation binds the behavioral PMA.
// Synthesis binds GTYE4_CHANNEL / GTYE4_COMMON (rivet_phy_gty_usplus).

module rivet_pcie_phy_soft
  import rivet_pkg::*;
#(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic                             phy_refclk,
  input  logic                             phy_gtrefclk,
  input  logic                             phy_rst_n,

  output logic                             pclk,
  output logic                             user_clk,
  output logic                             phy_ready,
  output logic [LANES-1:0]                 gt_gtpowergood,

  output logic [LANES-1:0]                 pci_exp_txp,
  output logic [LANES-1:0]                 pci_exp_txn,
  input  logic [LANES-1:0]                 pci_exp_rxp,
  input  logic [LANES-1:0]                 pci_exp_rxn,

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata,
  input  logic [2*LANES-1:0]               pipe_txdatak,
  input  logic [LANES-1:0]                 pipe_txdata_valid,
  input  logic [LANES-1:0]                 pipe_txstart_block,
  input  logic [2*LANES-1:0]               pipe_txsync_header,
  output logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata,
  output logic [2*LANES-1:0]               pipe_rxdatak,
  output logic [LANES-1:0]                 pipe_rxdata_valid,
  output logic [2*LANES-1:0]               pipe_rxstart_block,
  output logic [2*LANES-1:0]               pipe_rxsync_header,
  input  logic                             pipe_txdetectrx,
  input  logic [LANES-1:0]                 pipe_txelecidle,
  input  logic [LANES-1:0]                 pipe_txcompliance,
  input  logic [LANES-1:0]                 pipe_rxpolarity,
  input  logic [1:0]                       pipe_powerdown,
  input  logic [2:0]                       pipe_rate,
  output logic [LANES-1:0]                 pipe_rxvalid,
  output logic [LANES-1:0]                 pipe_phystatus,
  output logic [LANES-1:0]                 pipe_phystatus_rst,
  output logic [LANES-1:0]                 pipe_rxelecidle,
  output logic [3*LANES-1:0]               pipe_rxstatus,
  input  logic [2:0]                       pipe_txmargin,
  input  logic                             pipe_txswing,
  input  logic                             pipe_txdeemph,
  input  logic [2*LANES-1:0]               pipe_txeq_ctrl,
  input  logic [4*LANES-1:0]               pipe_txeq_preset,
  input  logic [6*LANES-1:0]               pipe_txeq_coeff,
  output logic [5:0]                       pipe_txeq_fs,
  output logic [5:0]                       pipe_txeq_lf,
  output logic [18*LANES-1:0]              pipe_txeq_new_coeff,
  output logic [LANES-1:0]                 pipe_txeq_done,
  input  logic [2*LANES-1:0]               pipe_rxeq_ctrl,
  input  logic [4*LANES-1:0]               pipe_rxeq_txpreset,
  output logic [LANES-1:0]                 pipe_rxeq_preset_sel,
  output logic [18*LANES-1:0]              pipe_rxeq_new_txcoeff,
  output logic [LANES-1:0]                 pipe_rxeq_adapt_done,
  output logic [LANES-1:0]                 pipe_rxeq_done,
  input  logic                             pipe_as_mac_in_detect,
  input  logic                             pipe_as_cdr_hold_req,

  input  logic                             inject_code_err,
  input  logic                             inject_disp_err,
  input  logic                             eb_delete_skp,
  input  logic                             eb_insert_skp,
  input  logic                             eb_flood
);

  logic [63:0] pma_txdata;
  logic [5:0]  pma_txwidth;
  logic        pma_txelecidle;
  logic        pma_txdetectrx;
  logic        pma_txpolarity;
  logic [4:0]  pma_txdiffctrl;
  logic [4:0]  pma_txprecursor;
  logic [6:0]  pma_txmaincursor;
  logic [4:0]  pma_txpostcursor;
  logic        pma_rxslide;
  logic [2:0]  pma_rate;
  logic [63:0] pma_rxdata;
  logic        pma_rxelecidle;
  logic        pma_rxdetected;
  logic        pma_resetdone;
  logic        pma_pll_lock;

  // Simulation clock is the bench refclk. Synthesis replaces both
  // clocks with BUFG_GT outputs of the GTY TXOUTCLK (Task 8).
  assign pclk      = phy_refclk;
  assign user_clk  = phy_refclk;
  assign phy_ready = pma_resetdone;

  rivet_phy_pcs #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_pcs (
    .pclk                 (pclk),
    .preset_n             (phy_rst_n),
    .pipe_txdata          (pipe_txdata),
    .pipe_txdatak         (pipe_txdatak),
    .pipe_txdata_valid    (pipe_txdata_valid),
    .pipe_txstart_block   (pipe_txstart_block),
    .pipe_txsync_header   (pipe_txsync_header),
    .pipe_rxdata          (pipe_rxdata),
    .pipe_rxdatak         (pipe_rxdatak),
    .pipe_rxdata_valid    (pipe_rxdata_valid),
    .pipe_rxstart_block   (pipe_rxstart_block),
    .pipe_rxsync_header   (pipe_rxsync_header),
    .pipe_txdetectrx      (pipe_txdetectrx),
    .pipe_txelecidle      (pipe_txelecidle),
    .pipe_txcompliance    (pipe_txcompliance),
    .pipe_rxpolarity      (pipe_rxpolarity),
    .pipe_powerdown       (pipe_powerdown),
    .pipe_rate            (pipe_rate),
    .pipe_rxvalid         (pipe_rxvalid),
    .pipe_phystatus       (pipe_phystatus),
    .pipe_phystatus_rst   (pipe_phystatus_rst),
    .pipe_rxelecidle      (pipe_rxelecidle),
    .pipe_rxstatus        (pipe_rxstatus),
    .pipe_txmargin        (pipe_txmargin),
    .pipe_txswing         (pipe_txswing),
    .pipe_txdeemph        (pipe_txdeemph),
    .pipe_txeq_ctrl       (pipe_txeq_ctrl),
    .pipe_txeq_preset     (pipe_txeq_preset),
    .pipe_txeq_coeff      (pipe_txeq_coeff),
    .pipe_txeq_fs         (pipe_txeq_fs),
    .pipe_txeq_lf         (pipe_txeq_lf),
    .pipe_txeq_new_coeff  (pipe_txeq_new_coeff),
    .pipe_txeq_done       (pipe_txeq_done),
    .pipe_rxeq_ctrl       (pipe_rxeq_ctrl),
    .pipe_rxeq_txpreset   (pipe_rxeq_txpreset),
    .pipe_rxeq_preset_sel (pipe_rxeq_preset_sel),
    .pipe_rxeq_new_txcoeff (pipe_rxeq_new_txcoeff),
    .pipe_rxeq_adapt_done (pipe_rxeq_adapt_done),
    .pipe_rxeq_done       (pipe_rxeq_done),
    .pipe_as_mac_in_detect (pipe_as_mac_in_detect),
    .pipe_as_cdr_hold_req  (pipe_as_cdr_hold_req),
    .pma_txdata           (pma_txdata),
    .pma_txwidth          (pma_txwidth),
    .pma_txelecidle       (pma_txelecidle),
    .pma_txdetectrx       (pma_txdetectrx),
    .pma_txpolarity       (pma_txpolarity),
    .pma_txdiffctrl       (pma_txdiffctrl),
    .pma_txprecursor      (pma_txprecursor),
    .pma_txmaincursor     (pma_txmaincursor),
    .pma_txpostcursor     (pma_txpostcursor),
    .pma_rxslide          (pma_rxslide),
    .pma_rate             (pma_rate),
    .pma_rxdata           (pma_rxdata),
    .pma_rxelecidle       (pma_rxelecidle),
    .pma_rxdetected       (pma_rxdetected),
    .pma_resetdone        (pma_resetdone),
    .pma_pll_lock         (pma_pll_lock)
  );

`ifndef SYNTHESIS
  assign gt_gtpowergood = {LANES{pma_resetdone}};
  assign pci_exp_txp    = '0;
  assign pci_exp_txn    = {LANES{1'b1}};

  rivet_phy_pma_model #(
    .LANES (LANES)
  ) u_pma (
    .pclk              (pclk),
    .preset_n          (phy_rst_n),
    .pma_txdata        (pma_txdata),
    .pma_txwidth       (pma_txwidth),
    .pma_txelecidle    (pma_txelecidle),
    .pma_txdetectrx    (pma_txdetectrx),
    .pma_txpolarity    (pma_txpolarity),
    .pma_txdiffctrl    (pma_txdiffctrl),
    .pma_txprecursor   (pma_txprecursor),
    .pma_txmaincursor  (pma_txmaincursor),
    .pma_txpostcursor  (pma_txpostcursor),
    .pma_rxslide       (pma_rxslide),
    .pma_rate          (pma_rate),
    .pma_rxdata        (pma_rxdata),
    .pma_rxelecidle    (pma_rxelecidle),
    .pma_rxdetected    (pma_rxdetected),
    .pma_resetdone     (pma_resetdone),
    .pma_pll_lock      (pma_pll_lock),
    .inject_code_err   (inject_code_err),
    .inject_disp_err   (inject_disp_err),
    .eb_delete_skp     (eb_delete_skp),
    .eb_insert_skp     (eb_insert_skp),
    .eb_flood          (eb_flood),
    .cdr_hold          (pipe_as_cdr_hold_req)
  );

  wire _unused_sim = phy_gtrefclk ^ (|pci_exp_rxp) ^ (|pci_exp_rxn);
`else
  rivet_phy_gty_usplus #(
    .LANES (LANES)
  ) u_gty (
    .phy_gtrefclk      (phy_gtrefclk),
    .phy_rst_n         (phy_rst_n),
    .pclk              (pclk),
    .user_clk          (user_clk),
    .gt_gtpowergood    (gt_gtpowergood),
    .pci_exp_txp       (pci_exp_txp),
    .pci_exp_txn       (pci_exp_txn),
    .pci_exp_rxp       (pci_exp_rxp),
    .pci_exp_rxn       (pci_exp_rxn),
    .pma_txdata        (pma_txdata),
    .pma_txwidth       (pma_txwidth),
    .pma_txelecidle    (pma_txelecidle),
    .pma_txdetectrx    (pma_txdetectrx),
    .pma_txpolarity    (pma_txpolarity),
    .pma_txdiffctrl    (pma_txdiffctrl),
    .pma_txprecursor   (pma_txprecursor),
    .pma_txmaincursor  (pma_txmaincursor),
    .pma_txpostcursor  (pma_txpostcursor),
    .pma_rxslide       (pma_rxslide),
    .pma_rate          (pma_rate),
    .pma_rxdata        (pma_rxdata),
    .pma_rxelecidle    (pma_rxelecidle),
    .pma_rxdetected    (pma_rxdetected),
    .pma_resetdone     (pma_resetdone),
    .pma_pll_lock      (pma_pll_lock)
  );
`endif

endmodule : rivet_pcie_phy_soft
