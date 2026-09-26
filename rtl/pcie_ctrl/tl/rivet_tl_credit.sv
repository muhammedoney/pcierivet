// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pulse TL FC free/consume from a classified TLP header (one shot per accept).

module rivet_tl_credit (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        rx_accept_i,
  input  logic [7:0]  rx_hdr0_i,
  input  logic [9:0]  rx_len_dw_i,

  input  logic        tx_accept_i,
  input  logic [7:0]  tx_hdr0_i,
  input  logic [9:0]  tx_len_dw_i,

  output logic        free_ph_o,
  output logic        free_pd_o,
  output logic        free_nph_o,
  output logic        free_npd_o,
  output logic        free_cplh_o,
  output logic        free_cpld_o,
  output logic [7:0]  free_ph_amt_o,
  output logic [11:0] free_pd_amt_o,
  output logic [7:0]  free_nph_amt_o,
  output logic [11:0] free_npd_amt_o,
  output logic [7:0]  free_cplh_amt_o,
  output logic [11:0] free_cpld_amt_o,

  output logic        consume_ph_o,
  output logic        consume_pd_o,
  output logic        consume_nph_o,
  output logic        consume_npd_o,
  output logic        consume_cplh_o,
  output logic        consume_cpld_o,
  output logic [7:0]  consume_ph_amt_o,
  output logic [11:0] consume_pd_amt_o,
  output logic [7:0]  consume_nph_amt_o,
  output logic [11:0] consume_npd_amt_o,
  output logic [7:0]  consume_cplh_amt_o,
  output logic [11:0] consume_cpld_amt_o
);

  import rivet_pkg::*;

  rivet_fc_cls_e rx_cls, tx_cls;
  logic [11:0]   rx_dc, tx_dc;
  logic          rx_data, tx_data;

  assign rx_cls  = rivet_tlp_fc_class(rx_hdr0_i);
  assign tx_cls  = rivet_tlp_fc_class(tx_hdr0_i);
  assign rx_data = rivet_tlp_has_data(rx_hdr0_i);
  assign tx_data = rivet_tlp_has_data(tx_hdr0_i);
  assign rx_dc   = rx_data ? rivet_tlp_data_credits(rx_len_dw_i) : 12'd0;
  assign tx_dc   = tx_data ? rivet_tlp_data_credits(tx_len_dw_i) : 12'd0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      free_ph_o          <= 1'b0;
      free_pd_o          <= 1'b0;
      free_nph_o         <= 1'b0;
      free_npd_o         <= 1'b0;
      free_cplh_o        <= 1'b0;
      free_cpld_o        <= 1'b0;
      consume_ph_o       <= 1'b0;
      consume_pd_o       <= 1'b0;
      consume_nph_o      <= 1'b0;
      consume_npd_o      <= 1'b0;
      consume_cplh_o     <= 1'b0;
      consume_cpld_o     <= 1'b0;
      free_ph_amt_o      <= '0;
      free_pd_amt_o      <= '0;
      free_nph_amt_o     <= '0;
      free_npd_amt_o     <= '0;
      free_cplh_amt_o    <= '0;
      free_cpld_amt_o    <= '0;
      consume_ph_amt_o   <= '0;
      consume_pd_amt_o   <= '0;
      consume_nph_amt_o  <= '0;
      consume_npd_amt_o  <= '0;
      consume_cplh_amt_o <= '0;
      consume_cpld_amt_o <= '0;
    end else begin
      free_ph_o      <= 1'b0;
      free_pd_o      <= 1'b0;
      free_nph_o     <= 1'b0;
      free_npd_o     <= 1'b0;
      free_cplh_o    <= 1'b0;
      free_cpld_o    <= 1'b0;
      consume_ph_o   <= 1'b0;
      consume_pd_o   <= 1'b0;
      consume_nph_o  <= 1'b0;
      consume_npd_o  <= 1'b0;
      consume_cplh_o <= 1'b0;
      consume_cpld_o <= 1'b0;

      if (rx_accept_i) begin
        unique case (rx_cls)
          RIVET_FC_CLS_P: begin
            free_ph_o     <= 1'b1;
            free_ph_amt_o <= 8'd1;
            if (rx_data) begin
              free_pd_o     <= 1'b1;
              free_pd_amt_o <= rx_dc;
            end
          end
          RIVET_FC_CLS_NP: begin
            free_nph_o     <= 1'b1;
            free_nph_amt_o <= 8'd1;
            if (rx_data) begin
              free_npd_o     <= 1'b1;
              free_npd_amt_o <= rx_dc;
            end
          end
          default: begin
            free_cplh_o     <= 1'b1;
            free_cplh_amt_o <= 8'd1;
            if (rx_data) begin
              free_cpld_o     <= 1'b1;
              free_cpld_amt_o <= rx_dc;
            end
          end
        endcase
      end

      if (tx_accept_i) begin
        unique case (tx_cls)
          RIVET_FC_CLS_P: begin
            consume_ph_o     <= 1'b1;
            consume_ph_amt_o <= 8'd1;
            if (tx_data) begin
              consume_pd_o     <= 1'b1;
              consume_pd_amt_o <= tx_dc;
            end
          end
          RIVET_FC_CLS_NP: begin
            consume_nph_o     <= 1'b1;
            consume_nph_amt_o <= 8'd1;
            if (tx_data) begin
              consume_npd_o     <= 1'b1;
              consume_npd_amt_o <= tx_dc;
            end
          end
          default: begin
            consume_cplh_o     <= 1'b1;
            consume_cplh_amt_o <= 8'd1;
            if (tx_data) begin
              consume_cpld_o     <= 1'b1;
              consume_cpld_amt_o <= tx_dc;
            end
          end
        endcase
      end
    end
  end

endmodule : rivet_tl_credit
