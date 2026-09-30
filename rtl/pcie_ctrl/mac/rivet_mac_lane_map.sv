// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Full-port lane reversal remap: logical MAC indices ↔ physical PIPE lanes.
// Only 0..W-1 ↔ W-1..0 on the enabled set (no arbitrary permute).

module rivet_mac_lane_map #(
  parameter int unsigned LANES           = 4,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic                             reverse_i,
  input  logic [LANES-1:0]                 lane_en_i,

  // TX: MAC (logical) → PIPE (physical)
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] tx_data_i,
  input  logic [2*LANES-1:0]               tx_datak_i,
  input  logic                             tx_valid_i,
  output logic [PIPE_DATA_WIDTH*LANES-1:0] tx_data_o,
  output logic [2*LANES-1:0]               tx_datak_o,
  output logic                             tx_valid_o,

  // RX: PIPE (physical) → MAC (logical)
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] rx_data_i,
  input  logic [2*LANES-1:0]               rx_datak_i,
  input  logic [LANES-1:0]                 rx_valid_i,
  output logic [PIPE_DATA_WIDTH*LANES-1:0] rx_data_o,
  output logic [2*LANES-1:0]               rx_datak_o,
  output logic [LANES-1:0]                 rx_valid_o
);

  localparam int unsigned SYMS = PIPE_DATA_WIDTH / 8;

`ifndef SYNTHESIS
  initial begin
    if (!(LANES == 1 || LANES == 2 || LANES == 4))
      $error("rivet_mac_lane_map LANES must be 1, 2, or 4");
    if (PIPE_DATA_WIDTH != 16)
      $error("rivet_mac_lane_map: only PIPE_DATA_WIDTH=16 (got %0d)", PIPE_DATA_WIDTH);
  end
`endif

  // Phys index that carries logical lane e[k] when reversed: e[W-1-k].
  logic [LANES-1:0][4:0] map_phys; // map_phys[log] = phys
  logic [LANES-1:0][4:0] map_log;  // map_log[phys] = log

  always_comb begin
    int unsigned w;
    int unsigned e[LANES];
    w = 0;
    for (int unsigned i = 0; i < LANES; i++) begin
      map_phys[i] = 5'(i);
      map_log[i]  = 5'(i);
      e[i] = 0;
    end
    for (int unsigned i = 0; i < LANES; i++) begin
      if (lane_en_i[i]) begin
        e[w] = i;
        w++;
      end
    end
    if (reverse_i && (w > 1)) begin
      for (int unsigned k = 0; k < w; k++) begin
        map_phys[e[k]] = 5'(e[w - 1 - k]);
        map_log[e[w - 1 - k]] = 5'(e[k]);
      end
    end
  end

  always_comb begin
    tx_data_o  = '0;
    tx_datak_o = '0;
    for (int unsigned log = 0; log < LANES; log++) begin
      automatic int unsigned phys = int'(map_phys[log]);
      tx_data_o[PIPE_DATA_WIDTH*phys +: PIPE_DATA_WIDTH] =
          tx_data_i[PIPE_DATA_WIDTH*log +: PIPE_DATA_WIDTH];
      tx_datak_o[SYMS*phys +: SYMS] = tx_datak_i[SYMS*log +: SYMS];
    end
  end
  assign tx_valid_o = tx_valid_i;

  always_comb begin
    rx_data_o  = '0;
    rx_datak_o = '0;
    rx_valid_o = '0;
    for (int unsigned phys = 0; phys < LANES; phys++) begin
      automatic int unsigned log = int'(map_log[phys]);
      rx_data_o[PIPE_DATA_WIDTH*log +: PIPE_DATA_WIDTH] =
          rx_data_i[PIPE_DATA_WIDTH*phys +: PIPE_DATA_WIDTH];
      rx_datak_o[SYMS*log +: SYMS] = rx_datak_i[SYMS*phys +: SYMS];
      rx_valid_o[log] = rx_valid_i[phys];
    end
  end

endmodule : rivet_mac_lane_map
