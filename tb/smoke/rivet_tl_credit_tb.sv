// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Classify Cfg/Cpl accepts through rivet_tl_credit → stub → dual-DLL UpdateFC/CC.

`timescale 1ns/1ps

module rivet_tl_credit_tb;
  import rivet_pkg::*;

  logic clk;
  logic rst_n;

  rivet_mac_dll_sb_t mac_a, mac_b;
  rivet_tl_dll_fc_sb_t tl_a, tl_b;
  rivet_dll_tl_fc_sb_t dll_tl_a, dll_tl_b;
  rivet_dll_mac_sb_t dll_mac_a, dll_mac_b;

  rivet_dll_mac_tx_beat_t tx_a, tx_b;
  logic                   txv_a, txv_b, txr_a, txr_b;
  rivet_dll_mac_rx_beat_t rx_a, rx_b;
  logic                   rxv_a, rxv_b, rxr_a, rxr_b;

  logic        rx_acc, tx_acc;
  logic [7:0]  rx_h0, tx_h0;
  logic [9:0]  rx_len, tx_len;

  logic        free_ph, free_pd, free_nph, free_npd, free_cplh, free_cpld;
  logic [7:0]  free_ph_a, free_nph_a, free_cplh_a;
  logic [11:0] free_pd_a, free_npd_a, free_cpld_a;
  logic        cons_ph, cons_pd, cons_nph, cons_npd, cons_cplh, cons_cpld;
  logic [7:0]  cons_ph_a, cons_nph_a, cons_cplh_a;
  logic [11:0] cons_pd_a, cons_npd_a, cons_cpld_a;

  always_comb begin
    rx_b.data = tx_a.data; rx_b.keep = tx_a.keep; rx_b.sop = tx_a.sop;
    rx_b.eop = tx_a.eop; rx_b.err = 1'b0; rx_b.pkt_type = tx_a.pkt_type;
    rxv_b = txv_a; txr_a = rxr_b;

    rx_a.data = tx_b.data; rx_a.keep = tx_b.keep; rx_a.sop = tx_b.sop;
    rx_a.eop = tx_b.eop; rx_a.err = 1'b0; rx_a.pkt_type = tx_b.pkt_type;
    rxv_a = txv_b; txr_b = rxr_a;
  end

  rivet_tl_credit u_cred (
    .clk_i(clk), .rst_ni(rst_n),
    .rx_accept_i(rx_acc), .rx_hdr0_i(rx_h0), .rx_len_dw_i(rx_len),
    .tx_accept_i(tx_acc), .tx_hdr0_i(tx_h0), .tx_len_dw_i(tx_len),
    .free_ph_o(free_ph), .free_pd_o(free_pd),
    .free_nph_o(free_nph), .free_npd_o(free_npd),
    .free_cplh_o(free_cplh), .free_cpld_o(free_cpld),
    .free_ph_amt_o(free_ph_a), .free_pd_amt_o(free_pd_a),
    .free_nph_amt_o(free_nph_a), .free_npd_amt_o(free_npd_a),
    .free_cplh_amt_o(free_cplh_a), .free_cpld_amt_o(free_cpld_a),
    .consume_ph_o(cons_ph), .consume_pd_o(cons_pd),
    .consume_nph_o(cons_nph), .consume_npd_o(cons_npd),
    .consume_cplh_o(cons_cplh), .consume_cpld_o(cons_cpld),
    .consume_ph_amt_o(cons_ph_a), .consume_pd_amt_o(cons_pd_a),
    .consume_nph_amt_o(cons_nph_a), .consume_npd_amt_o(cons_npd_a),
    .consume_cplh_amt_o(cons_cplh_a), .consume_cpld_amt_o(cons_cpld_a)
  );

  rivet_tl_fc_stub #(.PH_CRED(8'h05), .NPH_CRED(8'h03)) u_tl_a (
    .clk_i(clk), .rst_ni(rst_n),
    .free_ph_i(free_ph), .free_pd_i(free_pd),
    .free_nph_i(free_nph), .free_npd_i(free_npd),
    .free_cplh_i(free_cplh), .free_cpld_i(free_cpld),
    .free_ph_amt_i(free_ph_a), .free_pd_amt_i(free_pd_a),
    .free_nph_amt_i(free_nph_a), .free_npd_amt_i(free_npd_a),
    .free_cplh_amt_i(free_cplh_a), .free_cpld_amt_i(free_cpld_a),
    .consume_ph_i(cons_ph), .consume_pd_i(cons_pd),
    .consume_nph_i(cons_nph), .consume_npd_i(cons_npd),
    .consume_cplh_i(cons_cplh), .consume_cpld_i(cons_cpld),
    .consume_ph_amt_i(cons_ph_a), .consume_pd_amt_i(cons_pd_a),
    .consume_nph_amt_i(cons_nph_a), .consume_npd_amt_i(cons_npd_a),
    .consume_cplh_amt_i(cons_cplh_a), .consume_cpld_amt_i(cons_cpld_a),
    .tl_to_dll_fc_o(tl_a), .dll_to_tl_fc_i(dll_tl_a)
  );

  rivet_tl_fc_stub #(.PH_CRED(8'h11), .NPH_CRED(8'h07), .CPL_INF(1'b1)) u_tl_b (
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

  rivet_dll #(.INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(4)) u_dll_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_a), .dll_tx_valid_o(txv_a), .dll_tx_ready_i(txr_a),
    .dll_rx_beat_i(rx_a), .dll_rx_valid_i(rxv_a), .dll_rx_ready_o(rxr_a),
    .mac_to_dll_sb_i(mac_a), .dll_to_mac_sb_o(dll_mac_a),
    .tl_to_dll_fc_i(tl_a), .dll_to_tl_fc_o(dll_tl_a),
    .tl_tx_tdata_i('0), .tl_tx_tkeep_i('0), .tl_tx_tlast_i(1'b0),
    .tl_tx_tvalid_i(1'b0), .tl_tx_tready_o(),
    .tl_rx_tdata_o(), .tl_rx_tkeep_o(), .tl_rx_tlast_o(),
    .tl_rx_tvalid_o(), .tl_rx_tready_i(1'b1), .tl_rx_seq_o()
  );

  rivet_dll #(.INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(4)) u_dll_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_b), .dll_tx_valid_o(txv_b), .dll_tx_ready_i(txr_b),
    .dll_rx_beat_i(rx_b), .dll_rx_valid_i(rxv_b), .dll_rx_ready_o(rxr_b),
    .mac_to_dll_sb_i(mac_b), .dll_to_mac_sb_o(dll_mac_b),
    .tl_to_dll_fc_i(tl_b), .dll_to_tl_fc_o(dll_tl_b),
    .tl_tx_tdata_i('0), .tl_tx_tkeep_i('0), .tl_tx_tlast_i(1'b0),
    .tl_tx_tvalid_i(1'b0), .tl_tx_tready_o(),
    .tl_rx_tdata_o(), .tl_rx_tkeep_o(), .tl_rx_tlast_o(),
    .tl_rx_tvalid_o(), .tl_rx_tready_i(1'b1), .tl_rx_seq_o()
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic pulse_rx(input logic [7:0] h0, input logic [9:0] ln);
    begin
      @(posedge clk);
      rx_acc <= 1'b1;
      rx_h0  <= h0;
      rx_len <= ln;
      @(posedge clk);
      rx_acc <= 1'b0;
    end
  endtask

  initial begin
    rst_n  = 1'b0;
    mac_a  = '0;
    mac_b  = '0;
    rx_acc = 1'b0;
    tx_acc = 1'b0;
    rx_h0  = '0;
    tx_h0  = '0;
    rx_len = '0;
    tx_len = '0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    mac_a.accept_dll_tlp = 1'b1;
    mac_a.link_up        = 1'b1;
    mac_b.accept_dll_tlp = 1'b1;
    mac_b.link_up        = 1'b1;

    wait (dll_tl_a.fc_init_done && dll_tl_b.fc_init_done);
    @(posedge clk);

    if (dll_tl_b.cl.nph !== 8'h03) begin
      $error("pre NPH CL=%h", dll_tl_b.cl.nph);
      $fatal(1);
    end

    // Three CfgRd accepts: CA.nph 3→6; peer CL follows via UpdateFC-NP.
    pulse_rx(RIVET_TLP_B0_CFGRD0, 10'd1);
    pulse_rx(RIVET_TLP_B0_CFGRD0, 10'd1);
    pulse_rx(RIVET_TLP_B0_CFGRD0, 10'd1);

    wait (dll_tl_b.cl.nph === 8'h06);
    @(posedge clk);
    if (tl_a.ca.nph !== 8'h06) begin
      $error("A CA.nph=%h", tl_a.ca.nph);
      $fatal(1);
    end

    // Cpl TX consume against peer infinite CPL: CC moves, gate stays open.
    @(posedge clk);
    tx_acc <= 1'b1;
    tx_h0  <= RIVET_TLP_B0_CPL;
    tx_len <= 10'd0;
    @(posedge clk);
    tx_acc <= 1'b0;
    repeat (4) @(posedge clk);

    if (dll_tl_a.cc.cplh !== 8'd1) begin
      $error("CC.cplh=%h", dll_tl_a.cc.cplh);
      $fatal(1);
    end
    if (!dll_tl_a.cplh_ok) begin
      $error("cplh_ok dropped on infinite peer CPL");
      $fatal(1);
    end

    $display("PASS: rivet_tl_credit_tb");
    $finish;
  end

  initial begin
    #500000;
    $error("timeout nph=%h cc_cplh=%h", dll_tl_b.cl.nph, dll_tl_a.cc.cplh);
    $fatal(1);
  end
endmodule : rivet_tl_credit_tb
