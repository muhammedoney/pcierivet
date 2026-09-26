// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Dual-DLL + MAC STP/SDP loop: InitFC, TLP+LCRC, ACK DLLP on the symbol wire.

`timescale 1ns/1ps

module rivet_dll_mac_tlp_tb;
  import rivet_pkg::*;

  localparam int unsigned LANES = 4;
  localparam int unsigned PIPE_W = 16;
  localparam int unsigned SLOT = 32;

  logic clk, rst_n;

  rivet_mac_dll_sb_t mac_a, mac_b;
  rivet_tl_dll_fc_sb_t tl_a, tl_b;
  rivet_dll_tl_fc_sb_t dll_tl_a, dll_tl_b;
  rivet_dll_mac_sb_t dll_mac_a, dll_mac_b;

  rivet_dll_mac_tx_beat_t tx_a, tx_b;
  logic                   txv_a, txv_b, txr_a, txr_b;
  rivet_dll_mac_rx_beat_t rx_a, rx_b;
  logic                   rxv_a, rxv_b, rxr_a, rxr_b;

  logic [PIPE_W*LANES-1:0] sym_ab, sym_ba;
  logic [2*LANES-1:0]      k_ab, k_ba, osd_ab, osd_ba;
  logic                    v_ab, v_ba;
  logic [11:0]             sent_ab, sent_ba;

  logic [63:0] txd_a, rxd_b;
  logic [7:0]  txk_a, rxk_b;
  logic        txl_a, txv_tl_a, txr_tl_a;
  logic        rxl_b, rxv_tl_b, rxr_tl_b;
  logic [11:0] rxseq_b;
  logic        unused_a_rxv, unused_b_txr;
  logic [63:0] unused_a_rxd;
  logic [7:0]  unused_a_rxk;
  logic        unused_a_rxl;
  logic [11:0] unused_a_rxs;

  rivet_tl_fc_stub #(.PH_CRED(8'h08), .NPH_CRED(8'h04)) u_tl_a (
    .clk_i(clk), .rst_ni(rst_n),
    .free_ph_i(1'b0), .free_pd_i(1'b0),
    .free_nph_i(1'b0), .free_npd_i(1'b0),
    .free_cplh_i(1'b0), .free_cpld_i(1'b0),
    .free_ph_amt_i(8'd0), .free_pd_amt_i(12'd0),
    .free_nph_amt_i(8'd0), .free_npd_amt_i(12'd0),
    .free_cplh_amt_i(8'd0), .free_cpld_amt_i(12'd0),
    .consume_ph_i(1'b0), .consume_pd_i(1'b0),
    .consume_nph_i(1'b0), .consume_npd_i(1'b0),
    .consume_cplh_i(1'b0), .consume_cpld_i(1'b0),
    .consume_ph_amt_i(8'd0), .consume_pd_amt_i(12'd0),
    .consume_nph_amt_i(8'd0), .consume_npd_amt_i(12'd0),
    .consume_cplh_amt_i(8'd0), .consume_cpld_amt_i(12'd0),
    .tl_to_dll_fc_o(tl_a), .dll_to_tl_fc_i(dll_tl_a)
  );
  rivet_tl_fc_stub #(.PH_CRED(8'h08), .NPH_CRED(8'h04)) u_tl_b (
    .clk_i(clk), .rst_ni(rst_n),
    .free_ph_i(1'b0), .free_pd_i(1'b0),
    .free_nph_i(1'b0), .free_npd_i(1'b0),
    .free_cplh_i(1'b0), .free_cpld_i(1'b0),
    .free_ph_amt_i(8'd0), .free_pd_amt_i(12'd0),
    .free_nph_amt_i(8'd0), .free_npd_amt_i(12'd0),
    .free_cplh_amt_i(8'd0), .free_cpld_amt_i(12'd0),
    .consume_ph_i(1'b0), .consume_pd_i(1'b0),
    .consume_nph_i(1'b0), .consume_npd_i(1'b0),
    .consume_cplh_i(1'b0), .consume_cpld_i(1'b0),
    .consume_ph_amt_i(8'd0), .consume_pd_amt_i(12'd0),
    .consume_nph_amt_i(8'd0), .consume_npd_amt_i(12'd0),
    .consume_cplh_amt_i(8'd0), .consume_cpld_amt_i(12'd0),
    .tl_to_dll_fc_o(tl_b), .dll_to_tl_fc_i(dll_tl_b)
  );

  rivet_dll #(
    .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000),
    .REPLAY_TLP_SLOTS(4), .REPLAY_SLOT_BYTES(SLOT),
    .REPLAY_TIMER_CYC(1024), .REPLAY_NUM_LIMIT(7)
  ) u_dll_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_a), .dll_tx_valid_o(txv_a), .dll_tx_ready_i(txr_a),
    .dll_rx_beat_i(rx_a), .dll_rx_valid_i(rxv_a), .dll_rx_ready_o(rxr_a),
    .mac_to_dll_sb_i(mac_a), .dll_to_mac_sb_o(dll_mac_a),
    .tl_to_dll_fc_i(tl_a), .dll_to_tl_fc_o(dll_tl_a),
    .tl_tx_tdata_i(txd_a), .tl_tx_tkeep_i(txk_a), .tl_tx_tlast_i(txl_a),
    .tl_tx_tvalid_i(txv_tl_a), .tl_tx_tready_o(txr_tl_a),
    .tl_rx_tdata_o(unused_a_rxd), .tl_rx_tkeep_o(unused_a_rxk),
    .tl_rx_tlast_o(unused_a_rxl), .tl_rx_tvalid_o(unused_a_rxv),
    .tl_rx_tready_i(1'b1), .tl_rx_seq_o(unused_a_rxs)
  );

  rivet_dll #(
    .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000),
    .REPLAY_TLP_SLOTS(4), .REPLAY_SLOT_BYTES(SLOT),
    .REPLAY_TIMER_CYC(1024), .REPLAY_NUM_LIMIT(7)
  ) u_dll_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_b), .dll_tx_valid_o(txv_b), .dll_tx_ready_i(txr_b),
    .dll_rx_beat_i(rx_b), .dll_rx_valid_i(rxv_b), .dll_rx_ready_o(rxr_b),
    .mac_to_dll_sb_i(mac_b), .dll_to_mac_sb_o(dll_mac_b),
    .tl_to_dll_fc_i(tl_b), .dll_to_tl_fc_o(dll_tl_b),
    .tl_tx_tdata_i(64'd0), .tl_tx_tkeep_i(8'd0), .tl_tx_tlast_i(1'b0),
    .tl_tx_tvalid_i(1'b0), .tl_tx_tready_o(unused_b_txr),
    .tl_rx_tdata_o(rxd_b), .tl_rx_tkeep_o(rxk_b),
    .tl_rx_tlast_o(rxl_b), .tl_rx_tvalid_o(rxv_tl_b),
    .tl_rx_tready_i(rxr_tl_b), .tl_rx_seq_o(rxseq_b)
  );

  rivet_mac_os_tx #(.LANES(LANES), .PIPE_DATA_WIDTH(PIPE_W), .SKP_INTERVAL_SYM(1180)) u_tx_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .os_req_i(RIVET_MAC_OS_IDLE), .os_req_valid_i(1'b1), .os_cnt_clr_i(1'b0),
    .lane_en_i({LANES{1'b1}}), .pkt_en_i(1'b1),
    .tx_link_num_i(8'h00), .tx_lane_num_i({LANES{8'h00}}),
    .tx_link_pad_i(1'b0), .tx_lane_pad_i(1'b0),
    .tx_n_fts_i(8'h00), .tx_rate_id_i(8'h06), .tx_train_ctrl_i(8'h00),
    .dll_tx_beat_i(tx_a), .dll_tx_valid_i(txv_a), .dll_tx_ready_o(txr_a),
    .sym_data_o(sym_ab), .sym_datak_o(k_ab), .sym_os_d_o(osd_ab),
    .sym_valid_o(v_ab), .os_sent_cnt_o(sent_ab)
  );
  rivet_mac_os_rx #(.LANES(LANES), .PIPE_DATA_WIDTH(PIPE_W)) u_rx_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .sym_data_i(sym_ab), .sym_datak_i(k_ab), .sym_valid_i({LANES{v_ab}}),
    .rxstatus_i({LANES{3'b000}}), .lane_en_i({LANES{1'b1}}), .capture_clr_i(1'b0),
    .ts1_pad_all_o(), .ts1_pad_any_o(), .ts2_pad_all_o(), .ts2_pad_any_o(),
    .ts1_link_all_o(), .ts1_link_any_o(), .ts1_lane_all_o(), .ts1_lane_any_o(),
    .ts2_cfg_all_o(), .ts2_cfg_any_o(), .idle_all_o(), .idle_any_o(),
    .idle_sym_any_o(), .rx_link_num_o(), .rx_lane_num_o(), .rx_n_fts_o(),
    .rx_rate_id_o(), .rx_train_ctrl_o(), .rx_lane_num_changed_o(),
    .polarity_inverted_o(), .deskew_done_o(), .rx_err_o(),
    .dll_rx_beat_o(rx_b), .dll_rx_valid_o(rxv_b), .dll_rx_ready_i(rxr_b)
  );

  rivet_mac_os_tx #(.LANES(LANES), .PIPE_DATA_WIDTH(PIPE_W), .SKP_INTERVAL_SYM(1180)) u_tx_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .os_req_i(RIVET_MAC_OS_IDLE), .os_req_valid_i(1'b1), .os_cnt_clr_i(1'b0),
    .lane_en_i({LANES{1'b1}}), .pkt_en_i(1'b1),
    .tx_link_num_i(8'h00), .tx_lane_num_i({LANES{8'h00}}),
    .tx_link_pad_i(1'b0), .tx_lane_pad_i(1'b0),
    .tx_n_fts_i(8'h00), .tx_rate_id_i(8'h06), .tx_train_ctrl_i(8'h00),
    .dll_tx_beat_i(tx_b), .dll_tx_valid_i(txv_b), .dll_tx_ready_o(txr_b),
    .sym_data_o(sym_ba), .sym_datak_o(k_ba), .sym_os_d_o(osd_ba),
    .sym_valid_o(v_ba), .os_sent_cnt_o(sent_ba)
  );
  rivet_mac_os_rx #(.LANES(LANES), .PIPE_DATA_WIDTH(PIPE_W)) u_rx_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .sym_data_i(sym_ba), .sym_datak_i(k_ba), .sym_valid_i({LANES{v_ba}}),
    .rxstatus_i({LANES{3'b000}}), .lane_en_i({LANES{1'b1}}), .capture_clr_i(1'b0),
    .ts1_pad_all_o(), .ts1_pad_any_o(), .ts2_pad_all_o(), .ts2_pad_any_o(),
    .ts1_link_all_o(), .ts1_link_any_o(), .ts1_lane_all_o(), .ts1_lane_any_o(),
    .ts2_cfg_all_o(), .ts2_cfg_any_o(), .idle_all_o(), .idle_any_o(),
    .idle_sym_any_o(), .rx_link_num_o(), .rx_lane_num_o(), .rx_n_fts_o(),
    .rx_rate_id_o(), .rx_train_ctrl_o(), .rx_lane_num_changed_o(),
    .polarity_inverted_o(), .deskew_done_o(), .rx_err_o(),
    .dll_rx_beat_o(rx_a), .dll_rx_valid_o(rxv_a), .dll_rx_ready_i(rxr_a)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  int unsigned ack_seen;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) ack_seen <= 0;
    else if (rxv_a && (rx_a.pkt_type == RIVET_MAC_PKT_DLLP) &&
             (rx_a.data[7:0] == RIVET_DLLP_TYPE_ACK))
      ack_seen <= ack_seen + 1;
  end

  task automatic send_tlp(input logic [7:0] tag);
    @(negedge clk);
    txd_a = {32'h0, (tag + 8'd3), (tag + 8'd2), (tag + 8'd1), tag};
    txk_a = 8'h0F;
    txl_a = 1'b1;
    txv_tl_a = 1'b1;
    do @(negedge clk); while (!txr_tl_a);
    txv_tl_a = 1'b0;
    txl_a = 1'b0;
  endtask

  initial begin
    rst_n = 1'b0;
    mac_a = '0;
    mac_b = '0;
    txv_tl_a = 1'b0;
    txd_a = '0;
    txk_a = '0;
    txl_a = 1'b0;
    rxr_tl_b = 1'b1;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    mac_a.accept_dll_tlp = 1'b1;
    mac_a.link_up        = 1'b1;
    mac_b.accept_dll_tlp = 1'b1;
    mac_b.link_up        = 1'b1;

    wait (dll_tl_a.fc_init_done && dll_tl_b.fc_init_done);
    wait (dll_tl_a.dl_up && dll_tl_b.dl_up);
    repeat (8) @(posedge clk);

    fork
      send_tlp(8'h5A);
      begin
        int unsigned g;
        g = 0;
        while (!rxv_tl_b && g < 8000) begin
          @(posedge clk);
          g++;
        end
        if (!rxv_tl_b || rxd_b[7:0] !== 8'h5A || rxseq_b !== 12'd0) begin
          $error("MAC TLP RX fail v=%0b d0=%h seq=%0d", rxv_tl_b, rxd_b[7:0], rxseq_b);
          $fatal(1);
        end
      end
    join

    wait (ack_seen > 0);
    @(posedge clk);
    $display("PASS: rivet_dll_mac_tlp_tb acks=%0d", ack_seen);
    $finish;
  end

  initial begin
    #4_000_000;
    $error("timeout dll_mac_tlp");
    $fatal(1);
  end
endmodule : rivet_dll_mac_tlp_tb
