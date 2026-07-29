// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC layer wrapper: LTSSM + OS TX/RX + PIPE adapter (pclk domain).

module rivet_mac #(
  parameter int unsigned MODE            = 0,
  parameter int unsigned GEN             = 2,
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  // DLL <-> MAC (payload + sideband) — open for DLL stub
  input  rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_i,
  input  logic                              dll_tx_valid_i,
  output logic                              dll_tx_ready_o,
  output rivet_pkg::rivet_dll_mac_rx_beat_t dll_rx_beat_o,
  output logic                              dll_rx_valid_o,
  input  logic                              dll_rx_ready_i,
  output rivet_pkg::rivet_mac_dll_sb_t      mac_to_dll_sb_o,
  input  rivet_pkg::rivet_dll_mac_sb_t      dll_to_mac_sb_i,

  output rivet_pkg::rivet_ltssm_state_e ltssm_state_o,
  output logic                          link_up_o,

  // Flat PIPE (PG239-aligned)
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

  logic                    ts1_detected;
  logic                    ts2_detected;
  logic                    rx_error;
  logic                    txdetectrx;
  logic [LANES-1:0]        txelecidle;
  logic [1:0]              powerdown;
  logic [2:0]              rate;
  logic                    as_mac_in_detect;
  logic                    as_cdr_hold_req;
  logic                    as_mac_in_L0;
  rivet_mac_os_type_e      os_req;
  logic                    os_req_valid;

  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_tx_data;
  logic [2*LANES-1:0]               sym_tx_datak;
  logic                             sym_tx_valid;
  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_rx_data;
  logic [2*LANES-1:0]               sym_rx_datak;
  logic [LANES-1:0]                 sym_rx_valid;
  logic [3*LANES-1:0]               rxstatus;

  rivet_ltssm #(
    .MODE  (MODE),
    .GEN   (GEN),
    .LANES (LANES)
  ) u_ltssm (
    .pclk_i              (pclk_i),
    .rst_ni              (rst_ni),
    .ts1_detected_i      (ts1_detected),
    .ts2_detected_i      (ts2_detected),
    .rx_error_i          (rx_error),
    .txdetectrx_o        (txdetectrx),
    .txelecidle_o        (txelecidle),
    .powerdown_o         (powerdown),
    .rate_o              (rate),
    .as_mac_in_detect_o  (as_mac_in_detect),
    .as_cdr_hold_req_o   (as_cdr_hold_req),
    .as_mac_in_L0_o      (as_mac_in_L0),
    .ltssm_state_o       (ltssm_state_o),
    .link_up_o           (link_up_o),
    .os_req_o            (os_req),
    .os_req_valid_o      (os_req_valid)
  );

  rivet_mac_os_tx #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_os_tx (
    .pclk_i         (pclk_i),
    .rst_ni         (rst_ni),
    .os_req_i       (os_req),
    .os_req_valid_i (os_req_valid),
    .dll_tx_beat_i  (dll_tx_beat_i),
    .dll_tx_valid_i (dll_tx_valid_i),
    .dll_tx_ready_o (dll_tx_ready_o),
    .sym_data_o     (sym_tx_data),
    .sym_datak_o    (sym_tx_datak),
    .sym_valid_o    (sym_tx_valid)
  );

  rivet_mac_os_rx #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_os_rx (
    .pclk_i         (pclk_i),
    .rst_ni         (rst_ni),
    .sym_data_i     (sym_rx_data),
    .sym_datak_i    (sym_rx_datak),
    .sym_valid_i    (sym_rx_valid),
    .rxstatus_i     (rxstatus),
    .ts1_detected_o (ts1_detected),
    .ts2_detected_o (ts2_detected),
    .rx_error_o     (rx_error),
    .dll_rx_beat_o  (dll_rx_beat_o),
    .dll_rx_valid_o (dll_rx_valid_o),
    .dll_rx_ready_i (dll_rx_ready_i)
  );

  rivet_mac_pipe_adapter #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_pipe_adapter (
    .pclk_i                  (pclk_i),
    .rst_ni                  (rst_ni),
    .sym_tx_data_i           (sym_tx_data),
    .sym_tx_datak_i          (sym_tx_datak),
    .sym_tx_valid_i          (sym_tx_valid),
    .txdetectrx_i            (txdetectrx),
    .txelecidle_i            (txelecidle),
    .powerdown_i             (powerdown),
    .rate_i                  (rate),
    .as_mac_in_detect_i      (as_mac_in_detect),
    .as_cdr_hold_req_i       (as_cdr_hold_req),
    .as_mac_in_L0_i          (as_mac_in_L0),
    .sym_rx_data_o           (sym_rx_data),
    .sym_rx_datak_o          (sym_rx_datak),
    .sym_rx_valid_o          (sym_rx_valid),
    .rxstatus_o              (rxstatus),
    .pipe_txdata_o           (pipe_txdata_o),
    .pipe_txdatak_o          (pipe_txdatak_o),
    .pipe_txdata_valid_o     (pipe_txdata_valid_o),
    .pipe_txstart_block_o    (pipe_txstart_block_o),
    .pipe_txsync_header_o    (pipe_txsync_header_o),
    .pipe_rxdata_i           (pipe_rxdata_i),
    .pipe_rxdatak_i          (pipe_rxdatak_i),
    .pipe_rxdata_valid_i     (pipe_rxdata_valid_i),
    .pipe_rxstart_block_i    (pipe_rxstart_block_i),
    .pipe_rxsync_header_i    (pipe_rxsync_header_i),
    .pipe_txdetectrx_o       (pipe_txdetectrx_o),
    .pipe_txelecidle_o       (pipe_txelecidle_o),
    .pipe_txcompliance_o     (pipe_txcompliance_o),
    .pipe_rxpolarity_o       (pipe_rxpolarity_o),
    .pipe_powerdown_o        (pipe_powerdown_o),
    .pipe_rate_o             (pipe_rate_o),
    .pipe_rxvalid_i          (pipe_rxvalid_i),
    .pipe_phystatus_i        (pipe_phystatus_i),
    .pipe_phystatus_rst_i    (pipe_phystatus_rst_i),
    .pipe_rxelecidle_i       (pipe_rxelecidle_i),
    .pipe_rxstatus_i         (pipe_rxstatus_i),
    .pipe_txmargin_o         (pipe_txmargin_o),
    .pipe_txswing_o          (pipe_txswing_o),
    .pipe_txdeemph_o         (pipe_txdeemph_o),
    .pipe_txeq_ctrl_o        (pipe_txeq_ctrl_o),
    .pipe_txeq_preset_o      (pipe_txeq_preset_o),
    .pipe_txeq_coeff_o       (pipe_txeq_coeff_o),
    .pipe_txeq_fs_i          (pipe_txeq_fs_i),
    .pipe_txeq_lf_i          (pipe_txeq_lf_i),
    .pipe_txeq_new_coeff_i   (pipe_txeq_new_coeff_i),
    .pipe_txeq_done_i        (pipe_txeq_done_i),
    .pipe_rxeq_ctrl_o        (pipe_rxeq_ctrl_o),
    .pipe_rxeq_txpreset_o    (pipe_rxeq_txpreset_o),
    .pipe_rxeq_preset_sel_i  (pipe_rxeq_preset_sel_i),
    .pipe_rxeq_new_txcoeff_i (pipe_rxeq_new_txcoeff_i),
    .pipe_rxeq_adapt_done_i  (pipe_rxeq_adapt_done_i),
    .pipe_rxeq_done_i        (pipe_rxeq_done_i),
    .pipe_as_mac_in_detect_o (pipe_as_mac_in_detect_o),
    .pipe_as_cdr_hold_req_o  (pipe_as_cdr_hold_req_o),
    .pipe_as_mac_in_L0_o     (pipe_as_mac_in_L0_o),
    .pipe_cfg_rx_pm_state_o  (pipe_cfg_rx_pm_state_o)
  );

  // Sideband toward DLL (M0)
  always_comb begin
    mac_to_dll_sb_o               = '0;
    mac_to_dll_sb_o.link_up       = link_up_o;
    mac_to_dll_sb_o.ltssm_state   = ltssm_state_o;
    mac_to_dll_sb_o.accept_dll_tlp = 1'b0;
    mac_to_dll_sb_o.replay_freeze  = 1'b1;
  end

  logic _unused_dll_sb;
  assign _unused_dll_sb = |dll_to_mac_sb_i;

endmodule : rivet_mac
