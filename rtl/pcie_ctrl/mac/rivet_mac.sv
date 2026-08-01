// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC layer wrapper: LTSSM + OS TX/RX + PIPE adapter (pclk domain).

module rivet_mac #(
  parameter int unsigned MODE            = 0,
  parameter int unsigned GEN             = 2,
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16,
  // Simulation knobs: divide every LTSSM timeout and shrink the Polling.Active
  // TS1 quota. Defaults are the silicon values.
  parameter int unsigned LTSSM_TIMER_SCALE = 1,
  parameter int unsigned N_TS1_POLLING     = rivet_pkg::RIVET_N_TS1_POLLING
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

  logic                    txdetectrx;
  logic [LANES-1:0]        txelecidle;
  logic [LANES-1:0]        rxpolarity;
  logic [1:0]              powerdown;
  logic [2:0]              rate;
  logic                    as_mac_in_detect;
  logic                    as_cdr_hold_req;
  logic                    as_mac_in_L0;

  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_tx_data;
  logic [2*LANES-1:0]               sym_tx_datak;
  logic [2*LANES-1:0]               sym_tx_os_d;
  logic                             sym_tx_valid;
  logic [PIPE_DATA_WIDTH*LANES-1:0] scr_tx_data;
  logic [2*LANES-1:0]               scr_tx_datak;
  logic                             scr_tx_valid;
  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_rx_data_raw;
  logic [2*LANES-1:0]               sym_rx_datak_raw;
  logic [LANES-1:0]                 sym_rx_valid_raw;
  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_rx_data;
  logic [2*LANES-1:0]               sym_rx_datak;
  logic [LANES-1:0]                 sym_rx_valid;
  logic [3*LANES-1:0]               rxstatus;

  logic [LANES-1:0] phystatus;
  logic [LANES-1:0] phystatus_rst;
  logic [LANES-1:0] rxelecidle;
  logic [LANES-1:0] rxvalid;
  logic [LANES-1:0] rx_detected;

  rivet_mac_os_type_e os_req;
  logic               os_req_valid;
  logic               os_cnt_clr;
  logic               capture_clr;
  logic [LANES-1:0]   lane_en;
  logic [7:0]         tx_link_num;
  logic [8*LANES-1:0] tx_lane_num;
  logic               tx_link_pad;
  logic               tx_lane_pad;
  logic [7:0]         tx_n_fts;
  logic [7:0]         tx_rate_id;
  logic [7:0]         tx_train_ctrl;
  logic [11:0]        os_sent_cnt;

  logic               ts1_pad_all,  ts1_pad_any;
  logic               ts2_pad_all,  ts2_pad_any;
  logic               ts1_link_all, ts1_link_any;
  logic               ts1_lane_all, ts1_lane_any;
  logic               ts2_cfg_all,  ts2_cfg_any;
  logic               idle_all,     idle_any;
  logic [7:0]         rx_link_num;
  logic [8*LANES-1:0] rx_lane_num;
  logic [7:0]         rx_n_fts;
  logic [7:0]         rx_rate_id;
  logic [7:0]         rx_train_ctrl;
  logic               rx_lane_num_changed;
  logic [LANES-1:0]   polarity_inverted;
  logic               deskew_done;
  logic               rx_err;

  logic [2:0]         negotiated_width;
  logic [1:0]         negotiated_speed;
  logic               accept_dll_tlp;
  logic [7:0]         remote_rate_id;
  logic [7:0]         remote_n_fts;

  rivet_ltssm #(
    .MODE               (MODE),
    .GEN                (GEN),
    .LANES              (LANES),
    .T_DETECT_QUIET_CYC (rivet_scale_cyc(RIVET_T_12MS_CYC, LTSSM_TIMER_SCALE)),
    .T_DETECT_RETRY_CYC (rivet_scale_cyc(RIVET_T_12MS_CYC, LTSSM_TIMER_SCALE)),
    .T_POLL_ACTIVE_CYC  (rivet_scale_cyc(RIVET_T_24MS_CYC, LTSSM_TIMER_SCALE)),
    .T_POLL_CFG_CYC     (rivet_scale_cyc(RIVET_T_48MS_CYC, LTSSM_TIMER_SCALE)),
    .T_CONFIG_CYC       (rivet_scale_cyc(RIVET_T_24MS_CYC, LTSSM_TIMER_SCALE)),
    .T_CFG_COMPLETE_CYC (rivet_scale_cyc(RIVET_T_2MS_CYC,  LTSSM_TIMER_SCALE)),
    .T_CFG_IDLE_CYC     (rivet_scale_cyc(RIVET_T_2MS_CYC,  LTSSM_TIMER_SCALE)),
    .T_RCVRLOCK_CYC     (rivet_scale_cyc(RIVET_T_24MS_CYC, LTSSM_TIMER_SCALE)),
    .N_TS1_POLLING      (N_TS1_POLLING)
  ) u_ltssm (
    .pclk_i               (pclk_i),
    .rst_ni               (rst_ni),
    .phystatus_i          (phystatus),
    .rx_detected_i        (rx_detected),
    .rxelecidle_i         (rxelecidle),
    .rxvalid_i            (rxvalid),
    .ts1_pad_all_i        (ts1_pad_all),
    .ts1_pad_any_i        (ts1_pad_any),
    .ts2_pad_all_i        (ts2_pad_all),
    .ts2_pad_any_i        (ts2_pad_any),
    .ts1_link_all_i       (ts1_link_all),
    .ts1_link_any_i       (ts1_link_any),
    .ts1_lane_all_i       (ts1_lane_all),
    .ts1_lane_any_i       (ts1_lane_any),
    .ts2_cfg_all_i        (ts2_cfg_all),
    .ts2_cfg_any_i        (ts2_cfg_any),
    .idle_all_i           (idle_all),
    .idle_any_i           (idle_any),
    .rx_link_num_i        (rx_link_num),
    .rx_lane_num_i        (rx_lane_num),
    .rx_rate_id_i         (rx_rate_id),
    .rx_n_fts_i           (rx_n_fts),
    .polarity_inverted_i  (polarity_inverted),
    .deskew_done_i        (deskew_done),
    .rx_err_i             (rx_err),
    .os_req_o             (os_req),
    .os_req_valid_o       (os_req_valid),
    .os_cnt_clr_o         (os_cnt_clr),
    .tx_link_num_o        (tx_link_num),
    .tx_lane_num_o        (tx_lane_num),
    .tx_link_pad_o        (tx_link_pad),
    .tx_lane_pad_o        (tx_lane_pad),
    .tx_n_fts_o           (tx_n_fts),
    .tx_rate_id_o         (tx_rate_id),
    .tx_train_ctrl_o      (tx_train_ctrl),
    .os_sent_cnt_i        (os_sent_cnt),
    .capture_clr_o        (capture_clr),
    .lane_en_o            (lane_en),
    .txdetectrx_o         (txdetectrx),
    .txelecidle_o         (txelecidle),
    .rxpolarity_o         (rxpolarity),
    .powerdown_o          (powerdown),
    .rate_o               (rate),
    .as_mac_in_detect_o   (as_mac_in_detect),
    .as_cdr_hold_req_o    (as_cdr_hold_req),
    .as_mac_in_L0_o       (as_mac_in_L0),
    .ltssm_state_o        (ltssm_state_o),
    .link_up_o            (link_up_o),
    .negotiated_width_o   (negotiated_width),
    .negotiated_speed_o   (negotiated_speed),
    .accept_dll_tlp_o     (accept_dll_tlp),
    .remote_rate_id_o     (remote_rate_id),
    .remote_n_fts_o       (remote_n_fts)
  );

  rivet_mac_os_tx #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_os_tx (
    .pclk_i          (pclk_i),
    .rst_ni          (rst_ni),
    .os_req_i        (os_req),
    .os_req_valid_i  (os_req_valid),
    .os_cnt_clr_i    (os_cnt_clr),
    .lane_en_i       (lane_en),
    .tx_link_num_i   (tx_link_num),
    .tx_lane_num_i   (tx_lane_num),
    .tx_link_pad_i   (tx_link_pad),
    .tx_lane_pad_i   (tx_lane_pad),
    .tx_n_fts_i      (tx_n_fts),
    .tx_rate_id_i    (tx_rate_id),
    .tx_train_ctrl_i (tx_train_ctrl),
    .dll_tx_beat_i   (dll_tx_beat_i),
    .dll_tx_valid_i  (dll_tx_valid_i),
    .dll_tx_ready_o  (dll_tx_ready_o),
    .sym_data_o      (sym_tx_data),
    .sym_datak_o     (sym_tx_datak),
    .sym_os_d_o      (sym_tx_os_d),
    .sym_valid_o     (sym_tx_valid),
    .os_sent_cnt_o   (os_sent_cnt)
  );

  rivet_mac_scrambler #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_scrambler (
    .pclk_i    (pclk_i),
    .rst_ni    (rst_ni),
    .data_i    (sym_tx_data),
    .datak_i   (sym_tx_datak),
    .os_d_i    (sym_tx_os_d),
    .valid_i   (sym_tx_valid),
    .lane_en_i (lane_en),
    .data_o    (scr_tx_data),
    .datak_o   (scr_tx_datak),
    .valid_o   (scr_tx_valid)
  );

  rivet_mac_descrambler #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_descrambler (
    .pclk_i    (pclk_i),
    .rst_ni    (rst_ni),
    .data_i    (sym_rx_data_raw),
    .datak_i   (sym_rx_datak_raw),
    .valid_i   (sym_rx_valid_raw),
    .lane_en_i (lane_en),
    .data_o    (sym_rx_data),
    .datak_o   (sym_rx_datak),
    .valid_o   (sym_rx_valid)
  );

  rivet_mac_os_rx #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_os_rx (
    .pclk_i                (pclk_i),
    .rst_ni                (rst_ni),
    .sym_data_i            (sym_rx_data),
    .sym_datak_i           (sym_rx_datak),
    .sym_valid_i           (sym_rx_valid),
    .rxstatus_i            (rxstatus),
    .lane_en_i             (lane_en),
    .capture_clr_i         (capture_clr),
    .ts1_pad_all_o         (ts1_pad_all),
    .ts1_pad_any_o         (ts1_pad_any),
    .ts2_pad_all_o         (ts2_pad_all),
    .ts2_pad_any_o         (ts2_pad_any),
    .ts1_link_all_o        (ts1_link_all),
    .ts1_link_any_o        (ts1_link_any),
    .ts1_lane_all_o        (ts1_lane_all),
    .ts1_lane_any_o        (ts1_lane_any),
    .ts2_cfg_all_o         (ts2_cfg_all),
    .ts2_cfg_any_o         (ts2_cfg_any),
    .idle_all_o            (idle_all),
    .idle_any_o            (idle_any),
    .rx_link_num_o         (rx_link_num),
    .rx_lane_num_o         (rx_lane_num),
    .rx_n_fts_o            (rx_n_fts),
    .rx_rate_id_o          (rx_rate_id),
    .rx_train_ctrl_o       (rx_train_ctrl),
    .rx_lane_num_changed_o (rx_lane_num_changed),
    .polarity_inverted_o   (polarity_inverted),
    .deskew_done_o         (deskew_done),
    .rx_err_o              (rx_err),
    .dll_rx_beat_o         (dll_rx_beat_o),
    .dll_rx_valid_o        (dll_rx_valid_o),
    .dll_rx_ready_i        (dll_rx_ready_i)
  );

  rivet_mac_pipe_adapter #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_pipe_adapter (
    .pclk_i                  (pclk_i),
    .rst_ni                  (rst_ni),
    .sym_tx_data_i           (scr_tx_data),
    .sym_tx_datak_i          (scr_tx_datak),
    .sym_tx_valid_i          (scr_tx_valid),
    .txdetectrx_i            (txdetectrx),
    .txelecidle_i            (txelecidle),
    .rxpolarity_i            (rxpolarity),
    .powerdown_i             (powerdown),
    .rate_i                  (rate),
    .as_mac_in_detect_i      (as_mac_in_detect),
    .as_cdr_hold_req_i       (as_cdr_hold_req),
    .as_mac_in_L0_i          (as_mac_in_L0),
    .sym_rx_data_o           (sym_rx_data_raw),
    .sym_rx_datak_o          (sym_rx_datak_raw),
    .sym_rx_valid_o          (sym_rx_valid_raw),
    .rxstatus_o              (rxstatus),
    .phystatus_o             (phystatus),
    .phystatus_rst_o         (phystatus_rst),
    .rxelecidle_o            (rxelecidle),
    .rxvalid_o               (rxvalid),
    .rx_detected_o           (rx_detected),
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

  // Sideband toward DLL. Replay stays frozen outside L0.
  always_comb begin
    mac_to_dll_sb_o                  = '0;
    mac_to_dll_sb_o.link_up          = link_up_o;
    mac_to_dll_sb_o.ltssm_state      = ltssm_state_o;
    mac_to_dll_sb_o.negotiated_width = negotiated_width;
    mac_to_dll_sb_o.negotiated_speed = negotiated_speed;
    mac_to_dll_sb_o.accept_dll_tlp   = accept_dll_tlp;
    mac_to_dll_sb_o.replay_freeze    = !accept_dll_tlp;
  end

  // DLL-driven Recovery requests and the captured peer TS fields land in later
  // milestones (Recovery, L0s).
  logic _unused_mac;
  assign _unused_mac = (|dll_to_mac_sb_i) ^ (|phystatus_rst) ^ (|rx_train_ctrl) ^
                       rx_lane_num_changed ^ (|remote_rate_id) ^ (|remote_n_fts);

endmodule : rivet_mac
