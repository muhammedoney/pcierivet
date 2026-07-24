// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PIPE interface skeleton (Gen2-oriented subset). Cite PIPE spec for full semantics.
// Parameterized by LANES (1/2/4). Aggregate data width = PIPE_DATA_WIDTH * LANES.

interface rivet_pipe_if #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input logic pclk,
  input logic preset_n
);

  localparam int unsigned DATA_W = PIPE_DATA_WIDTH * LANES;

  // TX (MAC -> PHY)
  logic [DATA_W-1:0]           txdata;
  logic [LANES-1:0]            txdatak;
  logic                        txdetectrx;
  logic                        txelecidle;
  logic [LANES-1:0]            txcompliance;
  logic                        txdata_valid;
  logic                        txdatavalid; // alias-friendly name used by some PHYs

  // RX (PHY -> MAC)
  logic [DATA_W-1:0]           rxdata;
  logic [LANES-1:0]            rxdatak;
  logic                        rxvalid;
  logic                        rxelecidle;
  logic [2:0]                  rxstatus;
  logic                        phystatus;
  logic                        rxdatavalid;

  // Power / rate control (subset)
  logic [1:0]                  powerdown;
  logic [2:0]                  rate;
  logic                        rxpolarity;
  logic [LANES-1:0]            rxstandby;

  modport mac (
    input  pclk, preset_n,
    output txdata, txdatak, txdetectrx, txelecidle, txcompliance, txdata_valid, txdatavalid,
           powerdown, rate, rxpolarity, rxstandby,
    input  rxdata, rxdatak, rxvalid, rxelecidle, rxstatus, phystatus, rxdatavalid
  );

  modport phy (
    input  pclk, preset_n,
    input  txdata, txdatak, txdetectrx, txelecidle, txcompliance, txdata_valid, txdatavalid,
           powerdown, rate, rxpolarity, rxstandby,
    output rxdata, rxdatak, rxvalid, rxelecidle, rxstatus, phystatus, rxdatavalid
  );

  modport monitor (
    input pclk, preset_n,
          txdata, txdatak, txdetectrx, txelecidle, txcompliance, txdata_valid, txdatavalid,
          rxdata, rxdatak, rxvalid, rxelecidle, rxstatus, phystatus, rxdatavalid,
          powerdown, rate, rxpolarity, rxstandby
  );

endinterface : rivet_pipe_if
