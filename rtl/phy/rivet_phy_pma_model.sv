// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Behavioral PMA for the soft PCS. Serial pins stay idle.
// Loopback, bit-slip, symbol stretch, and receiver detect live here.
// The VCU118 build replaces this module with GTYE4 primitives.

module rivet_phy_pma_model #(
  parameter int unsigned LANES = 1
) (
  input  logic                            pclk,
  input  logic                            preset_n,

  input  logic [63:0]                     pma_txdata,
  input  logic [5:0]                      pma_txwidth,
  input  logic                            pma_txelecidle,
  input  logic                            pma_txdetectrx,
  input  logic                            pma_txpolarity,
  input  logic [4:0]                      pma_txdiffctrl,
  input  logic [4:0]                      pma_txprecursor,
  input  logic [6:0]                      pma_txmaincursor,
  input  logic [4:0]                      pma_txpostcursor,
  input  logic                            pma_rxslide,
  input  logic [2:0]                      pma_rate,

  output logic [63:0]                     pma_rxdata,
  output logic                            pma_rxelecidle,
  output logic                            pma_rxdetected,
  output logic                            pma_resetdone,
  output logic                            pma_pll_lock,

  input  logic                            inject_code_err,
  input  logic                            inject_disp_err,
  input  logic                            eb_delete_skp,
  input  logic                            eb_insert_skp,
  input  logic                            eb_flood,
  input  logic                            cdr_hold
);

  logic [3:0]  rst_cnt_q;
  logic [63:0] tx_d1_q;
  logic [63:0] tx_d2_q;
  logic [4:0]  slip_q;
  logic        detect_arm_q;
  logic [3:0]  detect_cnt_q;
  logic [2:0]  rate_q;
  logic        lock_drop_q;
  logic [3:0]  lock_cnt_q;

  assign pma_rxelecidle = pma_txelecidle;
  assign pma_pll_lock   = pma_resetdone & ~lock_drop_q;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      rst_cnt_q      <= '0;
      pma_resetdone  <= 1'b0;
      tx_d1_q        <= '0;
      tx_d2_q        <= '0;
      slip_q         <= '0;
      detect_arm_q   <= 1'b0;
      detect_cnt_q   <= '0;
      pma_rxdetected <= 1'b0;
      rate_q         <= 3'd1;
      lock_drop_q    <= 1'b0;
      lock_cnt_q     <= '0;
    end else begin
      if (!pma_resetdone) begin
        rst_cnt_q <= rst_cnt_q + 4'd1;
        if (rst_cnt_q == 4'd15)
          pma_resetdone <= 1'b1;
      end

      tx_d1_q <= pma_txdata;
      tx_d2_q <= tx_d1_q;

      if (pma_rxslide)
        slip_q <= slip_q + 5'd1;

      if (pma_rate != rate_q) begin
        rate_q      <= pma_rate;
        lock_drop_q <= 1'b1;
        lock_cnt_q  <= '0;
      end else if (lock_drop_q) begin
        lock_cnt_q <= lock_cnt_q + 4'd1;
        if (lock_cnt_q == 4'd7)
          lock_drop_q <= 1'b0;
      end

      pma_rxdetected <= 1'b0;
      if (pma_txdetectrx && pma_txelecidle && !detect_arm_q) begin
        detect_arm_q <= 1'b1;
        detect_cnt_q <= '0;
      end else if (detect_arm_q) begin
        detect_cnt_q <= detect_cnt_q + 4'd1;
        if (detect_cnt_q == 4'd7) begin
          pma_rxdetected <= 1'b1;
          detect_arm_q   <= 1'b0;
        end
      end else if (!pma_txdetectrx) begin
        detect_arm_q <= 1'b0;
      end
    end
  end

  always_comb begin
    logic [63:0] word;
    word = tx_d2_q;
    if (inject_code_err)
      word[0] = ~word[0];
    if (inject_disp_err)
      word[9:0] = ~word[9:0];
    if (pma_rxslide || (slip_q != 5'd0))
      word[19:0] = {word[18:0], word[19]};
    if (cdr_hold)
      word = tx_d2_q;
    if (eb_flood)
      word = {word[62:0], 1'b1};
    pma_rxdata = word;
  end

  wire _unused = (|pma_txwidth) ^ pma_txpolarity ^ (|pma_txdiffctrl) ^
                 (|pma_txprecursor) ^ (|pma_txmaincursor) ^ (|pma_txpostcursor) ^
                 eb_delete_skp ^ eb_insert_skp ^ (|LANES);

endmodule : rivet_phy_pma_model
