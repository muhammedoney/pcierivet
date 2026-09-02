// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Data Link Layer top (D0): DLLP codec + TL FC stub. InitFC SM arrives in D1.
// Does not yet emit DLLPs toward MAC (tx held idle).

module rivet_dll #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  // Toward MAC
  output rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_o,
  output logic                              dll_tx_valid_o,
  input  logic                              dll_tx_ready_i,
  input  rivet_pkg::rivet_dll_mac_rx_beat_t dll_rx_beat_i,
  input  logic                              dll_rx_valid_i,
  output logic                              dll_rx_ready_o,
  input  rivet_pkg::rivet_mac_dll_sb_t      mac_to_dll_sb_i,
  output rivet_pkg::rivet_dll_mac_sb_t      dll_to_mac_sb_o,

  // Toward TL FC stub / later TL
  input  rivet_pkg::rivet_tl_dll_fc_sb_t    tl_to_dll_fc_i,
  output rivet_pkg::rivet_dll_tl_fc_sb_t    dll_to_tl_fc_o
);

  import rivet_pkg::*;

`ifndef SYNTHESIS
  initial begin
    if (!rivet_lanes_legal(LANES))
      $error("rivet_dll LANES must be 1, 2, or 4");
  end
`endif

  // D0: hold TX quiet; RX decode path live for unit tests / D1.
  rivet_dllp_req_t req;
  logic            req_valid;
  logic            req_ready;
  rivet_dll_mac_tx_beat_t codec_beat;
  logic            codec_beat_valid;
  logic            codec_beat_ready;

  assign req       = '0;
  assign req_valid = 1'b0;

  rivet_dllp_tx u_dllp_tx (
    .clk_i        (pclk_i),
    .rst_ni       (rst_ni),
    .req_i        (req),
    .req_valid_i  (req_valid),
    .req_ready_o  (req_ready),
    .beat_o       (codec_beat),
    .beat_valid_o (codec_beat_valid),
    .beat_ready_i (codec_beat_ready)
  );

  // Not connected to MAC yet in D0 (FC SM is D1).
  assign codec_beat_ready = 1'b1;
  assign dll_tx_beat_o    = '0;
  assign dll_tx_valid_o   = 1'b0;

  rivet_dllp_dec_t dec;
  logic            dec_valid;
  logic            dec_ready;

  rivet_dllp_rx u_dllp_rx (
    .clk_i        (pclk_i),
    .rst_ni       (rst_ni),
    .beat_i       (dll_rx_beat_i),
    .beat_valid_i (dll_rx_valid_i),
    .beat_ready_o (dll_rx_ready_o),
    .dec_o        (dec),
    .dec_valid_o  (dec_valid),
    .dec_ready_i  (dec_ready)
  );

  assign dec_ready = 1'b1; // drop until FC SM consumes

  assign dll_to_mac_sb_o = '0;

  rivet_dll_tl_fc_sb_t dll_tl_q;
  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dll_tl_q <= '0;
    end else begin
      // Seed CL from our own CA until peer InitFC arrives (D1).
      dll_tl_q.cl           <= tl_to_dll_fc_i.ca;
      dll_tl_q.fc_init_done <= 1'b0;
      dll_tl_q.dl_active    <= 1'b0;
    end
  end
  assign dll_to_tl_fc_o = dll_tl_q;

  logic _unused;
  assign _unused = dll_tx_ready_i ^ (|mac_to_dll_sb_i) ^ req_ready ^
                   codec_beat_valid ^ (|codec_beat) ^ dec_valid ^ (|dec) ^
                   (|PIPE_DATA_WIDTH);

endmodule : rivet_dll
