// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Two rivet_dll instances exchange InitFC over a crossed DLLP beat path.

`timescale 1ns/1ps

module rivet_dll_fc_init_tb;
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

  // Cross-connect framed beats (no MAC)
  always_comb begin
    rx_b.data = tx_a.data; rx_b.keep = tx_a.keep; rx_b.sop = tx_a.sop;
    rx_b.eop = tx_a.eop; rx_b.err = 1'b0; rx_b.pkt_type = tx_a.pkt_type;
    rxv_b = txv_a; txr_a = rxr_b;

    rx_a.data = tx_b.data; rx_a.keep = tx_b.keep; rx_a.sop = tx_b.sop;
    rx_a.eop = tx_b.eop; rx_a.err = 1'b0; rx_a.pkt_type = tx_b.pkt_type;
    rxv_a = txv_b; txr_b = rxr_a;
  end

  rivet_tl_fc_stub #(.PH_CRED(8'h05), .NPH_CRED(8'h03)) u_tl_a (
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
  rivet_tl_fc_stub #(.PH_CRED(8'h11), .NPH_CRED(8'h07)) u_tl_b (
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

  rivet_dll #(.INITFC_GAP_CYC(2)) u_dll_a (
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

  rivet_dll #(.INITFC_GAP_CYC(2)) u_dll_b (
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

  initial begin
    rst_n = 1'b0;
    mac_a = '0;
    mac_b = '0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    mac_a.accept_dll_tlp = 1'b1;
    mac_a.link_up        = 1'b1;
    mac_b.accept_dll_tlp = 1'b1;
    mac_b.link_up        = 1'b1;

    wait (dll_tl_a.fc_init_done && dll_tl_b.fc_init_done);
    @(posedge clk);

    if (dll_tl_a.cl.ph !== 8'h11 || dll_tl_a.cl.nph !== 8'h07) begin
      $error("A CL mismatch ph=%h nph=%h", dll_tl_a.cl.ph, dll_tl_a.cl.nph);
      $fatal(1);
    end
    if (dll_tl_b.cl.ph !== 8'h05 || dll_tl_b.cl.nph !== 8'h03) begin
      $error("B CL mismatch ph=%h nph=%h", dll_tl_b.cl.ph, dll_tl_b.cl.nph);
      $fatal(1);
    end
    if (!dll_tl_a.cl.cplh_inf || !dll_tl_b.cl.cplh_inf) begin
      $error("CPL should be infinite");
      $fatal(1);
    end

    $display("PASS: rivet_dll_fc_init_tb");
    $finish;
  end

  initial begin
    #200000;
    $error("timeout fc_init_done a=%0b b=%0b", dll_tl_a.fc_init_done, dll_tl_b.fc_init_done);
    $fatal(1);
  end
endmodule : rivet_dll_fc_init_tb
