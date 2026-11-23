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
    if (!(PIPE_DATA_WIDTH == 16 || PIPE_DATA_WIDTH == 32))
      $error("rivet_mac_lane_map: PIPE_DATA_WIDTH must be 16 or 32 (got %0d)", PIPE_DATA_WIDTH);
  end
`endif

  // Phys index that carries logical lane of rank k when reversed: rank W-1-k.
  // Every loop is bounded by LANES. A trip count of w does not unroll in Vivado,
  // and a variable part-select base is out of range for the same reason.
  logic [LANES-1:0][4:0] map_phys; // map_phys[log] = phys
  logic [LANES-1:0][4:0] map_log;  // map_log[phys] = log

  always_comb begin
    int unsigned w;
    logic [4:0]  rank_phys [LANES];
    w = 0;
    for (int unsigned i = 0; i < LANES; i++) begin
      map_phys[i]  = 5'(i);
      map_log[i]   = 5'(i);
      rank_phys[i] = 5'(i);
    end
    for (int unsigned i = 0; i < LANES; i++) begin
      if (lane_en_i[i] && (w < LANES)) begin
        for (int unsigned s = 0; s < LANES; s++) begin
          if (s == w)
            rank_phys[s] = 5'(i);
        end
        w = w + 1;
      end
    end
    for (int unsigned k = 0; k < LANES; k++) begin
      for (int unsigned r = 0; r < LANES; r++) begin
        if (reverse_i && (w > 1) && (k < w) && ((k + r + 1) == w)) begin
          for (int unsigned log = 0; log < LANES; log++) begin
            if (rank_phys[k] == 5'(log))
              map_phys[log] = rank_phys[r];
          end
          for (int unsigned phys = 0; phys < LANES; phys++) begin
            if (rank_phys[r] == 5'(phys))
              map_log[phys] = rank_phys[k];
          end
        end
      end
    end
  end

  always_comb begin
    tx_data_o  = '0;
    tx_datak_o = '0;
    for (int unsigned log = 0; log < LANES; log++) begin
      for (int unsigned phys = 0; phys < LANES; phys++) begin
        if (map_phys[log] == 5'(phys)) begin
          tx_data_o[PIPE_DATA_WIDTH*phys +: PIPE_DATA_WIDTH] =
              tx_data_i[PIPE_DATA_WIDTH*log +: PIPE_DATA_WIDTH];
          tx_datak_o[SYMS*phys +: SYMS] = tx_datak_i[SYMS*log +: SYMS];
        end
      end
    end
  end
  assign tx_valid_o = tx_valid_i;

  always_comb begin
    rx_data_o  = '0;
    rx_datak_o = '0;
    rx_valid_o = '0;
    for (int unsigned phys = 0; phys < LANES; phys++) begin
      for (int unsigned log = 0; log < LANES; log++) begin
        if (map_log[phys] == 5'(log)) begin
          rx_data_o[PIPE_DATA_WIDTH*log +: PIPE_DATA_WIDTH] =
              rx_data_i[PIPE_DATA_WIDTH*phys +: PIPE_DATA_WIDTH];
          rx_datak_o[SYMS*log +: SYMS] = rx_datak_i[SYMS*phys +: SYMS];
          rx_valid_o[log] = rx_valid_i[phys];
        end
      end
    end
  end

endmodule : rivet_mac_lane_map
