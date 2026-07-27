// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rivet PCIe PHY — UltraScale+ / VCU118 (XCVU9P).
// Wrap Xilinx PCIe PHY (PG239) generated for VU9P (GTY).
// PIPE <-> serial. Phase 0: behavioral stub (no vendor netlist in-repo).
// PIPE ports match rivet_pipe_if / PG239 Tables 5–15 (GT/DRP stay off this stub).

module rivet_pcie_phy_usplus #(
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

`ifndef SYNTHESIS
  initial begin
    if (!(LANES == 1 || LANES == 2 || LANES == 4))
      $error("rivet_pcie_phy_usplus LANES must be 1, 2, or 4");
  end
`endif

  assign pipe_rxdata            = '0;
  assign pipe_rxdatak           = '0;
  assign pipe_rxdata_valid      = '0;
  assign pipe_rxstart_block     = '0;
  assign pipe_rxsync_header     = '0;
  assign pipe_rxvalid           = '0;
  assign pipe_phystatus         = '0;
  assign pipe_phystatus_rst     = {LANES{~preset_n}}; // High in reset; Low when stub "ready"
  assign pipe_rxelecidle        = '1;
  assign pipe_rxstatus          = '0;
  assign pipe_txeq_fs           = 6'd0;
  assign pipe_txeq_lf           = 6'd0;
  assign pipe_txeq_new_coeff    = '0;
  assign pipe_txeq_done         = '0;
  assign pipe_rxeq_preset_sel   = '0;
  assign pipe_rxeq_new_txcoeff  = '0;
  assign pipe_rxeq_adapt_done   = '0;
  assign pipe_rxeq_done         = '0;

  assign pci_exp_txp = '0;
  assign pci_exp_txn = '1;

  // Silence unused inputs in Phase 0 stub
  wire _unused = pclk ^ pipe_txdetectrx ^ pipe_txswing ^ pipe_txdeemph ^
                 pipe_as_mac_in_detect ^ pipe_as_cdr_hold_req ^ pipe_as_mac_in_L0 ^
                 sys_clk ^ sys_reset_n ^
                 (|pipe_txdata) ^ (|pipe_txdatak) ^ (|pipe_txdata_valid) ^
                 (|pipe_txstart_block) ^ (|pipe_txsync_header) ^
                 (|pipe_txelecidle) ^ (|pipe_txcompliance) ^ (|pipe_rxpolarity) ^
                 (|pipe_powerdown) ^ (|pipe_rate) ^ (|pipe_txmargin) ^
                 (|pipe_txeq_ctrl) ^ (|pipe_txeq_preset) ^ (|pipe_txeq_coeff) ^
                 (|pipe_rxeq_ctrl) ^ (|pipe_rxeq_txpreset) ^ (|pipe_cfg_rx_pm_state) ^
                 (|pci_exp_rxp) ^ (|pci_exp_rxn);

endmodule : rivet_pcie_phy_usplus
