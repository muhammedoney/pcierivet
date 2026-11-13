// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rivet PCIe PHY — Cyclone 10 GX / DK-DEV-10CX220-B (10CX220YF780E5G).
// The lab project binds the Quartus Native PHY in PIPE Gen2 x4 mode
// (fpga/c10gx). Agilex 5 is not this family: it has no PIPE mode.
// This behavioral stub keeps the same PIPE port list as the US+ stub so
// rivet_pcie can select FPGA_FAMILY=3 without a vendor netlist.

module rivet_pcie_phy_c10gx #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic                             pclk,
  input  logic                             preset_n,
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
  input  logic                             pipe_as_mac_in_L0,
  input  logic [1:0]                       pipe_cfg_rx_pm_state,
  output logic [LANES-1:0]                 pci_exp_txp,
  output logic [LANES-1:0]                 pci_exp_txn,
  input  logic [LANES-1:0]                 pci_exp_rxp,
  input  logic [LANES-1:0]                 pci_exp_rxn,
  input  logic                             sys_clk,
  input  logic                             sys_reset_n
);

  rivet_pcie_phy_usplus #(
    .LANES(LANES),
    .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)
  ) u_stub (
    .*
  );

endmodule : rivet_pcie_phy_c10gx
