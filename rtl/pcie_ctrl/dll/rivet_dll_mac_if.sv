// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// DLL <-> MAC payload streams + control sideband (internal, pclk domain).
// Not PCIe Configuration Space. Not user AXI-ST.

interface rivet_dll_mac_if (
  input logic clk_i,
  input logic rst_ni
);

  import rivet_pkg::*;

  // DLL TX -> MAC TX
  rivet_dll_mac_tx_beat_t tx_beat;
  logic                   tx_valid;
  logic                   tx_ready;

  // MAC RX -> DLL RX
  rivet_dll_mac_rx_beat_t rx_beat;
  logic                   rx_valid;
  logic                   rx_ready;

  // Sideband
  rivet_mac_dll_sb_t mac_to_dll_sb;
  rivet_dll_mac_sb_t dll_to_mac_sb;

  modport mac (
    input  clk_i, rst_ni,
    input  tx_beat, tx_valid, dll_to_mac_sb,
    output tx_ready, rx_beat, rx_valid, mac_to_dll_sb,
    input  rx_ready
  );

  modport dll (
    input  clk_i, rst_ni,
    output tx_beat, tx_valid, dll_to_mac_sb,
    input  tx_ready, rx_beat, rx_valid, mac_to_dll_sb,
    output rx_ready
  );

  modport monitor (
    input clk_i, rst_ni,
          tx_beat, tx_valid, tx_ready,
          rx_beat, rx_valid, rx_ready,
          mac_to_dll_sb, dll_to_mac_sb
  );

endinterface : rivet_dll_mac_if
