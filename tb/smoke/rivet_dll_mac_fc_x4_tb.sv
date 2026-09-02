// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Dual DLL + MAC ×4: InitFC over striped SDP with scrambler (no PHY).

`timescale 1ns/1ps

module rivet_dll_mac_fc_x4_tb;
  import rivet_pkg::*;

  localparam int unsigned LANES = 4;
  localparam int unsigned PDW   = 16;

  logic clk, rst_n;

  rivet_mac_dll_sb_t mac_sb_a, mac_sb_b;
  rivet_tl_dll_fc_sb_t tl_a, tl_b;
  rivet_dll_tl_fc_sb_t dll_tl_a, dll_tl_b;
  rivet_dll_mac_sb_t dll_mac_a, dll_mac_b;

  rivet_dll_mac_tx_beat_t dll_tx_a, dll_tx_b;
  logic dll_txv_a, dll_txv_b, dll_txr_a, dll_txr_b;
  rivet_dll_mac_rx_beat_t dll_rx_a, dll_rx_b;
  logic dll_rxv_a, dll_rxv_b, dll_rxr_a, dll_rxr_b;

  logic [PDW*LANES-1:0] sym_a, sym_b, scr_a, scr_b, dscr_a, dscr_b;
  logic [2*LANES-1:0]   k_a, k_b, sk_a, sk_b, dk_a, dk_b, osd_a, osd_b;
  logic                 v_a, v_b, sv_a, sv_b;
  logic [LANES-1:0]     dv_a, dv_b;
  logic [11:0]          oscnt_a, oscnt_b;

  // Cross-connect scrambled A→B and B→A
  assign dscr_a = scr_b;
  assign dk_a   = sk_b;
  assign dv_a   = {LANES{sv_b}};
  assign dscr_b = scr_a;
  assign dk_b   = sk_a;
  assign dv_b   = {LANES{sv_a}};

  rivet_tl_fc_stub #(.PH_CRED(8'h08), .NPH_CRED(8'h04)) u_tl_a (
    .clk_i(clk), .rst_ni(rst_n),
    .free_ph_i(1'b0), .free_pd_i(1'b0), .free_nph_i(1'b0), .free_npd_i(1'b0),
    .free_cplh_i(1'b0), .free_cpld_i(1'b0),
    .free_ph_amt_i(8'd0), .free_pd_amt_i(12'd0), .free_nph_amt_i(8'd0),
    .free_npd_amt_i(12'd0), .free_cplh_amt_i(8'd0), .free_cpld_amt_i(12'd0),
    .consume_ph_i(1'b0), .consume_pd_i(1'b0), .consume_nph_i(1'b0),
    .consume_npd_i(1'b0), .consume_cplh_i(1'b0), .consume_cpld_i(1'b0),
    .consume_ph_amt_i(8'd0), .consume_pd_amt_i(12'd0), .consume_nph_amt_i(8'd0),
    .consume_npd_amt_i(12'd0), .consume_cplh_amt_i(8'd0), .consume_cpld_amt_i(12'd0),
    .tl_to_dll_fc_o(tl_a), .dll_to_tl_fc_i(dll_tl_a)
  );
  rivet_tl_fc_stub #(.PH_CRED(8'h08), .NPH_CRED(8'h04)) u_tl_b (
    .clk_i(clk), .rst_ni(rst_n),
    .free_ph_i(1'b0), .free_pd_i(1'b0), .free_nph_i(1'b0), .free_npd_i(1'b0),
    .free_cplh_i(1'b0), .free_cpld_i(1'b0),
    .free_ph_amt_i(8'd0), .free_pd_amt_i(12'd0), .free_nph_amt_i(8'd0),
    .free_npd_amt_i(12'd0), .free_cplh_amt_i(8'd0), .free_cpld_amt_i(12'd0),
    .consume_ph_i(1'b0), .consume_pd_i(1'b0), .consume_nph_i(1'b0),
    .consume_npd_i(1'b0), .consume_cplh_i(1'b0), .consume_cpld_i(1'b0),
    .consume_ph_amt_i(8'd0), .consume_pd_amt_i(12'd0), .consume_nph_amt_i(8'd0),
    .consume_npd_amt_i(12'd0), .consume_cplh_amt_i(8'd0), .consume_cpld_amt_i(12'd0),
    .tl_to_dll_fc_o(tl_b), .dll_to_tl_fc_i(dll_tl_b)
  );

  rivet_dll #(.LANES(LANES), .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000)) u_dll_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(dll_tx_a), .dll_tx_valid_o(dll_txv_a), .dll_tx_ready_i(dll_txr_a),
    .dll_rx_beat_i(dll_rx_a), .dll_rx_valid_i(dll_rxv_a), .dll_rx_ready_o(dll_rxr_a),
    .mac_to_dll_sb_i(mac_sb_a), .dll_to_mac_sb_o(dll_mac_a),
    .tl_to_dll_fc_i(tl_a), .dll_to_tl_fc_o(dll_tl_a),
    .tl_tx_tdata_i('0), .tl_tx_tkeep_i('0), .tl_tx_tlast_i(1'b0),
    .tl_tx_tvalid_i(1'b0), .tl_tx_tready_o(),
    .tl_rx_tdata_o(), .tl_rx_tkeep_o(), .tl_rx_tlast_o(),
    .tl_rx_tvalid_o(), .tl_rx_tready_i(1'b1), .tl_rx_seq_o()
  );
  rivet_dll #(.LANES(LANES), .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000)) u_dll_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(dll_tx_b), .dll_tx_valid_o(dll_txv_b), .dll_tx_ready_i(dll_txr_b),
    .dll_rx_beat_i(dll_rx_b), .dll_rx_valid_i(dll_rxv_b), .dll_rx_ready_o(dll_rxr_b),
    .mac_to_dll_sb_i(mac_sb_b), .dll_to_mac_sb_o(dll_mac_b),
    .tl_to_dll_fc_i(tl_b), .dll_to_tl_fc_o(dll_tl_b),
    .tl_tx_tdata_i('0), .tl_tx_tkeep_i('0), .tl_tx_tlast_i(1'b0),
    .tl_tx_tvalid_i(1'b0), .tl_tx_tready_o(),
    .tl_rx_tdata_o(), .tl_rx_tkeep_o(), .tl_rx_tlast_o(),
    .tl_rx_tvalid_o(), .tl_rx_tready_i(1'b1), .tl_rx_seq_o()
  );

  rivet_mac_os_tx #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_tx_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .os_req_i(RIVET_MAC_OS_IDLE), .os_req_valid_i(1'b1), .os_cnt_clr_i(1'b0),
    .lane_en_i({LANES{1'b1}}), .pkt_en_i(mac_sb_a.accept_dll_tlp),
    .tx_link_num_i(8'h0), .tx_lane_num_i({LANES{8'h0}}),
    .tx_link_pad_i(1'b0), .tx_lane_pad_i(1'b0),
    .tx_n_fts_i(8'h0), .tx_rate_id_i(8'h06), .tx_train_ctrl_i(8'h0),
    .dll_tx_beat_i(dll_tx_a), .dll_tx_valid_i(dll_txv_a), .dll_tx_ready_o(dll_txr_a),
    .sym_data_o(sym_a), .sym_datak_o(k_a), .sym_os_d_o(osd_a), .sym_valid_o(v_a),
    .os_sent_cnt_o(oscnt_a)
  );
  rivet_mac_os_tx #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_tx_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .os_req_i(RIVET_MAC_OS_IDLE), .os_req_valid_i(1'b1), .os_cnt_clr_i(1'b0),
    .lane_en_i({LANES{1'b1}}), .pkt_en_i(mac_sb_b.accept_dll_tlp),
    .tx_link_num_i(8'h0), .tx_lane_num_i({LANES{8'h0}}),
    .tx_link_pad_i(1'b0), .tx_lane_pad_i(1'b0),
    .tx_n_fts_i(8'h0), .tx_rate_id_i(8'h06), .tx_train_ctrl_i(8'h0),
    .dll_tx_beat_i(dll_tx_b), .dll_tx_valid_i(dll_txv_b), .dll_tx_ready_o(dll_txr_b),
    .sym_data_o(sym_b), .sym_datak_o(k_b), .sym_os_d_o(osd_b), .sym_valid_o(v_b),
    .os_sent_cnt_o(oscnt_b)
  );

  rivet_mac_scrambler #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_scr_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .data_i(sym_a), .datak_i(k_a), .os_d_i(osd_a), .valid_i(v_a),
    .lane_en_i({LANES{1'b1}}), .data_o(scr_a), .datak_o(sk_a), .valid_o(sv_a)
  );
  rivet_mac_scrambler #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_scr_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .data_i(sym_b), .datak_i(k_b), .os_d_i(osd_b), .valid_i(v_b),
    .lane_en_i({LANES{1'b1}}), .data_o(scr_b), .datak_o(sk_b), .valid_o(sv_b)
  );

  logic [PDW*LANES-1:0] rx_data_a, rx_data_b;
  logic [2*LANES-1:0]   rx_k_a, rx_k_b;
  logic [LANES-1:0]     rx_v_a, rx_v_b;

  rivet_mac_descrambler #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_dscr_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .data_i(dscr_a), .datak_i(dk_a), .valid_i(dv_a), .lane_en_i({LANES{1'b1}}),
    .data_o(rx_data_a), .datak_o(rx_k_a), .valid_o(rx_v_a)
  );
  rivet_mac_descrambler #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_dscr_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .data_i(dscr_b), .datak_i(dk_b), .valid_i(dv_b), .lane_en_i({LANES{1'b1}}),
    .data_o(rx_data_b), .datak_o(rx_k_b), .valid_o(rx_v_b)
  );

  // Unused OS training outputs
  logic unused_a, unused_b;
  rivet_mac_os_rx #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_rx_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .sym_data_i(rx_data_a), .sym_datak_i(rx_k_a), .sym_valid_i(rx_v_a),
    .rxstatus_i({LANES{3'b000}}), .lane_en_i({LANES{1'b1}}), .capture_clr_i(1'b0),
    .ts1_pad_all_o(unused_a), .ts1_pad_any_o(), .ts2_pad_all_o(), .ts2_pad_any_o(),
    .ts1_link_all_o(), .ts1_link_any_o(), .ts1_lane_all_o(), .ts1_lane_any_o(),
    .ts2_cfg_all_o(), .ts2_cfg_any_o(), .idle_all_o(), .idle_any_o(),
    .rx_link_num_o(), .rx_lane_num_o(), .rx_n_fts_o(), .rx_rate_id_o(),
    .rx_train_ctrl_o(), .rx_lane_num_changed_o(), .polarity_inverted_o(),
    .deskew_done_o(), .rx_err_o(),
    .dll_rx_beat_o(dll_rx_a), .dll_rx_valid_o(dll_rxv_a), .dll_rx_ready_i(dll_rxr_a)
  );
  rivet_mac_os_rx #(.LANES(LANES), .PIPE_DATA_WIDTH(PDW)) u_rx_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .sym_data_i(rx_data_b), .sym_datak_i(rx_k_b), .sym_valid_i(rx_v_b),
    .rxstatus_i({LANES{3'b000}}), .lane_en_i({LANES{1'b1}}), .capture_clr_i(1'b0),
    .ts1_pad_all_o(unused_b), .ts1_pad_any_o(), .ts2_pad_all_o(), .ts2_pad_any_o(),
    .ts1_link_all_o(), .ts1_link_any_o(), .ts1_lane_all_o(), .ts1_lane_any_o(),
    .ts2_cfg_all_o(), .ts2_cfg_any_o(), .idle_all_o(), .idle_any_o(),
    .rx_link_num_o(), .rx_lane_num_o(), .rx_n_fts_o(), .rx_rate_id_o(),
    .rx_train_ctrl_o(), .rx_lane_num_changed_o(), .polarity_inverted_o(),
    .deskew_done_o(), .rx_err_o(),
    .dll_rx_beat_o(dll_rx_b), .dll_rx_valid_o(dll_rxv_b), .dll_rx_ready_i(dll_rxr_b)
  );

  initial clk = 0;
  always #4 clk = ~clk;

  initial begin
    rst_n = 0;
    mac_sb_a = '0;
    mac_sb_b = '0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    mac_sb_a.accept_dll_tlp = 1;
    mac_sb_a.link_up = 1;
    mac_sb_b.accept_dll_tlp = 1;
    mac_sb_b.link_up = 1;

    wait (dll_tl_a.fc_init_done && dll_tl_b.fc_init_done &&
          dll_tl_a.dl_up && dll_tl_b.dl_up);
    repeat (4) @(posedge clk);
    $display("PASS: rivet_dll_mac_fc_x4_tb");
    $finish;
  end

  initial begin
    #200000;
    $error("timeout fc_init a=%0b b=%0b dl a=%0b b=%0b tv/tr a=%0b%0b b=%0b%0b rv a=%0b b=%0b",
           dll_tl_a.fc_init_done, dll_tl_b.fc_init_done,
           dll_tl_a.dl_up, dll_tl_b.dl_up,
           dll_txv_a, dll_txr_a, dll_txv_b, dll_txr_b, dll_rxv_a, dll_rxv_b);
    $fatal(1);
  end
endmodule
