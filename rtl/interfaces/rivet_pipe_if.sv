// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PIPE (MAC <-> PHY) interface aligned to AMD PG239 PCIe PHY ports.
//
// PIPE revision note (PG239 does not name a PIPE version):
//   Signal set matches Intel "original" PIPE architecture with Gen3+ block
//   controls (Tx/Rx DataValid, StartBlock, SyncHeader) and Rate[2:0] through
//   Gen5 encodings on some devices. Prefer obtaining:
//     - PIPE 4.4.1  (covers Gen1–Gen4 / PCIe 4.0 era), and/or
//     - PIPE 5.x    (Gen5 + SerDes architecture notes; PG239 is still closer
//                    to classic/original PIPE than SerDes-only PIPE).
//   AMD Gen3+ equalization and assist ports below are PG239-specific and are
//   NOT the standard PIPE Local FS/LF / GetLocalPresetCoefficients EQ model.
//
// PG213 is the *user* AXI-ST boundary — not this interface.
//
// Width packing for per-lane buses (PG239): {LaneN-1, ..., Lane1, Lane0}.
// Default PIPE_DATA_WIDTH=16 for Gen2; UltraScale+ PHY pins are up to 64 bits
// per lane (upper bits unused below Gen4/Gen5).

interface rivet_pipe_if #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16  // 16 (Gen1/2), 32 (Gen3), 64 (Gen4/5 US+)
) (
  input logic pclk,
  input logic preset_n
);

  localparam int unsigned DATA_W       = PIPE_DATA_WIDTH * LANES;
  localparam int unsigned DATAK_W      = 2 * LANES;           // [1:0] per lane (Gen1/2)
  localparam int unsigned RXSTATUS_W   = 3 * LANES;           // [2:0] per lane
  localparam int unsigned SYNC_HDR_W   = 2 * LANES;           // [1:0] per lane
  localparam int unsigned RX_SB_W      = 2 * LANES;           // US+: [1:0] per lane
  localparam int unsigned TXEQ_CTRL_W  = 2 * LANES;
  localparam int unsigned TXEQ_PRE_W   = 4 * LANES;
  localparam int unsigned TXEQ_COEF_W  = 6 * LANES;
  localparam int unsigned TXEQ_NEW_W   = 18 * LANES;
  localparam int unsigned RXEQ_CTRL_W  = 2 * LANES;
  localparam int unsigned RXEQ_PRE_W   = 4 * LANES;
  localparam int unsigned RXEQ_NEW_W   = 18 * LANES;

  // ------------------------------------------------------------------------
  // TX data (MAC -> PHY) — PG239 Tables 5/6
  // ------------------------------------------------------------------------
  logic [DATA_W-1:0]     txdata;
  logic [DATAK_W-1:0]    txdatak;          // Gen1/Gen2 only; 2 bits/lane
  logic [LANES-1:0]      txdata_valid;     // Gen3+; per-lane
  logic [LANES-1:0]      txstart_block;    // Gen3+; per-lane
  logic [SYNC_HDR_W-1:0] txsync_header;    // Gen3+; per-lane

  // ------------------------------------------------------------------------
  // RX data (PHY -> MAC) — PG239 Tables 7/8
  // ------------------------------------------------------------------------
  logic [DATA_W-1:0]     rxdata;
  logic [DATAK_W-1:0]    rxdatak;          // Gen1/Gen2 only
  logic [LANES-1:0]      rxdata_valid;     // Gen3+
  logic [RX_SB_W-1:0]    rxstart_block;    // US+: 2 bits/lane; US Gen3: 1 bit/lane
  logic [SYNC_HDR_W-1:0] rxsync_header;    // Gen3+

  // ------------------------------------------------------------------------
  // Command (MAC -> PHY) — PG239 Table 9
  // ------------------------------------------------------------------------
  logic                  txdetectrx;       // per-design
  logic [LANES-1:0]      txelecidle;       // per-lane
  logic [LANES-1:0]      txcompliance;     // per-lane
  logic [LANES-1:0]      rxpolarity;       // per-lane
  logic [1:0]            powerdown;        // per-design: P0/P0s/P1/P2 (P2 N/A)
  logic [2:0]            rate;             // per-design: Gen1..Gen5 encodings

  // ------------------------------------------------------------------------
  // Status (PHY -> MAC) — PG239 Table 10
  // ------------------------------------------------------------------------
  logic [LANES-1:0]      rxvalid;          // Gen1/Gen2 symbol lock; per-lane
  logic [LANES-1:0]      phystatus;        // per-lane
  logic [LANES-1:0]      phystatus_rst;    // PG239 reset-done (AMD)
  logic [LANES-1:0]      rxelecidle;       // Gen1/Gen2; async; per-lane
  logic [RXSTATUS_W-1:0] rxstatus;         // [2:0] per-lane

  // ------------------------------------------------------------------------
  // TX driver Gen1/Gen2 — PG239 Table 11
  // ------------------------------------------------------------------------
  logic [2:0]            txmargin;
  logic                  txswing;
  logic                  txdeemph;

  // ------------------------------------------------------------------------
  // TX equalization Gen3+ (AMD custom, not standard PIPE EQ) — Table 12
  // ------------------------------------------------------------------------
  logic [TXEQ_CTRL_W-1:0]  txeq_ctrl;
  logic [TXEQ_PRE_W-1:0]   txeq_preset;
  logic [TXEQ_COEF_W-1:0]  txeq_coeff;
  logic [5:0]              txeq_fs;          // static; per-design in PG239
  logic [5:0]              txeq_lf;
  logic [TXEQ_NEW_W-1:0]   txeq_new_coeff;
  logic [LANES-1:0]        txeq_done;

  // ------------------------------------------------------------------------
  // RX equalization Gen3+ (AMD custom) — Table 13
  // ------------------------------------------------------------------------
  logic [RXEQ_CTRL_W-1:0]  rxeq_ctrl;
  logic [RXEQ_PRE_W-1:0]   rxeq_txpreset;
  logic [LANES-1:0]        rxeq_preset_sel;
  logic [RXEQ_NEW_W-1:0]   rxeq_new_txcoeff;
  logic [LANES-1:0]        rxeq_adapt_done;
  logic [LANES-1:0]        rxeq_done;

  // ------------------------------------------------------------------------
  // Assist (AMD, MAC LTSSM helpers) — Tables 14/15
  // ------------------------------------------------------------------------
  logic                  as_mac_in_detect;
  logic                  as_cdr_hold_req;
  logic                  as_mac_in_L0;       // ASPM L0s path (US+)
  logic [1:0]            cfg_rx_pm_state;    // ASPM RX L0s substate

  // ------------------------------------------------------------------------
  // Modports
  // ------------------------------------------------------------------------
  modport mac (
    input  pclk, preset_n,
    output txdata, txdatak, txdata_valid, txstart_block, txsync_header,
           txdetectrx, txelecidle, txcompliance, rxpolarity, powerdown, rate,
           txmargin, txswing, txdeemph,
           txeq_ctrl, txeq_preset, txeq_coeff,
           rxeq_ctrl, rxeq_txpreset,
           as_mac_in_detect, as_cdr_hold_req, as_mac_in_L0, cfg_rx_pm_state,
    input  rxdata, rxdatak, rxdata_valid, rxstart_block, rxsync_header,
           rxvalid, phystatus, phystatus_rst, rxelecidle, rxstatus,
           txeq_fs, txeq_lf, txeq_new_coeff, txeq_done,
           rxeq_preset_sel, rxeq_new_txcoeff, rxeq_adapt_done, rxeq_done
  );

  modport phy (
    input  pclk, preset_n,
    input  txdata, txdatak, txdata_valid, txstart_block, txsync_header,
           txdetectrx, txelecidle, txcompliance, rxpolarity, powerdown, rate,
           txmargin, txswing, txdeemph,
           txeq_ctrl, txeq_preset, txeq_coeff,
           rxeq_ctrl, rxeq_txpreset,
           as_mac_in_detect, as_cdr_hold_req, as_mac_in_L0, cfg_rx_pm_state,
    output rxdata, rxdatak, rxdata_valid, rxstart_block, rxsync_header,
           rxvalid, phystatus, phystatus_rst, rxelecidle, rxstatus,
           txeq_fs, txeq_lf, txeq_new_coeff, txeq_done,
           rxeq_preset_sel, rxeq_new_txcoeff, rxeq_adapt_done, rxeq_done
  );

  modport monitor (
    input pclk, preset_n,
          txdata, txdatak, txdata_valid, txstart_block, txsync_header,
          rxdata, rxdatak, rxdata_valid, rxstart_block, rxsync_header,
          txdetectrx, txelecidle, txcompliance, rxpolarity, powerdown, rate,
          rxvalid, phystatus, phystatus_rst, rxelecidle, rxstatus,
          txmargin, txswing, txdeemph,
          txeq_ctrl, txeq_preset, txeq_coeff, txeq_fs, txeq_lf,
          txeq_new_coeff, txeq_done,
          rxeq_ctrl, rxeq_txpreset, rxeq_preset_sel, rxeq_new_txcoeff,
          rxeq_adapt_done, rxeq_done,
          as_mac_in_detect, as_cdr_hold_req, as_mac_in_L0, cfg_rx_pm_state
  );

endinterface : rivet_pipe_if
