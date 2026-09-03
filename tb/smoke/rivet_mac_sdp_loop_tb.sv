// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// ×1 SDP framing loopback: os_tx → os_rx (no scramble). DLLP beat round-trip.

`timescale 1ns/1ps

module rivet_mac_sdp_loop_tb;
  import rivet_pkg::*;

  localparam int unsigned LANES = 4;
  localparam int unsigned PIPE_DATA_WIDTH = 16;

  logic pclk;
  logic rst_n;

  rivet_mac_os_type_e os_req;
  logic               os_req_valid;
  logic               os_cnt_clr;
  logic               pkt_en;

  rivet_dll_mac_tx_beat_t dll_tx;
  logic                   dll_tx_valid;
  logic                   dll_tx_ready;

  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data;
  logic [2*LANES-1:0]               sym_datak;
  logic [2*LANES-1:0]               sym_os_d;
  logic                             sym_valid;

  rivet_dll_mac_rx_beat_t dll_rx;
  logic                   dll_rx_valid;
  logic                   dll_rx_ready;

  // Unused OS RX training outputs
  logic ts1_pad_all, ts1_pad_any, ts2_pad_all, ts2_pad_any;
  logic ts1_link_all, ts1_link_any, ts1_lane_all, ts1_lane_any;
  logic ts2_cfg_all, ts2_cfg_any, idle_all, idle_any;
  logic [7:0] rx_link_num, rx_n_fts, rx_rate_id, rx_train_ctrl;
  logic [8*LANES-1:0] rx_lane_num;
  logic rx_lane_num_changed, deskew_done, rx_err;
  logic [LANES-1:0] polarity_inverted;
  logic [11:0] os_sent_cnt;

  rivet_mac_os_tx #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_tx (
    .pclk_i          (pclk),
    .rst_ni          (rst_n),
    .os_req_i        (os_req),
    .os_req_valid_i  (os_req_valid),
    .os_cnt_clr_i    (os_cnt_clr),
    .lane_en_i       ({LANES{1'b1}}),
    .pkt_en_i        (pkt_en),
    .tx_link_num_i   (8'h00),
    .tx_lane_num_i   ({LANES{8'h00}}),
    .tx_link_pad_i   (1'b0),
    .tx_lane_pad_i   (1'b0),
    .tx_n_fts_i      (8'h00),
    .tx_rate_id_i    (8'h06),
    .tx_train_ctrl_i (8'h00),
    .dll_tx_beat_i   (dll_tx),
    .dll_tx_valid_i  (dll_tx_valid),
    .dll_tx_ready_o  (dll_tx_ready),
    .sym_data_o      (sym_data),
    .sym_datak_o     (sym_datak),
    .sym_os_d_o      (sym_os_d),
    .sym_valid_o     (sym_valid),
    .os_sent_cnt_o   (os_sent_cnt)
  );

  rivet_mac_os_rx #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_rx (
    .pclk_i                (pclk),
    .rst_ni                (rst_n),
    .sym_data_i            (sym_data),
    .sym_datak_i           (sym_datak),
    .sym_valid_i           ({LANES{sym_valid}}),
    .rxstatus_i            ({LANES{3'b000}}),
    .lane_en_i             ({LANES{1'b1}}),
    .capture_clr_i         (1'b0),
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
    .idle_sym_any_o        (),
    .rx_link_num_o         (rx_link_num),
    .rx_lane_num_o         (rx_lane_num),
    .rx_n_fts_o            (rx_n_fts),
    .rx_rate_id_o          (rx_rate_id),
    .rx_train_ctrl_o       (rx_train_ctrl),
    .rx_lane_num_changed_o (rx_lane_num_changed),
    .polarity_inverted_o   (polarity_inverted),
    .deskew_done_o         (deskew_done),
    .rx_err_o              (rx_err),
    .dll_rx_beat_o         (dll_rx),
    .dll_rx_valid_o        (dll_rx_valid),
    .dll_rx_ready_i        (dll_rx_ready)
  );

  initial pclk = 1'b0;
  always #4 pclk = ~pclk;

  logic got;
  logic [63:0] got_data;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      got      <= 1'b0;
      got_data <= '0;
    end else if (dll_rx_valid && dll_rx_ready) begin
      got      <= 1'b1;
      got_data <= dll_rx.data;
    end
  end

  initial begin
    rst_n         = 1'b0;
    os_req        = RIVET_MAC_OS_IDLE;
    os_req_valid  = 1'b1;
    os_cnt_clr    = 1'b0;
    pkt_en        = 1'b1;
    dll_tx        = '0;
    dll_tx_valid  = 1'b0;
    dll_rx_ready  = 1'b1;

    repeat (4) @(posedge pclk);
    rst_n = 1'b1;
    repeat (2) @(posedge pclk);

    // One DLLP beat: SDP will frame data[63:0]
    dll_tx.data     = 64'h0123_4567_89AB_CDEF;
    dll_tx.keep     = 8'hFF;
    dll_tx.sop      = 1'b1;
    dll_tx.eop      = 1'b1;
    dll_tx.pkt_type = RIVET_MAC_PKT_DLLP;
    dll_tx_valid    = 1'b1;

    // Wait for accept
    wait (dll_tx_ready);
    @(posedge pclk);
    dll_tx_valid = 1'b0;

    // Wait for RX beat
    wait (got);
    @(posedge pclk);

    if (got_data !== 64'h0123_4567_89AB_CDEF) begin
      $error("SDP loopback data mismatch got=%016h", got_data);
      $fatal(1);
    end
    if (dll_rx.err) begin
      $error("SDP loopback set err");
      $fatal(1);
    end
    if (dll_rx.pkt_type !== RIVET_MAC_PKT_DLLP) begin
      $error("bad pkt_type");
      $fatal(1);
    end

    $display("PASS: rivet_mac_sdp_loop_tb");
    $finish;
  end

  initial begin
    #10000;
    $error("timeout");
    $fatal(1);
  end
endmodule : rivet_mac_sdp_loop_tb
