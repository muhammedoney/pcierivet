// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC ordered-set / TS RX skeleton (Gen2). M0: no detections; classify later.

module rivet_mac_os_rx #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_i,
  input  logic [2*LANES-1:0]               sym_datak_i,
  input  logic [LANES-1:0]                 sym_valid_i,
  input  logic [3*LANES-1:0]               rxstatus_i,

  output logic                             ts1_detected_o,
  output logic                             ts2_detected_o,
  output logic                             rx_error_o,

  // Toward DLL (idle in M0)
  output rivet_pkg::rivet_dll_mac_rx_beat_t dll_rx_beat_o,
  output logic                              dll_rx_valid_o,
  input  logic                              dll_rx_ready_i
);

  import rivet_pkg::*;

  assign ts1_detected_o = 1'b0;
  assign ts2_detected_o = 1'b0;
  assign rx_error_o     = 1'b0;
  assign dll_rx_beat_o  = '0;
  assign dll_rx_valid_o = 1'b0;

  logic _unused_ok;
  assign _unused_ok = rst_ni ^ dll_rx_ready_i ^ pclk_i ^
                      (|sym_data_i) ^ (|sym_datak_i) ^ (|sym_valid_i) ^ (|rxstatus_i);

endmodule : rivet_mac_os_rx
