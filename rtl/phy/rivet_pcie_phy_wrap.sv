// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Board-select PHY wrapper. BOARD picks the vendor PCIe PHY the way
// Wupper's pcie_ep_wrap picks a core from CARD_TYPE.
//   RIVET_BOARD_VCU118 (0) — PG239 pcie_phy_0, link-wide PIPE controls
//   RIVET_BOARD_VMK180 (1) — PG345 pcie_phy_bd_wrapper, per-lane controls
//
// The controller still sees 16-bit Gen2 PIPE. The 64-bit PHY data pins
// are padded here. Vendor netlists are not in the repo: Vivado defines
// SYNTHESIS and supplies the generated core; simulation keeps the stub.

module rivet_pcie_phy_wrap
  import rivet_pkg::*;
#(
  parameter int unsigned BOARD           = RIVET_BOARD_VCU118,
  parameter int unsigned LANES           = 4,
  parameter int unsigned PIPE_DATA_WIDTH = 16,
  parameter int unsigned PHY_DATA_WIDTH  = 64
) (
  input  logic phy_refclk,
  input  logic phy_gtrefclk,
  input  logic phy_rst_n,

  output logic pclk,
  output logic user_clk,
  output logic phy_ready,
  output logic [LANES-1:0] gt_gtpowergood,

  output logic [LANES-1:0] pci_exp_txp,
  output logic [LANES-1:0] pci_exp_txn,
  input  logic [LANES-1:0] pci_exp_rxp,
  input  logic [LANES-1:0] pci_exp_rxn,

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

  input  logic [5:0]                       pcie_ltssm_state,
  input  logic                             pcie_link_reach_target
);

  logic [PHY_DATA_WIDTH*LANES-1:0] phy_txdata;
  logic [PHY_DATA_WIDTH*LANES-1:0] phy_rxdata;
  logic [2*LANES-1:0]              phy_txdatak;
  logic [2*LANES-1:0]              phy_rxdatak;

  // PG345 x4 (pcie_phy_versal component.xml): these controls are per lane.
  // The controller still drives one link-wide value.
  logic [LANES-1:0]   pg345_txdetectrx;
  logic [2*LANES-1:0] pg345_powerdown;
  logic [3*LANES-1:0] pg345_txmargin;
  logic [LANES-1:0]   pg345_txswing;
  logic [LANES-1:0]   pg345_txdeemph;
  logic [LANES-1:0]   pg345_rx_termination;

  assign pg345_txdetectrx    = {LANES{pipe_txdetectrx}};
  assign pg345_rx_termination = {LANES{pipe_as_mac_in_detect}};

  genvar li;
  generate
    for (li = 0; li < LANES; li++) begin : g_lane_ctl
      assign pg345_powerdown[2*li +: 2] = pipe_powerdown;
      assign pg345_txmargin[3*li +: 3]  = pipe_txmargin;
      assign pg345_txswing[li]          = pipe_txswing;
      assign pg345_txdeemph[li]         = pipe_txdeemph;
    end
  endgenerate

  rivet_pipe_pg239_pad #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH),
    .PHY_DATA_WIDTH  (PHY_DATA_WIDTH)
  ) u_pad (
    .mac_txdata  (pipe_txdata),
    .mac_txdatak (pipe_txdatak),
    .mac_rxdata  (pipe_rxdata),
    .mac_rxdatak (pipe_rxdatak),
    .phy_txdata  (phy_txdata),
    .phy_txdatak (phy_txdatak),
    .phy_rxdata  (phy_rxdata),
    .phy_rxdatak (phy_rxdatak)
  );

