// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Dual-DLL multi-beat TL stream (12 B payload across two 64b beats).

`timescale 1ns/1ps

module rivet_dll_tl_stream_tb;
  import rivet_pkg::*;

  localparam int unsigned SLOT = 48;

  logic clk, rst_n;

  rivet_mac_dll_sb_t mac_a, mac_b;
  rivet_tl_dll_fc_sb_t tl_a, tl_b;
  rivet_dll_tl_fc_sb_t dll_tl_a, dll_tl_b;
  rivet_dll_mac_sb_t dll_mac_a, dll_mac_b;

  rivet_dll_mac_tx_beat_t tx_a, tx_b;
  logic                   txv_a, txv_b, txr_a, txr_b;
  rivet_dll_mac_rx_beat_t rx_a, rx_b;
  logic                   rxv_a, rxv_b, rxr_a, rxr_b;

  always_comb begin
    rx_b = '{data: tx_a.data, keep: tx_a.keep, sop: tx_a.sop, eop: tx_a.eop,
             err: 1'b0, pkt_type: tx_a.pkt_type};
    rxv_b = txv_a; txr_a = rxr_b;
    rx_a = '{data: tx_b.data, keep: tx_b.keep, sop: tx_b.sop, eop: tx_b.eop,
             err: 1'b0, pkt_type: tx_b.pkt_type};
    rxv_a = txv_b; txr_b = rxr_a;
  end

  logic [63:0] txd, rxd;
  logic [7:0]  txk, rxk;
  logic        txl, txv, txr, rxl, rxv, rxr;
  logic [11:0] rxseq;
  logic        unused_r;

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

  rivet_dll #(
    .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000),
    .REPLAY_TLP_SLOTS(4), .REPLAY_SLOT_BYTES(SLOT)
  ) u_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_a), .dll_tx_valid_o(txv_a), .dll_tx_ready_i(txr_a),
    .dll_rx_beat_i(rx_a), .dll_rx_valid_i(rxv_a), .dll_rx_ready_o(rxr_a),
    .mac_to_dll_sb_i(mac_a), .dll_to_mac_sb_o(dll_mac_a),
    .tl_to_dll_fc_i(tl_a), .dll_to_tl_fc_o(dll_tl_a),
    .tl_tx_tdata_i(txd), .tl_tx_tkeep_i(txk), .tl_tx_tlast_i(txl),
    .tl_tx_tvalid_i(txv), .tl_tx_tready_o(txr),
    .tl_rx_tdata_o(), .tl_rx_tkeep_o(), .tl_rx_tlast_o(),
    .tl_rx_tvalid_o(), .tl_rx_tready_i(1'b1), .tl_rx_seq_o()
  );

  rivet_dll #(
    .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000),
    .REPLAY_TLP_SLOTS(4), .REPLAY_SLOT_BYTES(SLOT)
  ) u_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_b), .dll_tx_valid_o(txv_b), .dll_tx_ready_i(txr_b),
    .dll_rx_beat_i(rx_b), .dll_rx_valid_i(rxv_b), .dll_rx_ready_o(rxr_b),
    .mac_to_dll_sb_i(mac_b), .dll_to_mac_sb_o(dll_mac_b),
    .tl_to_dll_fc_i(tl_b), .dll_to_tl_fc_o(dll_tl_b),
    .tl_tx_tdata_i(64'd0), .tl_tx_tkeep_i(8'd0), .tl_tx_tlast_i(1'b0),
    .tl_tx_tvalid_i(1'b0), .tl_tx_tready_o(unused_r),
    .tl_rx_tdata_o(rxd), .tl_rx_tkeep_o(rxk), .tl_rx_tlast_o(rxl),
    .tl_rx_tvalid_o(rxv), .tl_rx_tready_i(rxr), .tl_rx_seq_o(rxseq)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  initial begin
    logic [7:0] got [0:11];
    int unsigned gi, guard;
    rst_n = 1'b0;
    mac_a = '0; mac_b = '0;
    txv = 1'b0; txd = '0; txk = '0; txl = 1'b0; rxr = 1'b1;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    mac_a.accept_dll_tlp = 1'b1; mac_a.link_up = 1'b1;
    mac_b.accept_dll_tlp = 1'b1; mac_b.link_up = 1'b1;
    wait (dll_tl_a.dl_up && dll_tl_b.dl_up);
    repeat (2) @(posedge clk);

    // Beat0: 8 bytes, Beat1: 4 bytes + tlast
    @(negedge clk);
    txd = 64'h0706050403020100;
    txk = 8'hFF; txl = 1'b0; txv = 1'b1;
    do @(negedge clk); while (!txr);
    txd = 64'h00000000_0B0A0908;
    txk = 8'h0F; txl = 1'b1;
    do @(negedge clk); while (!txr);
    txv = 1'b0; txl = 1'b0;

    gi = 0;
    guard = 0;
    while (gi < 12 && guard < 5000) begin
      @(posedge clk);
      guard++;
      if (rxv) begin
        for (int unsigned i = 0; i < 8; i++) begin
          if (rxk[i] && gi < 12) begin
            got[gi] = rxd[8*i +: 8];
            gi++;
          end
        end
        if (rxl && gi != 12) begin
          $error("tlast with gi=%0d", gi);
          $fatal(1);
        end
      end
    end
    if (gi != 12 || rxseq !== 12'd0) begin
      $error("stream RX fail gi=%0d seq=%0d", gi, rxseq);
      $fatal(1);
    end
    for (int unsigned i = 0; i < 12; i++) begin
      if (got[i] !== 8'(i)) begin
        $error("byte[%0d]=%h", i, got[i]);
        $fatal(1);
      end
    end

    $display("PASS: rivet_dll_tl_stream_tb");
    $finish;
  end

  initial begin
    #2_000_000;
    $error("timeout");
    $fatal(1);
  end
endmodule : rivet_dll_tl_stream_tb
