// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC ordered-set / TS TX skeleton (Gen2). M0: idle symbols; OS insert later.

module rivet_mac_os_tx #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  input  rivet_pkg::rivet_mac_os_type_e os_req_i,
  input  logic                          os_req_valid_i,

  // DLL payload (ignored in M0 when not in L0)
  input  rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_i,
  input  logic                              dll_tx_valid_i,
  output logic                              dll_tx_ready_o,

  // Symbol stream toward pipe adapter (per-link packed)
  output logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_o,
  output logic [2*LANES-1:0]               sym_datak_o,
  output logic                             sym_valid_o
);

  import rivet_pkg::*;

  // M0: hold idle; do not accept DLL traffic yet.
  assign dll_tx_ready_o = 1'b0;
  assign sym_data_o     = '0;
  assign sym_datak_o    = '0;
  assign sym_valid_o    = 1'b0;

  logic _unused_ok;
  assign _unused_ok = rst_ni ^ os_req_valid_i ^ dll_tx_valid_i ^
                      (|dll_tx_beat_i.data) ^ (|os_req_i) ^ pclk_i;

endmodule : rivet_mac_os_tx
