// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Data Link Layer top: FC + DL SM (D4a). TLP path / replay wire-up is D4b.

module rivet_dll #(
  parameter int unsigned LANES            = 1,
  parameter int unsigned PIPE_DATA_WIDTH  = 16,
  parameter int unsigned INITFC_GAP_CYC   = 8,
  parameter int unsigned UPDATEFC_GAP_CYC = 32,
  parameter int unsigned REPLAY_TLP_SLOTS = 16,
  parameter int unsigned REPLAY_SLOT_BYTES = 160
) (
  input  logic pclk_i,
  input  logic rst_ni,

  output rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_o,
  output logic                              dll_tx_valid_o,
  input  logic                              dll_tx_ready_i,
  input  rivet_pkg::rivet_dll_mac_rx_beat_t dll_rx_beat_i,
  input  logic                              dll_rx_valid_i,
  output logic                              dll_rx_ready_o,
  input  rivet_pkg::rivet_mac_dll_sb_t      mac_to_dll_sb_i,
  output rivet_pkg::rivet_dll_mac_sb_t      dll_to_mac_sb_o,

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

  rivet_dllp_req_t req;
  logic            req_valid;
  logic            req_ready;

  rivet_dllp_dec_t dec;
  logic            dec_valid;
  logic            dec_ready;

  rivet_dll_tl_fc_sb_t fc_sb;
  rivet_dl_state_e     dl_state;
  logic                tlp_tx_en;
  logic                replay_en;
  logic                fc_en;
  logic                replay_req;
  logic                replay_done;

  // D4a: no NAK/timer source yet — held idle (D4b).
  assign replay_req  = 1'b0;
  assign replay_done = 1'b0;

  rivet_dll_sm u_sm (
    .pclk_i          (pclk_i),
    .rst_ni          (rst_ni),
    .mac_sb_i        (mac_to_dll_sb_i),
    .fc_init_done_i  (fc_sb.fc_init_done),
    .replay_req_i    (replay_req),
    .replay_done_i   (replay_done),
    .state_o         (dl_state),
    .tlp_tx_en_o     (tlp_tx_en),
    .replay_en_o     (replay_en),
    .fc_en_o         (fc_en)
  );

  rivet_dll_fc #(
    .INITFC_GAP_CYC   (INITFC_GAP_CYC),
    .UPDATEFC_GAP_CYC (UPDATEFC_GAP_CYC)
  ) u_fc (
    .pclk_i       (pclk_i),
    .rst_ni       (rst_ni),
    .mac_sb_i     (mac_to_dll_sb_i),
    .tl_fc_i      (tl_to_dll_fc_i),
    .req_o        (req),
    .req_valid_o  (req_valid),
    .req_ready_i  (req_ready),
    .dec_i        (dec),
    .dec_valid_i  (dec_valid),
    .dec_ready_o  (dec_ready),
    .dll_tl_fc_o  (fc_sb)
  );

  assign dll_to_tl_fc_o = fc_sb;

  rivet_dllp_tx u_dllp_tx (
    .clk_i        (pclk_i),
    .rst_ni       (rst_ni),
    .req_i        (req),
    .req_valid_i  (req_valid && fc_en),
    .req_ready_o  (req_ready),
    .beat_o       (dll_tx_beat_o),
    .beat_valid_o (dll_tx_valid_o),
    .beat_ready_i (dll_tx_ready_i)
  );

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

  assign dll_to_mac_sb_o = '0;

  logic _unused;
  assign _unused = |PIPE_DATA_WIDTH | tlp_tx_en | replay_en | (|dl_state) |
                   (|REPLAY_TLP_SLOTS) | (|REPLAY_SLOT_BYTES);

endmodule : rivet_dll
