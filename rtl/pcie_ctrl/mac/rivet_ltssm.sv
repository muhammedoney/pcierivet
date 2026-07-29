// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Gen2 EP LTSSM skeleton — holds Detect.Quiet until training logic lands.
// Encodings: rivet_pkg::rivet_ltssm_state_e (PG213 cfg_ltssm_state).

module rivet_ltssm #(
  parameter int unsigned MODE  = 0,
  parameter int unsigned GEN   = 2,
  parameter int unsigned LANES = 1
) (
  input  logic                    pclk_i,
  input  logic                    rst_ni,

  // RX / OS indications (from rivet_mac_os_rx) — unused in M0 stub
  input  logic                    ts1_detected_i,
  input  logic                    ts2_detected_i,
  input  logic                    rx_error_i,

  // PIPE command / assist (toward pipe adapter)
  output logic                    txdetectrx_o,
  output logic [LANES-1:0]        txelecidle_o,
  output logic [1:0]              powerdown_o,
  output logic [2:0]              rate_o,
  output logic                    as_mac_in_detect_o,
  output logic                    as_cdr_hold_req_o,
  output logic                    as_mac_in_L0_o,

  // Status toward DLL / user
  output rivet_pkg::rivet_ltssm_state_e ltssm_state_o,
  output logic                          link_up_o,

  // OS TX requests (toward rivet_mac_os_tx)
  output rivet_pkg::rivet_mac_os_type_e os_req_o,
  output logic                          os_req_valid_o
);

  import rivet_pkg::*;

`ifndef SYNTHESIS
  initial begin
    if (MODE != RIVET_MODE_EP)
      $error("rivet_ltssm M0 stub: MODE=EP only");
    if (GEN != RIVET_GEN2)
      $error("rivet_ltssm M0 stub: GEN=2 only");
    if (!rivet_lanes_legal(LANES))
      $error("rivet_ltssm LANES must be 1, 2, or 4");
  end
`endif

  rivet_ltssm_state_e state_q, state_d;

  always_comb begin
    state_d         = state_q;
    txdetectrx_o    = 1'b0;
    txelecidle_o    = '1;
    powerdown_o     = RIVET_PIPE_P1;
    rate_o          = 3'd1; // Gen2
    as_mac_in_detect_o = 1'b1;
    as_cdr_hold_req_o  = 1'b0;
    as_mac_in_L0_o     = 1'b0;
    link_up_o          = 1'b0;
    os_req_o           = RIVET_MAC_OS_NONE;
    os_req_valid_o     = 1'b0;

    unique case (state_q)
      RIVET_LTSSM_DETECT_QUIET: begin
        // M0: remain in Detect.Quiet (P1 + electrical idle).
        state_d = RIVET_LTSSM_DETECT_QUIET;
      end
      default: begin
        state_d = RIVET_LTSSM_DETECT_QUIET;
      end
    endcase

    // Silence unused inputs until M1 wiring.
    if (ts1_detected_i || ts2_detected_i || rx_error_i) begin
      // no-op in M0
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= RIVET_LTSSM_DETECT_QUIET;
    end else begin
      state_q <= state_d;
    end
  end

  assign ltssm_state_o = state_q;

endmodule : rivet_ltssm
