// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Minimal TL credit stub: parameterized CA advertisement toward DLL (no TLP).

module rivet_tl_fc_stub #(
  // Smoke-friendly large finite P/NP; CPL infinite (EP policy).
  parameter logic [7:0]  PH_CRED   = 8'h7F,
  parameter logic [11:0] PD_CRED   = 12'h7FF,
  parameter logic [7:0]  NPH_CRED  = 8'h7F,
  parameter logic [11:0] NPD_CRED  = 12'h7FF,
  parameter bit          CPL_INF   = 1'b1
) (
  input  logic clk_i,
  input  logic rst_ni,

  output rivet_pkg::rivet_tl_dll_fc_sb_t tl_to_dll_fc_o,
  input  rivet_pkg::rivet_dll_tl_fc_sb_t dll_to_tl_fc_i
);

  import rivet_pkg::*;

  rivet_tl_dll_fc_sb_t sb_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sb_q            <= '0;
      sb_q.ca.ph      <= PH_CRED;
      sb_q.ca.pd      <= PD_CRED;
      sb_q.ca.nph     <= NPH_CRED;
      sb_q.ca.npd     <= NPD_CRED;
      sb_q.ca.cplh    <= CPL_INF ? 8'h00 : 8'h01;
      sb_q.ca.cpld    <= CPL_INF ? 12'h000 : 12'h001;
      sb_q.ca.ph_inf  <= 1'b0;
      sb_q.ca.pd_inf  <= 1'b0;
      sb_q.ca.nph_inf <= 1'b0;
      sb_q.ca.npd_inf <= 1'b0;
      sb_q.ca.cplh_inf <= CPL_INF;
      sb_q.ca.cpld_inf <= CPL_INF;
    end else begin
      // Freed pulses unused in D0; keep CA sticky.
      sb_q.ph_freed   <= 1'b0;
      sb_q.pd_freed   <= 1'b0;
      sb_q.nph_freed  <= 1'b0;
      sb_q.npd_freed  <= 1'b0;
      sb_q.cplh_freed <= 1'b0;
      sb_q.cpld_freed <= 1'b0;
    end
  end

  assign tl_to_dll_fc_o = sb_q;

  logic _unused_dll;
  assign _unused_dll = |dll_to_tl_fc_i;

endmodule : rivet_tl_fc_stub
