// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Soft PIPE PCS. No FPGA primitives in this file.
// Gen1/Gen2 8b/10b, the elastic buffer, the command plane, and the
// Gen3/Gen4 gearbox are filled in by the following tasks. This slice
// completes reset: phystatus_rst stays high until the PMA reports done.

module rivet_phy_pcs
  import rivet_pkg::*;
  import rivet_phy_pkg::*;
#(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic                             pclk,
  input  logic                             preset_n,

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata,
  input  logic [2*LANES-1:0]               pipe_txdatak,
  input  logic [LANES-1:0]                 pipe_txdata_valid,
  input  logic [LANES-1:0]                 pipe_txstart_block,
  input  logic [2*LANES-1:0]               pipe_txsync_header,
  output logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata,
  output logic [2*LANES-1:0]               pipe_rxdatak,
  output logic [LANES-1:0]                 pipe_rxdata_valid,
  output logic [2*LANES-1:0]               pipe_rxstart_block,
  output logic [2*LANES-1:0]               pipe_rxsync_header,
  input  logic                             pipe_txdetectrx,
  input  logic [LANES-1:0]                 pipe_txelecidle,
  input  logic [LANES-1:0]                 pipe_txcompliance,
  input  logic [LANES-1:0]                 pipe_rxpolarity,
  input  logic [1:0]                       pipe_powerdown,
  input  logic [2:0]                       pipe_rate,
  output logic [LANES-1:0]                 pipe_rxvalid,
  output logic [LANES-1:0]                 pipe_phystatus,
  output logic [LANES-1:0]                 pipe_phystatus_rst,
  output logic [LANES-1:0]                 pipe_rxelecidle,
  output logic [3*LANES-1:0]               pipe_rxstatus,
  input  logic [2:0]                       pipe_txmargin,
  input  logic                             pipe_txswing,
  input  logic                             pipe_txdeemph,
  input  logic [2*LANES-1:0]               pipe_txeq_ctrl,
  input  logic [4*LANES-1:0]               pipe_txeq_preset,
  input  logic [6*LANES-1:0]               pipe_txeq_coeff,
  output logic [5:0]                       pipe_txeq_fs,
  output logic [5:0]                       pipe_txeq_lf,
  output logic [18*LANES-1:0]              pipe_txeq_new_coeff,
  output logic [LANES-1:0]                 pipe_txeq_done,
  input  logic [2*LANES-1:0]               pipe_rxeq_ctrl,
  input  logic [4*LANES-1:0]               pipe_rxeq_txpreset,
  output logic [LANES-1:0]                 pipe_rxeq_preset_sel,
  output logic [18*LANES-1:0]              pipe_rxeq_new_txcoeff,
  output logic [LANES-1:0]                 pipe_rxeq_adapt_done,
  output logic [LANES-1:0]                 pipe_rxeq_done,
  input  logic                             pipe_as_mac_in_detect,
  input  logic                             pipe_as_cdr_hold_req,

  output logic [63:0]                      pma_txdata,
  output logic [5:0]                       pma_txwidth,
  output logic                             pma_txelecidle,
  output logic                             pma_txdetectrx,
  output logic                             pma_txpolarity,
  output logic [4:0]                       pma_txdiffctrl,
  output logic [4:0]                       pma_txprecursor,
  output logic [6:0]                       pma_txmaincursor,
  output logic [4:0]                       pma_txpostcursor,
  output logic                             pma_rxslide,
  output logic [2:0]                       pma_rate,
  input  logic [63:0]                      pma_rxdata,
  input  logic                             pma_rxelecidle,
  input  logic                             pma_rxdetected,
  input  logic                             pma_resetdone,
  input  logic                             pma_pll_lock
);

  `include "rivet_phy_8b10b_enc.svh"

`ifndef SYNTHESIS
  initial begin
    if (!(LANES == 1 || LANES == 2 || LANES == 4))
      $error("rivet_phy_pcs LANES must be 1, 2, or 4");
    if (!(PIPE_DATA_WIDTH == 16 || PIPE_DATA_WIDTH == 32 || PIPE_DATA_WIDTH == 64))
      $error("rivet_phy_pcs PIPE_DATA_WIDTH must be 16, 32, or 64");
  end