`ifndef SYNTHESIS
  assign pclk            = phy_refclk;
  assign user_clk        = phy_refclk;
  assign phy_ready       = phy_rst_n;
  assign gt_gtpowergood  = {LANES{phy_rst_n}};
  assign pci_exp_txp     = '0;
  assign pci_exp_txn     = {LANES{1'b1}};
  assign phy_rxdata      = '0;
  assign phy_rxdatak     = '0;
  assign pipe_rxdata_valid   = '0;
  assign pipe_rxstart_block  = '0;
  assign pipe_rxsync_header  = '0;
  assign pipe_rxvalid        = '0;
  assign pipe_phystatus      = '0;
  assign pipe_phystatus_rst  = {LANES{~phy_rst_n}};
  assign pipe_rxelecidle     = {LANES{1'b1}};
  assign pipe_rxstatus       = '0;
  assign pipe_txeq_fs        = '0;
  assign pipe_txeq_lf        = '0;
  assign pipe_txeq_new_coeff = '0;
  assign pipe_txeq_done      = '0;
  assign pipe_rxeq_preset_sel  = '0;
  assign pipe_rxeq_new_txcoeff = '0;
  assign pipe_rxeq_adapt_done  = '0;
  assign pipe_rxeq_done        = '0;

  wire _unused_stub = phy_gtrefclk ^ pipe_as_cdr_hold_req ^
                      (|pci_exp_rxp) ^ (|pci_exp_rxn) ^ (|phy_txdata) ^ (|phy_txdatak) ^
                      (|pg345_txdetectrx) ^ (|pg345_powerdown) ^ (|pg345_txmargin) ^
                      (|pg345_txswing) ^ (|pg345_txdeemph) ^ (|pg345_rx_termination) ^
                      (|pipe_txdata_valid) ^ (|pipe_txstart_block) ^ (|pipe_txsync_header) ^
                      (|pipe_txelecidle) ^ (|pipe_txcompliance) ^ (|pipe_rxpolarity) ^
                      (|pipe_rate) ^ (|pipe_txeq_ctrl) ^ (|pipe_txeq_preset) ^
                      (|pipe_txeq_coeff) ^ (|pipe_rxeq_ctrl) ^ (|pipe_rxeq_txpreset) ^
                      (|pcie_ltssm_state) ^ pcie_link_reach_target;
`else
  generate
    if (BOARD == RIVET_BOARD_VCU118) begin : g_vcu118
      logic phystatus_rst_raw;
      logic mcap_clk;
      logic core_clk;

      // PG239: txdetectrx, powerdown, rate[1:0], txmargin, txswing, txdeemph
      // are link-wide. This is the port map that closed VCU118 timing.
      pcie_phy_0 u_phy (
        .phy_refclk         (phy_refclk),
        .phy_gtrefclk       (phy_gtrefclk),
        .phy_rst_n          (phy_rst_n),
        .phy_userclk        (user_clk),
        .phy_mcapclk        (mcap_clk),
        .phy_pclk           (pclk),
        .phy_coreclk        (core_clk),
        .phy_rxp            (pci_exp_rxp),
        .phy_rxn            (pci_exp_rxn),
        .phy_txp            (pci_exp_txp),
        .phy_txn            (pci_exp_txn),
        .phy_txdata         (phy_txdata),
        .phy_txdatak        (phy_txdatak),
        .phy_txdata_valid   (pipe_txdata_valid),
        .phy_txstart_block  (pipe_txstart_block),
        .phy_txsync_header  (pipe_txsync_header),
        .phy_rxdata         (phy_rxdata),
        .phy_rxdatak        (phy_rxdatak),
        .phy_rxdata_valid   (pipe_rxdata_valid),
        .phy_rxstart_block  (pipe_rxstart_block),
        .phy_rxsync_header  (pipe_rxsync_header),
        .phy_txdetectrx     (pipe_txdetectrx),
        .phy_txelecidle     (pipe_txelecidle),
        .phy_txcompliance   (pipe_txcompliance),
        .phy_rxpolarity     (pipe_rxpolarity),
        .phy_powerdown      (pipe_powerdown),
        .phy_rate           (pipe_rate[1:0]),
        .phy_rxvalid        (pipe_rxvalid),
        .phy_phystatus      (pipe_phystatus),
        .phy_phystatus_rst  (phystatus_rst_raw),
        .phy_rxelecidle     (pipe_rxelecidle),
        .phy_rxstatus       (pipe_rxstatus),
        .phy_txmargin       (pipe_txmargin),
        .phy_txswing        (pipe_txswing),
        .phy_txdeemph       (pipe_txdeemph),
        .phy_txeq_ctrl      (pipe_txeq_ctrl),
        .phy_txeq_preset    (pipe_txeq_preset),
        .phy_txeq_coeff     (pipe_txeq_coeff),
        .phy_txeq_fs        (pipe_txeq_fs),
        .phy_txeq_lf        (pipe_txeq_lf),
        .phy_txeq_new_coeff (pipe_txeq_new_coeff),
        .phy_txeq_done      (pipe_txeq_done),
        .phy_rxeq_ctrl      (pipe_rxeq_ctrl),
        .phy_rxeq_txpreset  (pipe_rxeq_txpreset),
        .phy_rxeq_preset_sel  (pipe_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff (pipe_rxeq_new_txcoeff),
        .phy_rxeq_done      (pipe_rxeq_done),
        .phy_rxeq_adapt_done (pipe_rxeq_adapt_done),
        .gt_gtpowergood     (gt_gtpowergood),
        .as_mac_in_detect   (pipe_as_mac_in_detect),
        .as_cdr_hold_req    (pipe_as_cdr_hold_req)
      );

      assign phy_ready          = ~phystatus_rst_raw;
      assign pipe_phystatus_rst = {LANES{phystatus_rst_raw}};

      wire _unused_vcu = (|pg345_txdetectrx) ^ (|pg345_powerdown) ^
                         (|pg345_txmargin) ^ (|pg345_txswing) ^ (|pg345_txdeemph) ^
                         (|pg345_rx_termination) ^ mcap_clk ^ core_clk ^
                         pipe_rate[2] ^ (|pcie_ltssm_state) ^ pcie_link_reach_target;
    end else if (BOARD == RIVET_BOARD_VMK180) begin : g_vmk180
      logic phystatus_rst_raw;

      // PG345: per-lane powerdown/margin/swing/deemph/txdetectrx, and
      // phy_rx_termination (the catalog name, not phy_rxtermination).
      pcie_phy_bd_wrapper u_phy (
        .phy_refclk              (phy_refclk),
        .phy_gtrefclk            (phy_gtrefclk),
        .sys_reset               (phy_rst_n),
        .phy_pclk                (pclk),
        .phy_userclk             (user_clk),
        .phy_ready               (phy_ready),
        .phy_txp                 (pci_exp_txp),
        .phy_txn                 (pci_exp_txn),
        .phy_rxp                 (pci_exp_rxp),
        .phy_rxn                 (pci_exp_rxn),
        .phy_txdata              (phy_txdata),
        .phy_txdatak             (phy_txdatak),
        .phy_txdata_valid        (pipe_txdata_valid),
        .phy_txstart_block       (pipe_txstart_block),
        .phy_txsync_header       (pipe_txsync_header),
        .phy_rxdata              (phy_rxdata),
        .phy_rxdatak             (phy_rxdatak),
        .phy_rxdata_valid        (pipe_rxdata_valid),
        .phy_rxstart_block       (pipe_rxstart_block),
        .phy_rxsync_header       (pipe_rxsync_header),
        .phy_txdetectrx_loopback (pg345_txdetectrx),
        .phy_txelecidle          (pipe_txelecidle),
        .phy_txcompliance        (pipe_txcompliance),
        .phy_rxpolarity          (pipe_rxpolarity),
        .phy_powerdown           (pg345_powerdown),
        .phy_rate                (pipe_rate),
        .phy_rx_termination      (pg345_rx_termination),
        .phy_rxvalid             (pipe_rxvalid),
        .phy_phystatus           (pipe_phystatus),
        .phy_phystatus_rst       (phystatus_rst_raw),
        .phy_rxelecidle          (pipe_rxelecidle),
        .phy_rxstatus            (pipe_rxstatus),
        .phy_txmargin            (pg345_txmargin),
        .phy_txswing             (pg345_txswing),
        .phy_txdeemph            (pg345_txdeemph),
        .phy_txeq_ctrl           (pipe_txeq_ctrl),
        .phy_txeq_preset         (pipe_txeq_preset),
        .phy_txeq_coeff          (pipe_txeq_coeff),
        .phy_txeq_fs             (pipe_txeq_fs),
        .phy_txeq_lf             (pipe_txeq_lf),
        .phy_txeq_new_coeff      (pipe_txeq_new_coeff),
        .phy_txeq_done           (pipe_txeq_done),
        .phy_rxeq_ctrl           (pipe_rxeq_ctrl),
        .phy_rxeq_txpreset       (pipe_rxeq_txpreset),
        .phy_rxeq_preset_sel     (pipe_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff    (pipe_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done     (pipe_rxeq_adapt_done),
        .phy_rxeq_done           (pipe_rxeq_done),
        .pcie_ltssm_state        (pcie_ltssm_state),
        .pcie_link_reach_target  (pcie_link_reach_target)
      );

      assign gt_gtpowergood     = {LANES{1'b1}};
      assign pipe_phystatus_rst = {LANES{phystatus_rst_raw}};

      wire _unused_vmk = pipe_as_cdr_hold_req;
    end else begin : g_bad
      initial $error("rivet_pcie_phy_wrap: BOARD %0d is not VCU118 or VMK180", BOARD);
    end
  endgenerate
`endif

endmodule : rivet_pcie_phy_wrap
