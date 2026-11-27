// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Soft PHY constants. PIPE rate and RxStatus codes stay in rivet_pkg.

package rivet_phy_pkg;
  localparam int unsigned RIVET_PHY_PMA_W = 64;

  localparam logic [5:0] RIVET_PHY_TXEQ_FS = 6'd24;
  localparam logic [5:0] RIVET_PHY_TXEQ_LF = 6'd8;

  localparam logic [1:0] RIVET_PHY_TXEQ_IDLE  = 2'b00;
  localparam logic [1:0] RIVET_PHY_TXEQ_PRE   = 2'b01;
  localparam logic [1:0] RIVET_PHY_TXEQ_COEF  = 2'b10;
  localparam logic [1:0] RIVET_PHY_TXEQ_QUERY = 2'b11;

  localparam logic [1:0] RIVET_PHY_RXEQ_IDLE   = 2'b00;
  localparam logic [1:0] RIVET_PHY_RXEQ_RSVD   = 2'b01;
  localparam logic [1:0] RIVET_PHY_RXEQ_EQ     = 2'b10;
  localparam logic [1:0] RIVET_PHY_RXEQ_BYPASS = 2'b11;

  // {pre[5:0], main[5:0], post[5:0]}. pre+main+post = FS.
  // Presets 0, 1, and 4 are the ones the MAC and the PG239 default use.
  function automatic logic [17:0] rivet_phy_preset(input logic [3:0] preset);
    case (preset)
      4'h0:    rivet_phy_preset = {6'd0,  6'd18, 6'd6};
      4'h1:    rivet_phy_preset = {6'd0,  6'd20, 6'd4};
      4'h2:    rivet_phy_preset = {6'd0,  6'd19, 6'd5};
      4'h3:    rivet_phy_preset = {6'd0,  6'd21, 6'd3};
      4'h4:    rivet_phy_preset = {6'd0,  6'd24, 6'd0};
      4'h5:    rivet_phy_preset = {6'd4,  6'd20, 6'd0};
      4'h6:    rivet_phy_preset = {6'd5,  6'd19, 6'd0};
      4'h7:    rivet_phy_preset = {6'd4,  6'd14, 6'd6};
      4'h8:    rivet_phy_preset = {6'd4,  6'd16, 6'd4};
      4'h9:    rivet_phy_preset = {6'd6,  6'd18, 6'd0};
      4'hA:    rivet_phy_preset = {6'd0,  6'd15, 6'd9};
      default: rivet_phy_preset = {6'd0,  6'd24, 6'd0};
    endcase
  endfunction

  function automatic logic [5:0] rivet_phy_pma_width(input logic [2:0] rate);
    case (rate)
      3'd2:    rivet_phy_pma_width = 6'd32;
      3'd3:    rivet_phy_pma_width = 6'd64;
      default: rivet_phy_pma_width = 6'd20;
    endcase
  endfunction
endpackage : rivet_phy_pkg
