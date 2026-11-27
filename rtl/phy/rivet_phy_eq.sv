// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PIPE equalization for one lane. Preset and query pulse txeq_done for
// one cycle. A coefficient request captures pre, main, then post on
// three clocks and pulses done on the third. Gen1/Gen2 deemphasis
// overrides the cursors. A rate change back to Gen3 or Gen4 reloads
// preset 4.

module rivet_phy_eq
  import rivet_pkg::*;
  import rivet_phy_pkg::*;
(
  input  logic        pclk,
  input  logic        preset_n,
  input  logic [2:0]  rate,
  input  logic [1:0]  txeq_ctrl,
  input  logic [3:0]  txeq_preset,
  input  logic [5:0]  txeq_coeff,
  input  logic [1:0]  rxeq_ctrl,
  input  logic        txdeemph,
  input  logic [2:0]  txmargin,

  output logic [5:0]  txeq_fs,
  output logic [5:0]  txeq_lf,
  output logic [17:0] txeq_new_coeff,
  output logic        txeq_done,
  output logic        rxeq_preset_sel,
  output logic [17:0] rxeq_new_txcoeff,
  output logic        rxeq_adapt_done,
  output logic        rxeq_done,

  output logic [4:0]  pma_txprecursor,
  output logic [6:0]  pma_txmaincursor,
  output logic [4:0]  pma_txpostcursor,
  output logic [4:0]  pma_txdiffctrl
);

  logic [5:0] pre_q, main_q, post_q;
  logic [1:0] tx_ctrl_q;
  logic [1:0] rx_ctrl_q;
  logic [1:0] phase_q;
  logic [2:0] rate_q;
  logic        gen12;
  logic        gen34;

  assign txeq_fs = RIVET_PHY_TXEQ_FS;
  assign txeq_lf = RIVET_PHY_TXEQ_LF;
  assign txeq_new_coeff = {pre_q, main_q, post_q};
  assign pma_txprecursor  = pre_q[4:0];
  assign pma_txmaincursor = {1'b0, main_q};
  assign pma_txpostcursor = post_q[4:0];
  assign pma_txdiffctrl   = {2'b00, txmargin};

  assign gen12 = (rate == RIVET_PIPE_RATE_GEN1) || (rate == RIVET_PIPE_RATE_GEN2);
  assign gen34 = (rate == RIVET_PIPE_RATE_GEN3) || (rate == RIVET_PIPE_RATE_GEN4);

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      {pre_q, main_q, post_q} <= rivet_phy_preset(4'h4);
      tx_ctrl_q      <= RIVET_PHY_TXEQ_IDLE;
      rx_ctrl_q      <= RIVET_PHY_RXEQ_IDLE;
      phase_q        <= '0;
      rate_q         <= RIVET_PIPE_RATE_GEN2;
      txeq_done      <= 1'b0;
      rxeq_done      <= 1'b0;
      rxeq_adapt_done <= 1'b0;
      rxeq_preset_sel <= 1'b0;
      rxeq_new_txcoeff <= rivet_phy_preset(4'h4);
    end else begin
      tx_ctrl_q <= txeq_ctrl;
      rx_ctrl_q <= rxeq_ctrl;
      rate_q    <= rate;
      txeq_done <= 1'b0;
      rxeq_done <= 1'b0;
      rxeq_adapt_done <= 1'b0;

      if (gen34 && (rate != rate_q))
        {pre_q, main_q, post_q} <= rivet_phy_preset(4'h4);

      if (gen12) begin
        if (txdeemph)
          {pre_q, main_q, post_q} <= rivet_phy_preset(4'h1);
        else
          {pre_q, main_q, post_q} <= rivet_phy_preset(4'h0);
        phase_q <= '0;
      end else if (txeq_ctrl == RIVET_PHY_TXEQ_PRE && tx_ctrl_q != RIVET_PHY_TXEQ_PRE) begin
        {pre_q, main_q, post_q} <= rivet_phy_preset(txeq_preset);
        txeq_done <= 1'b1;
        phase_q <= '0;
      end else if (txeq_ctrl == RIVET_PHY_TXEQ_QUERY && tx_ctrl_q != RIVET_PHY_TXEQ_QUERY) begin
        txeq_done <= 1'b1;
        phase_q <= '0;
      end else if (txeq_ctrl == RIVET_PHY_TXEQ_COEF) begin
        if (phase_q == 2'd0) begin
          pre_q   <= txeq_coeff;
          phase_q <= 2'd1;
        end else if (phase_q == 2'd1) begin
          main_q  <= txeq_coeff;
          phase_q <= 2'd2;
        end else if (phase_q == 2'd2) begin
          post_q  <= txeq_coeff;
          phase_q <= 2'd3;
          txeq_done <= 1'b1;
        end
      end else begin
        phase_q <= '0;
      end

      if (rxeq_ctrl == RIVET_PHY_RXEQ_EQ && rx_ctrl_q != RIVET_PHY_RXEQ_EQ) begin
        rxeq_done <= 1'b1;
        rxeq_adapt_done <= 1'b1;
        rxeq_preset_sel <= 1'b0;
        rxeq_new_txcoeff <= {pre_q, main_q, post_q};
      end
    end
  end

endmodule : rivet_phy_eq
