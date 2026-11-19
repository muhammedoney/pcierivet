// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PIPE adapter: MAC symbol/command plane <-> flat PG239-aligned PIPE ports.
// Both TX and RX boundaries are registered on pclk so transceiver hard-macro
// routing does not combine with MAC/LTSSM logic at 250 MHz.

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
  input  logic [LANES-1:0]                 rxpolarity_i,
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

  // To LTSSM: PHY handshake and receiver detection
  output logic [LANES-1:0]                 phystatus_o,
  output logic [LANES-1:0]                 phystatus_rst_o,
  output logic [LANES-1:0]                 rxelecidle_o,
  output logic [LANES-1:0]                 rxvalid_o,
  output logic [LANES-1:0]                 rx_detected_o,

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

  import rivet_pkg::*;

  logic [PIPE_DATA_WIDTH*LANES-1:0] txdata_q;
  logic [2*LANES-1:0]               txdatak_q;
  logic                             txdetectrx_q;
  logic [LANES-1:0]                 txelecidle_q;
  logic [LANES-1:0]                 rxpolarity_q;
  logic [1:0]                       powerdown_q;
  logic [2:0]                       rate_q;
  logic                             as_mac_in_detect_q;
  logic                             as_cdr_hold_req_q;
  logic                             as_mac_in_L0_q;

  logic [PIPE_DATA_WIDTH*LANES-1:0] rxdata_q;
  logic [2*LANES-1:0]               rxdatak_q;
  logic [LANES-1:0]                 rxvalid_q;
  logic [3*LANES-1:0]               rxstatus_q;
  logic [LANES-1:0]                 phystatus_q;
  logic [LANES-1:0]                 phystatus_rst_q;
  logic [LANES-1:0]                 rxelecidle_q;
  logic [LANES-1:0]                 rx_detected_d;
  logic [LANES-1:0]                 rx_detected_q;

  always_comb begin
    rx_detected_d = '0;
    for (int unsigned l = 0; l < LANES; l++) begin
      rx_detected_d[l] = pipe_phystatus_i[l] &&
                         (pipe_rxstatus_i[3*l +: 3] == RIVET_RXSTATUS_RX_DETECTED);
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      txdata_q           <= '0;
      txdatak_q          <= '0;
      txdetectrx_q       <= 1'b0;
      txelecidle_q       <= {LANES{1'b1}};
      rxpolarity_q       <= '0;
      powerdown_q        <= RIVET_PIPE_P1;
      rate_q             <= RIVET_PIPE_RATE_GEN1;
      as_mac_in_detect_q <= 1'b1;
      as_cdr_hold_req_q  <= 1'b0;
      as_mac_in_L0_q     <= 1'b0;

      rxdata_q           <= '0;
      rxdatak_q          <= '0;
      rxvalid_q          <= '0;
      rxstatus_q         <= '0;
      phystatus_q        <= '0;
      phystatus_rst_q    <= {LANES{1'b1}};
      rxelecidle_q       <= {LANES{1'b1}};
      rx_detected_q      <= '0;
    end else begin
      txdata_q           <= sym_tx_data_i;
      txdatak_q          <= sym_tx_datak_i;
      txdetectrx_q       <= txdetectrx_i;
      txelecidle_q       <= txelecidle_i;
      rxpolarity_q       <= rxpolarity_i;
      powerdown_q        <= powerdown_i;
      rate_q             <= rate_i;
      as_mac_in_detect_q <= as_mac_in_detect_i;
      as_cdr_hold_req_q  <= as_cdr_hold_req_i;
      as_mac_in_L0_q     <= as_mac_in_L0_i;

      rxdata_q           <= pipe_rxdata_i;
      rxdatak_q          <= pipe_rxdatak_i;
      rxvalid_q          <= pipe_rxvalid_i;
      rxstatus_q         <= pipe_rxstatus_i;
      phystatus_q        <= pipe_phystatus_i;
      phystatus_rst_q    <= pipe_phystatus_rst_i;
      rxelecidle_q       <= pipe_rxelecidle_i;
      rx_detected_q      <= rx_detected_d;
    end
  end

  // Gen2 TX data path
  assign pipe_txdata_o        = txdata_q;
  assign pipe_txdatak_o       = txdatak_q;
  assign pipe_txdata_valid_o  = '0; // Gen3+
  assign pipe_txstart_block_o = '0;
  assign pipe_txsync_header_o = '0;

  assign pipe_txdetectrx_o       = txdetectrx_q;
  assign pipe_txelecidle_o       = txelecidle_q;
  assign pipe_txcompliance_o     = '0;
  assign pipe_rxpolarity_o       = rxpolarity_q;
  assign pipe_powerdown_o        = powerdown_q;
  assign pipe_rate_o             = rate_q;
  assign pipe_txmargin_o         = 3'b000;
  assign pipe_txswing_o          = 1'b0;
  assign pipe_txdeemph_o         = 1'b1; // -3.5 dB default (PG239)
  assign pipe_txeq_ctrl_o        = '0;
  assign pipe_txeq_preset_o      = '0;
  assign pipe_txeq_coeff_o       = '0;
  assign pipe_rxeq_ctrl_o        = '0;
  assign pipe_rxeq_txpreset_o    = '0;
  assign pipe_as_mac_in_detect_o = as_mac_in_detect_q;
  assign pipe_as_cdr_hold_req_o  = as_cdr_hold_req_q;
  assign pipe_as_mac_in_L0_o     = as_mac_in_L0_q;
  assign pipe_cfg_rx_pm_state_o  = 2'b00;

  // RX toward OS RX (Gen2 uses rxvalid)
  assign sym_rx_data_o  = rxdata_q;
  assign sym_rx_datak_o = rxdatak_q;
  assign sym_rx_valid_o = rxvalid_q;
  assign rxstatus_o     = rxstatus_q;

  // Status toward the LTSSM
  assign phystatus_o     = phystatus_q;
  assign phystatus_rst_o = phystatus_rst_q;
  assign rxelecidle_o    = rxelecidle_q;
  assign rxvalid_o       = rxvalid_q;
  assign rx_detected_o   = rx_detected_q;

  logic _unused_ok;
  assign _unused_ok = sym_tx_valid_i ^
                      (|pipe_rxdata_valid_i) ^ (|pipe_rxstart_block_i) ^
                      (|pipe_rxsync_header_i) ^
                      (|pipe_txeq_fs_i) ^ (|pipe_txeq_lf_i) ^
                      (|pipe_txeq_new_coeff_i) ^ (|pipe_txeq_done_i) ^
                      (|pipe_rxeq_preset_sel_i) ^ (|pipe_rxeq_new_txcoeff_i) ^
                      (|pipe_rxeq_adapt_done_i) ^ (|pipe_rxeq_done_i);

endmodule : rivet_mac_pipe_adapter
