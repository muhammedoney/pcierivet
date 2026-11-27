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

  input  logic [64*LANES-1:0]            pma_txdata,
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

  output logic [64*LANES-1:0]            pma_rxdata,
  output logic                            pma_rxelecidle,
  output logic                            pma_rxdetected,
  output logic                            pma_resetdone,
  output logic                            pma_pll_lock,
  output logic [1:0]                      pma_wr_n,

  input  logic                            inject_code_err,
  input  logic                            inject_disp_err,
  input  logic                            eb_delete_skp,
  input  logic                            eb_insert_skp,
  input  logic                            eb_flood,
  input  logic                            cdr_hold,
  input  logic                            mac_in_detect
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
  logic [2:0]  skp_set_q;
  logic [63:0] hold_word_q;

  function automatic logic is_com10(input logic [9:0] code);
    return (code == 10'b0011111010) || (code == 10'b1100000101);
  endfunction

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
      skp_set_q      <= '0;
      hold_word_q    <= '0;
    end else begin
      if (!pma_resetdone) begin
        rst_cnt_q <= rst_cnt_q + 4'd1;
        if (rst_cnt_q == 4'd15)
          pma_resetdone <= 1'b1;
      end

      tx_d1_q <= pma_txdata[63:0];
      tx_d2_q <= tx_d1_q;
      if (!cdr_hold)
        hold_word_q <= tx_d2_q;

      if ((eb_delete_skp || eb_insert_skp) && is_com10(tx_d2_q[9:0])) begin
        if (skp_set_q == 3'd7)
          skp_set_q <= '0;
        else
          skp_set_q <= skp_set_q + 3'd1;
      end

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
    logic [19:0] slipped;
    word = tx_d2_q;
    // Bit 2 of a D0.0 code is not another legal symbol. Bit 0 is.
    if (inject_code_err)
      word[2] = ~word[2];
    if (inject_disp_err)
      word[9:0] = ~word[9:0];
    slipped = word[19:0];
    for (int i = 0; i < 20; i++) begin
      if (i < (slip_q % 5'd20))
        slipped = {slipped[18:0], slipped[19]};
    end
    word[19:0] = slipped;
    if (cdr_hold)
      word = hold_word_q;
    lane0_rx = word;
  end

  logic [63:0] lane0_rx;
  assign pma_rxdata[63:0] = lane0_rx;

  // One-clock stand-in for ppm. 1 = drop a symbol, 3 = insert a symbol.
  // Every 8th COM while the matching stretch input is high.
  wire eighth_skp = is_com10(pma_rxdata[9:0]) && (skp_set_q == 3'd7);
  assign pma_wr_n = eb_flood ? 2'd3 :
                    (eb_insert_skp && eighth_skp) ? 2'd3 :
                    (eb_delete_skp && eighth_skp) ? 2'd1 : 2'd2;

  wire _unused = (|pma_txwidth) ^ pma_txpolarity ^ (|pma_txdiffctrl) ^
                 (|pma_txprecursor) ^ (|pma_txmaincursor) ^ (|pma_txpostcursor) ^
                 mac_in_detect;

  // Lanes above 0 are a plain two-cycle loopback. Lane 0 keeps the
  // slip, inject, and hold behavior the Gen1/Gen2 benches use.
  for (genvar li = 1; li < LANES; li++) begin : g_lane
    logic [63:0] d1_q;
    logic [63:0] d2_q;
    always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
        d1_q <= '0;
        d2_q <= '0;
      end else begin
        d1_q <= pma_txdata[64*li +: 64];
        d2_q <= d1_q;
      end
    end
    assign pma_rxdata[64*li +: 64] = d2_q;
  end

endmodule : rivet_phy_pma_model