`endif

  assign pipe_phystatus_rst = {LANES{~preset_n | ~pma_resetdone}};
  assign pipe_phystatus     = pipe_phystatus_rst;
  assign pipe_rxdata_valid  = '0;
  assign pipe_rxstart_block = '0;
  assign pipe_rxsync_header = '0;
  assign pipe_rxelecidle    = {LANES{pma_rxelecidle}};
  assign pipe_txeq_fs       = RIVET_PHY_TXEQ_FS;
  assign pipe_txeq_lf       = RIVET_PHY_TXEQ_LF;
  assign pipe_txeq_new_coeff  = '0;
  assign pipe_txeq_done       = '0;
  assign pipe_rxeq_preset_sel = '0;
  assign pipe_rxeq_new_txcoeff = '0;
  assign pipe_rxeq_adapt_done = '0;
  assign pipe_rxeq_done       = '0;

  logic       rd_tx_q;
  logic       rd_rx_q;
  logic       locked_q;
  logic       rd0, rd1, rd_a, rd_b;
  logic       inv0, inv1, k0, k1, ce0, ce1, de0, de1;
  logic [9:0] c0, c1;
  logic [7:0] b0, b1;
  logic       comma0;
  logic [2:0] st0, st1;

  wire gen12 = (pipe_rate == RIVET_PIPE_RATE_GEN1) || (pipe_rate == RIVET_PIPE_RATE_GEN2);

  always_comb begin
    c0 = rivet_phy_enc10(pipe_txdata[7:0], pipe_txdatak[0],
                         pipe_txcompliance[0] ? 1'b1 : rd_tx_q, rd0, inv0);
    c1 = rivet_phy_enc10(pipe_txdata[15:8], pipe_txdatak[1], rd0, rd1, inv1);
  end
  assign pma_txdata  = gen12 ? {{44{1'b0}}, c1, c0} : '0;
  assign pma_txwidth = rivet_phy_pma_width(pipe_rate);

  assign comma0 = (pma_rxdata[9:0] == 10'b0011111010) ||
                   (pma_rxdata[9:0] == 10'b1100000101);

  always_comb begin
    rivet_phy_dec10(pma_rxdata[9:0], rd_rx_q, b0, k0, rd_a, ce0, de0);
    rivet_phy_dec10(pma_rxdata[19:10], ce0 ? rd_rx_q : rd_a, b1, k1, rd_b, ce1, de1);
    st0 = ce0 ? RIVET_RXSTATUS_DECODE_ERR : de0 ? RIVET_RXSTATUS_DISPARITY : RIVET_RXSTATUS_OK;
    st1 = ce1 ? RIVET_RXSTATUS_DECODE_ERR : de1 ? RIVET_RXSTATUS_DISPARITY : RIVET_RXSTATUS_OK;
  end

  assign pipe_rxdata[PIPE_DATA_WIDTH-1:0] = {{(PIPE_DATA_WIDTH-16){1'b0}}, b1, b0};
  assign pipe_rxdatak[1:0] = {k1, k0};
  assign pipe_rxvalid[0] = gen12 & (locked_q | comma0) & pma_resetdone & preset_n;
  assign pipe_rxstatus[2:0] = (st0 != RIVET_RXSTATUS_OK) ? st0 : st1;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      rd_tx_q  <= 1'b1;
      rd_rx_q  <= 1'b1;
      locked_q <= 1'b0;
    end else if (gen12 && !pipe_txelecidle[0]) begin
      rd_tx_q <= rd1;
      if (comma0 || locked_q) begin
        locked_q <= 1'b1;
        if (!ce0 && !de0)
          rd_rx_q <= (ce1 || de1) ? rd_a : rd_b;
      end
    end
  end

  if (LANES > 1) begin : g_tie_hi
    assign pipe_rxdata[PIPE_DATA_WIDTH*LANES-1:PIPE_DATA_WIDTH] = '0;
    assign pipe_rxdatak[2*LANES-1:2] = '0;
    assign pipe_rxvalid[LANES-1:1] = '0;
    assign pipe_rxstatus[3*LANES-1:3] = '0;
  end
  assign pma_txelecidle   = pipe_txelecidle[0];
  assign pma_txdetectrx   = pipe_txdetectrx;
  assign pma_txpolarity   = 1'b0;
  assign pma_txdiffctrl   = {2'b00, pipe_txmargin};
  assign pma_txprecursor  = '0;
  assign pma_txmaincursor = 7'd24;
  assign pma_txpostcursor = '0;
  assign pma_rxslide      = 1'b0;
  assign pma_rate         = pipe_rate;

  wire _unused = pma_pll_lock ^ pma_rxdetected ^ pipe_txswing ^ pipe_txdeemph ^
                 pipe_as_mac_in_detect ^ pipe_as_cdr_hold_req ^
                 (|pipe_txdata) ^ (|pipe_txdatak) ^ (|pipe_txdata_valid) ^
                 (|pipe_txstart_block) ^ (|pipe_txsync_header) ^
                 (|pipe_txcompliance) ^ (|pipe_rxpolarity) ^ (|pipe_powerdown) ^
                 (|pipe_txeq_ctrl) ^ (|pipe_txeq_preset) ^ (|pipe_txeq_coeff) ^
                 (|pipe_rxeq_ctrl) ^ (|pipe_rxeq_txpreset) ^ (|pma_rxdata);

endmodule : rivet_phy_pcs
