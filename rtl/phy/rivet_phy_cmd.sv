// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PIPE command plane. Accepts a legal PowerDown x TxDetectRx x TxElecIdle
// combination and a rate. An illegal combination holds the previous
// command and does not pulse phystatus. Rate completion waits for PLL
// lock. Receiver detect completes on the PMA detect pulse.

module rivet_phy_cmd
  import rivet_pkg::*;
(
  input  logic       pclk,
  input  logic       preset_n,

  input  logic [1:0] powerdown,
  input  logic       txdetectrx,
  input  logic       txelecidle,
  input  logic [2:0] rate,
  input  logic       as_mac_in_detect,

  input  logic       pma_rxdetected,
  input  logic       pma_pll_lock,

  output logic       phystatus,
  output logic       rx_detected,
  output logic       pma_txelecidle,
  output logic       pma_txdetectrx,
  output logic [2:0] pma_rate,
  output logic       pclk_gen1,
  output logic       rx_term
);

  function automatic logic combo_legal(
    input logic [1:0] pd, input logic det, input logic idle);
    case (pd)
      2'b00:   return !(det && idle);
      2'b01:   return idle;
      2'b10:   return idle;
      default: return 1'b1;
    endcase
  endfunction

  logic [1:0] pd_q;
  logic       det_q;
  logic       idle_q;
  logic [2:0] rate_q;
  logic       lock_q;
  logic       rate_wait;

  assign pma_txelecidle = idle_q;
  assign pma_txdetectrx = det_q;
  assign pma_rate       = rate_q;
  assign pclk_gen1      = (rate_q == RIVET_PIPE_RATE_GEN1);
  assign rx_term        = as_mac_in_detect;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      pd_q        <= 2'b10;
      det_q       <= 1'b0;
      idle_q      <= 1'b1;
      rate_q      <= RIVET_PIPE_RATE_GEN2;
      lock_q      <= 1'b0;
      rate_wait   <= 1'b0;
      phystatus   <= 1'b0;
      rx_detected <= 1'b0;
    end else begin
      phystatus   <= 1'b0;
      rx_detected <= 1'b0;
      lock_q      <= pma_pll_lock;

      if (combo_legal(powerdown, txdetectrx, txelecidle)) begin
        pd_q   <= powerdown;
        det_q  <= txdetectrx;
        idle_q <= txelecidle;
        if (rate != rate_q) begin
          rate_q    <= rate;
          rate_wait <= 1'b1;
        end
      end

      if (rate_wait && pma_pll_lock && !lock_q) begin
        phystatus <= 1'b1;
        rate_wait <= 1'b0;
      end else if (pma_rxdetected && det_q && idle_q) begin
        phystatus   <= 1'b1;
        rx_detected <= 1'b1;
      end
    end
  end

endmodule : rivet_phy_cmd
