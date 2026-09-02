// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Minimal TL credit stub: CA / free / consume inject for DLL FC (D3).

module rivet_tl_fc_stub #(
  parameter logic [7:0]  PH_CRED   = 8'h7F,
  parameter logic [11:0] PD_CRED   = 12'h7FF,
  parameter logic [7:0]  NPH_CRED  = 8'h7F,
  parameter logic [11:0] NPD_CRED  = 12'h7FF,
  parameter bit          CPL_INF   = 1'b1
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic        free_ph_i,
  input  logic        free_pd_i,
  input  logic        free_nph_i,
  input  logic        free_npd_i,
  input  logic        free_cplh_i,
  input  logic        free_cpld_i,
  input  logic [7:0]  free_ph_amt_i,
  input  logic [11:0] free_pd_amt_i,
  input  logic [7:0]  free_nph_amt_i,
  input  logic [11:0] free_npd_amt_i,
  input  logic [7:0]  free_cplh_amt_i,
  input  logic [11:0] free_cpld_amt_i,

  input  logic        consume_ph_i,
  input  logic        consume_pd_i,
  input  logic        consume_nph_i,
  input  logic        consume_npd_i,
  input  logic        consume_cplh_i,
  input  logic        consume_cpld_i,
  input  logic [7:0]  consume_ph_amt_i,
  input  logic [11:0] consume_pd_amt_i,
  input  logic [7:0]  consume_nph_amt_i,
  input  logic [11:0] consume_npd_amt_i,
  input  logic [7:0]  consume_cplh_amt_i,
  input  logic [11:0] consume_cpld_amt_i,

  output rivet_pkg::rivet_tl_dll_fc_sb_t tl_to_dll_fc_o,
  input  rivet_pkg::rivet_dll_tl_fc_sb_t dll_to_tl_fc_i
);

  import rivet_pkg::*;

  rivet_tl_dll_fc_sb_t sb_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sb_q             <= '0;
      sb_q.ca.ph       <= PH_CRED;
      sb_q.ca.pd       <= PD_CRED;
      sb_q.ca.nph      <= NPH_CRED;
      sb_q.ca.npd      <= NPD_CRED;
      sb_q.ca.cplh     <= CPL_INF ? 8'h00 : 8'h01;
      sb_q.ca.cpld     <= CPL_INF ? 12'h000 : 12'h001;
      sb_q.ca.ph_inf   <= 1'b0;
      sb_q.ca.pd_inf   <= 1'b0;
      sb_q.ca.nph_inf  <= 1'b0;
      sb_q.ca.npd_inf  <= 1'b0;
      sb_q.ca.cplh_inf <= CPL_INF;
      sb_q.ca.cpld_inf <= CPL_INF;
    end else begin
      sb_q.ph_freed   <= free_ph_i;
      sb_q.pd_freed   <= free_pd_i;
      sb_q.nph_freed  <= free_nph_i;
      sb_q.npd_freed  <= free_npd_i;
      sb_q.cplh_freed <= free_cplh_i;
      sb_q.cpld_freed <= free_cpld_i;

      if (free_ph_i && !sb_q.ca.ph_inf) sb_q.ca.ph <= sb_q.ca.ph + free_ph_amt_i;
      if (free_pd_i && !sb_q.ca.pd_inf) sb_q.ca.pd <= sb_q.ca.pd + free_pd_amt_i;
      if (free_nph_i && !sb_q.ca.nph_inf) sb_q.ca.nph <= sb_q.ca.nph + free_nph_amt_i;
      if (free_npd_i && !sb_q.ca.npd_inf) sb_q.ca.npd <= sb_q.ca.npd + free_npd_amt_i;
      if (free_cplh_i && !sb_q.ca.cplh_inf) sb_q.ca.cplh <= sb_q.ca.cplh + free_cplh_amt_i;
      if (free_cpld_i && !sb_q.ca.cpld_inf) sb_q.ca.cpld <= sb_q.ca.cpld + free_cpld_amt_i;

      sb_q.consume_ph        <= consume_ph_i;
      sb_q.consume_pd        <= consume_pd_i;
      sb_q.consume_nph       <= consume_nph_i;
      sb_q.consume_npd       <= consume_npd_i;
      sb_q.consume_cplh      <= consume_cplh_i;
      sb_q.consume_cpld      <= consume_cpld_i;
      sb_q.consume_ph_amt    <= consume_ph_amt_i;
      sb_q.consume_pd_amt    <= consume_pd_amt_i;
      sb_q.consume_nph_amt   <= consume_nph_amt_i;
      sb_q.consume_npd_amt   <= consume_npd_amt_i;
      sb_q.consume_cplh_amt  <= consume_cplh_amt_i;
      sb_q.consume_cpld_amt  <= consume_cpld_amt_i;
    end
  end

  assign tl_to_dll_fc_o = sb_q;

  logic _unused_dll;
  assign _unused_dll = |dll_to_tl_fc_i;

endmodule : rivet_tl_fc_stub
