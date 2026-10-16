// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// SDP framing loopback: os_tx → os_rx (no scramble), plus a lane-2 STP/SDP start.

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

  // Direct RX stimulus so a frame can start on a lane other than 0.
  logic                             inj_en;
  logic [PIPE_DATA_WIDTH*LANES-1:0] inj_data;
  logic [2*LANES-1:0]               inj_datak;
  logic [PIPE_DATA_WIDTH*LANES-1:0] rx_data;
  logic [2*LANES-1:0]               rx_datak;

  assign rx_data  = inj_en ? inj_data  : sym_data;
  assign rx_datak = inj_en ? inj_datak : sym_datak;

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
  logic [LANES-1:0] ts1_link_lanes;
  logic [LANES-1:0] ts1_lane_lanes;
  logic [11:0] os_sent_cnt;

  rivet_mac_os_tx #(
    .LANES            (LANES),
    .PIPE_DATA_WIDTH  (PIPE_DATA_WIDTH),
    .SKP_INTERVAL_SYM (1180) // legal min — keeps SKP check inside timeout
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
    .sym_data_i            (rx_data),
    .sym_datak_i           (rx_datak),
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
    .ts1_link_lanes_o      (ts1_link_lanes),
    .ts1_lane_lanes_o      (ts1_lane_lanes),
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
  logic        got_err;
  logic [1:0]  got_type;
  logic        got_sop;
  logic        got_eop;
  int unsigned skp_hits;
  int unsigned beat_n;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      got      <= 1'b0;
      got_data <= '0;
      got_err  <= 1'b0;
      got_type <= '0;
      got_sop  <= 1'b0;
      got_eop  <= 1'b0;
      skp_hits <= 0;
      beat_n   <= 0;
    end else begin
      if (dll_rx_valid && dll_rx_ready) begin
        got      <= 1'b1;
        got_data <= dll_rx.data;
        got_err  <= dll_rx.err;
        got_type <= dll_rx.pkt_type;
        got_sop  <= dll_rx.sop;
        got_eop  <= dll_rx.eop;
        beat_n   <= beat_n + 1;
      end
      // Lane0 Symbol0: COM, Symbol1: SKP (16-bit PIPE, SKP OS start)
      if (sym_valid &&
          (sym_datak[0] && (sym_data[7:0] == RIVET_SYM_COM)) &&
          (sym_datak[1] && (sym_data[15:8] == RIVET_SYM_SKP)))
        skp_hits <= skp_hits + 1;
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
    inj_en        = 1'b0;
    inj_data      = '0;
    inj_datak     = '0;

    repeat (4) @(posedge pclk);
    rst_n = 1'b1;
    repeat (2) @(posedge pclk);

    // One DLLP beat: SDP frames the 6 wire bytes in data[47:0]
    dll_tx.data     = 64'h0000_4567_89AB_CDEF;
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

    if (got_data !== 64'h0000_4567_89AB_CDEF) begin
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

    // Gen1/Gen2 L0 must schedule SKP OS (COM+SKP…) after the interval.
    wait (skp_hits > 0);
    @(posedge pclk);
    if (skp_hits == 0) begin
      $error("expected L0 SKP OS");
      $fatal(1);
    end

    // Partner continues the stripe: Logical Idle on lanes 0 and 1, SDP on lane 2.
    drive_offlane(2, 1'b0, 64'h0000_1122_3344_5566, 6);
    wait (beat_n == 2);
    @(posedge pclk);
    if (got_data !== 64'h0000_1122_3344_5566 || got_err ||
        (got_type !== RIVET_MAC_PKT_DLLP)) begin
      $error("lane2 SDP mismatch data=%016h err=%0b type=%0d", got_data, got_err, got_type);
      $fatal(1);
    end

    // Same phase, STP + 4 data bytes + END. One DLL beat, sop and eop.
    drive_offlane(2, 1'b1, 64'h0000_0000_AABB_CCDD, 4);
    wait (beat_n == 3);
    @(posedge pclk);
    if (got_data[31:0] !== 32'hAABB_CCDD || got_err || !got_sop || !got_eop ||
        (got_type !== RIVET_MAC_PKT_TLP)) begin
      $error("lane2 STP mismatch data=%016h err=%0b sop=%0b eop=%0b type=%0d",
             got_data, got_err, got_sop, got_eop, got_type);
      $fatal(1);
    end

    $display("PASS: rivet_mac_sdp_loop_tb (SDP + SKP hits=%0d, lane2 SDP/STP)", skp_hits);
    $finish;
  end

  // Place STP/SDP at `start_lane` of symbol 0. Earlier lanes in that beat are Idle.
  task automatic drive_offlane(
      input int unsigned start_lane,
      input logic        stp,
      input logic [63:0] payload,
      input int unsigned nbytes);
    int unsigned pos;
    int unsigned framed;
    logic [8:0] sym;
    framed = nbytes + 2;
    inj_en = 1'b1;
    for (int unsigned base = 0; base < start_lane + framed; base += LANES * 2) begin
      inj_data  = '0;
      inj_datak = '0;
      for (int unsigned s = 0; s < 2; s++) begin
        for (int unsigned l = 0; l < LANES; l++) begin
          pos = base + s * LANES + l;
          if (pos < start_lane)
            sym = {1'b0, 8'h00};
          else if (pos == start_lane)
            sym = {1'b1, stp ? RIVET_SYM_STP : RIVET_SYM_SDP};
          else if (pos < start_lane + 1 + nbytes)
            sym = {1'b0, payload[8*(pos - start_lane - 1) +: 8]};
          else if (pos == start_lane + 1 + nbytes)
            sym = {1'b1, RIVET_SYM_END};
          else
            sym = {1'b0, 8'h00};
          inj_data[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym[7:0];
          inj_datak[2*l + s]                     = sym[8];
        end
      end
      @(posedge pclk);
    end
    inj_data  = '0;
    inj_datak = '0;
    @(posedge pclk);
    inj_en = 1'b0;
  endtask

  initial begin
    #50000;
    $error("timeout skp_hits=%0d got=%0b", skp_hits, got);
    $fatal(1);
  end
endmodule : rivet_mac_sdp_loop_tb
