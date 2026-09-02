// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// DLLP encode → decode round-trip (InitFC1-P, UpdateFC-NP, Ack).

`timescale 1ns/1ps

module rivet_dllp_roundtrip_tb;
  import rivet_pkg::*;

  logic clk;
  logic rst_n;

  rivet_dllp_req_t req;
  logic            req_valid;
  logic            req_ready;

  rivet_dll_mac_tx_beat_t tx_beat;
  logic                   tx_valid;
  logic                   tx_ready;

  rivet_dll_mac_rx_beat_t rx_beat;
  logic                   rx_valid;
  logic                   rx_ready;

  rivet_dllp_dec_t dec;
  logic            dec_valid;
  logic            dec_ready;

  rivet_dllp_tx u_tx (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .req_i        (req),
    .req_valid_i  (req_valid),
    .req_ready_o  (req_ready),
    .beat_o       (tx_beat),
    .beat_valid_o (tx_valid),
    .beat_ready_i (tx_ready)
  );

  // Direct wire TX beat → RX beat (no MAC)
  always_comb begin
    rx_beat.data     = tx_beat.data;
    rx_beat.keep     = tx_beat.keep;
    rx_beat.sop      = tx_beat.sop;
    rx_beat.eop      = tx_beat.eop;
    rx_beat.err      = 1'b0;
    rx_beat.pkt_type = tx_beat.pkt_type;
    rx_valid         = tx_valid;
    tx_ready         = rx_ready;
  end

  rivet_dllp_rx u_rx (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .beat_i       (rx_beat),
    .beat_valid_i (rx_valid),
    .beat_ready_o (rx_ready),
    .dec_o        (dec),
    .dec_valid_o  (dec_valid),
    .dec_ready_i  (dec_ready)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic send_and_check(input rivet_dllp_req_t r);
    begin
      @(posedge clk);
      req       <= r;
      req_valid <= 1'b1;
      wait (req_ready);
      @(posedge clk);
      req_valid <= 1'b0;

      wait (dec_valid);
      @(posedge clk);
      if (!dec.crc_ok) begin
        $error("CRC fail kind=%0d", r.kind);
        $fatal(1);
      end
      if (dec.kind !== r.kind) begin
        $error("kind mismatch");
        $fatal(1);
      end
      if (r.kind == RIVET_DLLP_KIND_FC) begin
        if (dec.fc_kind !== r.fc_kind || dec.vc !== r.vc ||
            dec.hdr_fc !== r.hdr_fc || dec.data_fc !== r.data_fc) begin
          $error("FC fields mismatch");
          $fatal(1);
        end
      end else if (dec.ack_seq !== r.ack_seq) begin
        $error("ack_seq mismatch");
        $fatal(1);
      end
      // Consume
      dec_ready <= 1'b1;
      @(posedge clk);
      dec_ready <= 1'b0;
    end
  endtask

  initial begin
    rivet_dllp_req_t r;
    rst_n     = 1'b0;
    req       = '0;
    req_valid = 1'b0;
    dec_ready = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    r = '0;
    r.kind    = RIVET_DLLP_KIND_FC;
    r.fc_kind = RIVET_DLLP_FC_INIT1_P;
    r.vc      = 3'd0;
    r.hdr_fc  = 8'h7F;
    r.data_fc = 12'h7FF;
    send_and_check(r);

    r = '0;
    r.kind    = RIVET_DLLP_KIND_FC;
    r.fc_kind = RIVET_DLLP_FC_UPDATE_NP;
    r.vc      = 3'd0;
    r.hdr_fc  = 8'h10;
    r.data_fc = 12'h020;
    send_and_check(r);

    r = '0;
    r.kind    = RIVET_DLLP_KIND_ACK;
    r.ack_seq = 12'h0AB;
    send_and_check(r);

    // Infinite CPL InitFC1-Cpl (hdr/data 0)
    r = '0;
    r.kind    = RIVET_DLLP_KIND_FC;
    r.fc_kind = RIVET_DLLP_FC_INIT1_CPL;
    r.hdr_fc  = 8'h00;
    r.data_fc = 12'h000;
    send_and_check(r);

    $display("PASS: rivet_dllp_roundtrip_tb");
    $finish;
  end

  initial begin
    #50000;
    $error("timeout");
    $fatal(1);
  end
endmodule : rivet_dllp_roundtrip_tb
