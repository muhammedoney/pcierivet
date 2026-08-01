// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Map Rivet Gen2 logical PIPE (16 bits/lane) onto PG239 UltraScale+ pin width
// (typically 64 bits/lane). Per PG239: Gen1/Gen2 use phy_txdata/rxdata[15:0];
// [31:16] Gen3; [63:32] Gen4 — upper bits driven 0 / ignored in Gen2.

module rivet_pipe_pg239_pad #(
  parameter int unsigned LANES            = 4,
  parameter int unsigned PIPE_DATA_WIDTH  = 16,
  parameter int unsigned PHY_DATA_WIDTH   = 64
) (
  // Rivet MAC view (PIPE_DATA_WIDTH bits/lane)
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] mac_txdata,
  input  logic [2*LANES-1:0]               mac_txdatak,
  output logic [PIPE_DATA_WIDTH*LANES-1:0] mac_rxdata,
  output logic [2*LANES-1:0]               mac_rxdatak,

  // PG239 PHY view (PHY_DATA_WIDTH bits/lane)
  output logic [PHY_DATA_WIDTH*LANES-1:0]  phy_txdata,
  output logic [2*LANES-1:0]               phy_txdatak,
  input  logic [PHY_DATA_WIDTH*LANES-1:0]  phy_rxdata,
  input  logic [2*LANES-1:0]               phy_rxdatak
);

`ifndef SYNTHESIS
  initial begin
    if (PIPE_DATA_WIDTH != 16)
      $error("rivet_pipe_pg239_pad: PIPE_DATA_WIDTH must be 16 for Gen2 pad");
    if (PHY_DATA_WIDTH < PIPE_DATA_WIDTH)
      $error("rivet_pipe_pg239_pad: PHY_DATA_WIDTH must be >= PIPE_DATA_WIDTH");
  end
`endif

  genvar lane;
  generate
    for (lane = 0; lane < LANES; lane++) begin : g_lane
      assign phy_txdata[PHY_DATA_WIDTH*lane +: PHY_DATA_WIDTH] =
          {{(PHY_DATA_WIDTH - PIPE_DATA_WIDTH){1'b0}},
           mac_txdata[PIPE_DATA_WIDTH*lane +: PIPE_DATA_WIDTH]};
      assign mac_rxdata[PIPE_DATA_WIDTH*lane +: PIPE_DATA_WIDTH] =
          phy_rxdata[PHY_DATA_WIDTH*lane +: PIPE_DATA_WIDTH];
    end
  endgenerate

  // Gen1/2 K chars: still 2 bits/lane on PG239 even when PHY_DATA_WIDTH=64.
  assign phy_txdatak = mac_txdatak;
  assign mac_rxdatak = phy_rxdatak;

endmodule
