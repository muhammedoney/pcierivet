// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Minimal AER / advisory path: user cfg_err_*_in → status outs + Device Status sticky.

module rivet_tl_aer (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic err_cor_in_i,
  input  logic err_uncor_in_i,

  output logic err_cor_out_o,
  output logic err_nonfatal_out_o,
  output logic err_fatal_out_o,

  // Pulse sticky set into Device Status (DW30[31:16] side) via cfg_space
  output logic set_cor_o,
  output logic set_nonfatal_o
);

  logic cor_d, uncor_d;
  logic [4:0] cor_cnt_q, nf_cnt_q;

  assign err_cor_out_o      = |cor_cnt_q;
  assign err_nonfatal_out_o = |nf_cnt_q;
  assign err_fatal_out_o    = 1'b0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cor_d          <= 1'b0;
      uncor_d        <= 1'b0;
      cor_cnt_q      <= '0;
      nf_cnt_q       <= '0;
      set_cor_o      <= 1'b0;
      set_nonfatal_o <= 1'b0;
    end else begin
      cor_d          <= err_cor_in_i;
      uncor_d        <= err_uncor_in_i;
      set_cor_o      <= 1'b0;
      set_nonfatal_o <= 1'b0;
      if (cor_cnt_q != '0) cor_cnt_q <= cor_cnt_q - 5'd1;
      if (nf_cnt_q  != '0) nf_cnt_q  <= nf_cnt_q  - 5'd1;

      if (err_cor_in_i && !cor_d) begin
        cor_cnt_q <= 5'd16;
        set_cor_o <= 1'b1;
      end
      // Uncorrectable treated as non-fatal advisory for Gen2 EP smoke (no severity table yet).
      if (err_uncor_in_i && !uncor_d) begin
        nf_cnt_q       <= 5'd16;
        set_nonfatal_o <= 1'b1;
      end
    end
  end

endmodule : rivet_tl_aer
