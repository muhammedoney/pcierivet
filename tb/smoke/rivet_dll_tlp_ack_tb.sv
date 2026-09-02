// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Dual-DLL: after InitFC, TLP + ACK; corrupt one TLP → NAK → clean replay.

`timescale 1ns/1ps

module rivet_dll_tlp_ack_tb;
  import rivet_pkg::*;

  localparam int unsigned SLOT = 32;
  localparam int unsigned DATA_W = SLOT * 8;

  logic clk, rst_n;
  logic corrupt_arm;

  rivet_mac_dll_sb_t mac_a, mac_b;
  rivet_tl_dll_fc_sb_t tl_a, tl_b;
  rivet_dll_tl_fc_sb_t dll_tl_a, dll_tl_b;
  rivet_dll_mac_sb_t dll_mac_a, dll_mac_b;

  rivet_dll_mac_tx_beat_t tx_a, tx_b;
  logic                   txv_a, txv_b, txr_a, txr_b;
  rivet_dll_mac_rx_beat_t rx_a, rx_b;
  logic                   rxv_a, rxv_b, rxr_a, rxr_b;

  always_comb begin
    rx_b.data = tx_a.data;
    // Flip seq byte1 so LCRC and seq check both fail.
    if (corrupt_arm && txv_a && (tx_a.pkt_type == RIVET_MAC_PKT_TLP))
      rx_b.data[15:8] = tx_a.data[15:8] ^ 8'hFF;
    rx_b.keep = tx_a.keep; rx_b.sop = tx_a.sop;
    rx_b.eop = tx_a.eop; rx_b.err = 1'b0; rx_b.pkt_type = tx_a.pkt_type;
    rxv_b = txv_a; txr_a = rxr_b;

    rx_a.data = tx_b.data; rx_a.keep = tx_b.keep; rx_a.sop = tx_b.sop;
    rx_a.eop = tx_b.eop; rx_a.err = 1'b0; rx_a.pkt_type = tx_b.pkt_type;
    rxv_a = txv_b; txr_b = rxr_a;
  end

  logic                    tlv_a, tlr_a, rxv_tl_b, rxr_tl_b;
  logic [DATA_W-1:0]       tld_a, rxd_tl_b;
  logic [15:0]             tllen_a, rxlen_tl_b;
  logic [11:0]             rxseq_tl_b;
  logic unused_a_rxv, unused_b_tlr;
  logic [DATA_W-1:0] unused_a_rxd;
  logic [15:0] unused_a_rxl;
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
    .tl_tlp_valid_i(tlv_a), .tl_tlp_ready_o(tlr_a),
    .tl_tlp_data_i(tld_a), .tl_tlp_len_i(tllen_a),
    .tl_tlp_rx_valid_o(unused_a_rxv), .tl_tlp_rx_ready_i(1'b1),
    .tl_tlp_rx_data_o(unused_a_rxd), .tl_tlp_rx_len_o(unused_a_rxl),
    .tl_tlp_rx_seq_o(unused_a_rxs)
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
    .tl_tlp_valid_i(1'b0), .tl_tlp_ready_o(unused_b_tlr),
    .tl_tlp_data_i('0), .tl_tlp_len_i(16'd0),
    .tl_tlp_rx_valid_o(rxv_tl_b), .tl_tlp_rx_ready_i(rxr_tl_b),
    .tl_tlp_rx_data_o(rxd_tl_b), .tl_tlp_rx_len_o(rxlen_tl_b),
    .tl_tlp_rx_seq_o(rxseq_tl_b)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic send_tlp(input logic [7:0] tag, input logic [15:0] len);
    int unsigned i;
    int unsigned guard;
    @(negedge clk);
    tld_a = '0;
    for (i = 0; i < len; i++) tld_a[8*i +: 8] = tag + i[7:0];
    tllen_a = len;
    tlv_a = 1'b1;
    do @(negedge clk); while (!tlr_a);
    tlv_a = 1'b0;
    guard = 0;
    while (guard < 200) begin
      @(posedge clk);
      guard++;
      if (txv_a && txr_a && (tx_a.pkt_type == RIVET_MAC_PKT_TLP) && tx_a.eop)
        break;
    end
  endtask

  task automatic wait_rx(input logic [11:0] exp_seq, input logic [7:0] exp_b0,
                         input int unsigned max_cyc);
    int unsigned guard;
    guard = 0;
    while (!rxv_tl_b) begin
      @(posedge clk);
      guard++;
      if (guard >= max_cyc) begin
        $error("timeout waiting RX seq=%0d", exp_seq);
        $fatal(1);
      end
    end
    @(posedge clk);
    if (rxseq_tl_b !== exp_seq || rxd_tl_b[7:0] !== exp_b0 || rxlen_tl_b !== 16'd4) begin
      $error("RX mismatch seq=%0d d0=%h len=%0d", rxseq_tl_b, rxd_tl_b[7:0], rxlen_tl_b);
      $fatal(1);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    mac_a = '0;
    mac_b = '0;
    corrupt_arm = 1'b0;
    tlv_a = 1'b0;
    tld_a = '0;
    tllen_a = '0;
    rxr_tl_b = 1'b1;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    mac_a.accept_dll_tlp = 1'b1;
    mac_a.link_up        = 1'b1;
    mac_b.accept_dll_tlp = 1'b1;
    mac_b.link_up        = 1'b1;

    wait (dll_tl_a.fc_init_done && dll_tl_b.fc_init_done);
    repeat (4) @(posedge clk);

    fork
      send_tlp(8'h10, 16'd4);
      wait_rx(12'd0, 8'h10, 4000);
    join
    repeat (30) @(posedge clk);

    fork
      send_tlp(8'hA0, 16'd4);
      wait_rx(12'd1, 8'hA0, 4000);
    join
    repeat (30) @(posedge clk);

    // Corrupt the next on-wire TLP; drop corruption after its EOP so replay is clean.
    corrupt_arm = 1'b1;
    fork
      begin
        send_tlp(8'hB0, 16'd4);
        corrupt_arm = 1'b0;
      end
      begin
        int unsigned guard;
        logic saw_nak;
        saw_nak = 1'b0;
        guard = 0;
        while (!rxv_tl_b && guard < 8000) begin
          @(posedge clk);
          guard++;
          if (txv_b && (tx_b.pkt_type == RIVET_MAC_PKT_DLLP) &&
              (tx_b.data[7:0] == RIVET_DLLP_TYPE_NAK))
            saw_nak = 1'b1;
        end
        if (!saw_nak) begin
          $error("expected NAK before replay delivery");
          $fatal(1);
        end
        if (!rxv_tl_b) begin
          $error("timeout RX seq2 after NAK");
          $fatal(1);
        end
        @(posedge clk);
        if (rxseq_tl_b !== 12'd2 || rxd_tl_b[7:0] !== 8'hB0) begin
          $error("replay RX mismatch seq=%0d d0=%h", rxseq_tl_b, rxd_tl_b[7:0]);
          $fatal(1);
        end
      end
    join

    $display("PASS: rivet_dll_tlp_ack_tb");
    $finish;
  end

  initial begin
    #2_000_000;
    $error("timeout");
    $fatal(1);
  end
endmodule : rivet_dll_tlp_ack_tb
