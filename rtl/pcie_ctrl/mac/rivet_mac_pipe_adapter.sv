// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PIPE adapter: MAC symbol/command plane <-> flat PG239-aligned PIPE ports.

module rivet_mac_pipe_adapter #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  // From OS TX / LTSSM
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_tx_data_i,
  input  logic [2*LANES-1:0]               sym_tx_datak_i,
  input  logic                             sym_tx_valid_i,
  input  logic                             txdetectrx_i,
  input  logic [LANES-1:0]                 txelecidle_i,
  input  logic [1:0]                       powerdown_i,
  input  logic [2:0]                       rate_i,
  input  logic                             as_mac_in_detect_i,
  input  logic                             as_cdr_hold_req_i,
  input  logic                             as_mac_in_L0_i,

  // To OS RX
  output logic [PIPE_DATA_WIDTH*LANES-1:0] sym_rx_data_o,
  output logic [2*LANES-1:0]               sym_rx_datak_o,
  output logic [LANES-1:0]                 sym_rx_valid_o,
  output logic [3*LANES-1:0]               rxstatus_o,

  // Flat PIPE (controller top / PG239)
  output logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata_o,
  output logic [2*LANES-1:0]               pipe_txdatak_o,
  output logic [LANES-1:0]                 pipe_txdata_valid_o,
  output logic [LANES-1:0]                 pipe_txstart_block_o,
  output logic [2*LANES-1:0]               pipe_txsync_header_o,
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata_i,
  input  logic [2*LANES-1:0]               pipe_rxdatak_i,
  input  logic [LANES-1:0]                 pipe_rxdata_valid_i,
  input  logic [2*LANES-1:0]               pipe_rxstart_block_i,
  input  logic [2*LANES-1:0]               pipe_rxsync_header_i,
  output logic                             pipe_txdetectrx_o,
  output logic [LANES-1:0]                 pipe_txelecidle_o,
  output logic [LANES-1:0]                 pipe_txcompliance_o,
  output logic [LANES-1:0]                 pipe_rxpolarity_o,
  output logic [1:0]                       pipe_powerdown_o,
  output logic [2:0]                       pipe_rate_o,
  input  logic [LANES-1:0]                 pipe_rxvalid_i,
  input  logic [LANES-1:0]                 pipe_phystatus_i,
  input  logic [LANES-1:0]                 pipe_phystatus_rst_i,
  input  logic [LANES-1:0]                 pipe_rxelecidle_i,
  input  logic [3*LANES-1:0]               pipe_rxstatus_i,
  output logic [2:0]                       pipe_txmargin_o,
  output logic                             pipe_txswing_o,
  output logic                             pipe_txdeemph_o,
  output logic [2*LANES-1:0]               pipe_txeq_ctrl_o,
  output logic [4*LANES-1:0]               pipe_txeq_preset_o,
  output logic [6*LANES-1:0]               pipe_txeq_coeff_o,
  input  logic [5:0]                       pipe_txeq_fs_i,
  input  logic [5:0]                       pipe_txeq_lf_i,
  input  logic [18*LANES-1:0]              pipe_txeq_new_coeff_i,
  input  logic [LANES-1:0]                 pipe_txeq_done_i,
  output logic [2*LANES-1:0]               pipe_rxeq_ctrl_o,
  output logic [4*LANES-1:0]               pipe_rxeq_txpreset_o,
  input  logic [LANES-1:0]                 pipe_rxeq_preset_sel_i,
  input  logic [18*LANES-1:0]              pipe_rxeq_new_txcoeff_i,
  input  logic [LANES-1:0]                 pipe_rxeq_adapt_done_i,
  input  logic [LANES-1:0]                 pipe_rxeq_done_i,
  output logic                             pipe_as_mac_in_detect_o,
  output logic                             pipe_as_cdr_hold_req_o,
  output logic                             pipe_as_mac_in_L0_o,
  output logic [1:0]                       pipe_cfg_rx_pm_state_o
);

  // Gen2 TX data path
  assign pipe_txdata_o        = sym_tx_data_i;
  assign pipe_txdatak_o       = sym_tx_datak_i;
  assign pipe_txdata_valid_o  = '0; // Gen3+
  assign pipe_txstart_block_o = '0;
  assign pipe_txsync_header_o = '0;

  assign pipe_txdetectrx_o       = txdetectrx_i;
  assign pipe_txelecidle_o       = txelecidle_i;
  assign pipe_txcompliance_o     = '0;
  assign pipe_rxpolarity_o       = '0;
  assign pipe_powerdown_o        = powerdown_i;
  assign pipe_rate_o             = rate_i;
  assign pipe_txmargin_o         = 3'b000;
  assign pipe_txswing_o          = 1'b0;
  assign pipe_txdeemph_o         = 1'b1; // -3.5 dB default (PG239)
  assign pipe_txeq_ctrl_o        = '0;
  assign pipe_txeq_preset_o      = '0;
  assign pipe_txeq_coeff_o       = '0;
  assign pipe_rxeq_ctrl_o        = '0;
  assign pipe_rxeq_txpreset_o    = '0;
  assign pipe_as_mac_in_detect_o = as_mac_in_detect_i;
  assign pipe_as_cdr_hold_req_o  = as_cdr_hold_req_i;
  assign pipe_as_mac_in_L0_o     = as_mac_in_L0_i;
  assign pipe_cfg_rx_pm_state_o  = 2'b00;

  // RX toward OS RX (Gen2 uses rxvalid)
  assign sym_rx_data_o  = pipe_rxdata_i;
  assign sym_rx_datak_o = pipe_rxdatak_i;
  assign sym_rx_valid_o = pipe_rxvalid_i;
  assign rxstatus_o     = pipe_rxstatus_i;

  logic _unused_ok;
  assign _unused_ok = rst_ni ^ pclk_i ^ sym_tx_valid_i ^
                      (|pipe_rxdata_valid_i) ^ (|pipe_rxstart_block_i) ^
                      (|pipe_rxsync_header_i) ^ (|pipe_phystatus_i) ^
                      (|pipe_phystatus_rst_i) ^ (|pipe_rxelecidle_i) ^
                      (|pipe_txeq_fs_i) ^ (|pipe_txeq_lf_i) ^
                      (|pipe_txeq_new_coeff_i) ^ (|pipe_txeq_done_i) ^
                      (|pipe_rxeq_preset_sel_i) ^ (|pipe_rxeq_new_txcoeff_i) ^
                      (|pipe_rxeq_adapt_done_i) ^ (|pipe_rxeq_done_i);

endmodule : rivet_mac_pipe_adapter
