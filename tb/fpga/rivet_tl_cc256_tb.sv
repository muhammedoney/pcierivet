// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
module rivet_tl_cc256_tb;
  import rivet_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_ni, cc_tvalid, cc_tready, cc_tlast, tx_tvalid, tx_tready, tx_tlast;
  logic [255:0] cc_tdata;
  logic [7:0] cc_tkeep;
  logic [63:0] tx_tdata;
  logic [7:0] tx_tkeep;
  int cycles;

  rivet_tl_cc256 u (
    .clk_i(clk), .rst_ni(rst_ni),
    .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
    .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
    .s_axis_cc_tready(cc_tready), .s_axis_cc_tuser('0),
    .tx_tdata_o(tx_tdata), .tx_tkeep_o(tx_tkeep),
    .tx_tlast_o(tx_tlast), .tx_tvalid_o(tx_tvalid), .tx_tready_i(tx_tready),
    .tx_accept_o(), .tx_hdr0_o(), .tx_len_dw_o()
  );

  initial begin
    cycles = 0;
    forever begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > 40) $fatal(1, "cc256 timeout");
    end
  end

  initial begin
    rst_ni = 0; cc_tvalid = 0; cc_tlast = 0; cc_tkeep = 0; cc_tdata = '0;
    tx_tready = 0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_ni = 1;
    cc_tdata = '0;
    cc_tdata[6:0] = 7'h10;
    cc_tdata[27:16] = 12'd4;
    cc_tdata[41:32] = 10'd1;
    cc_tdata[45:43] = 3'b000;
    cc_tdata[64 +: 8] = 8'hAB;
    cc_tdata[80 +: 16] = 16'h0100;
    cc_tdata[159:128] = 32'hA1B2C3D4;
    cc_tkeep = 8'h3F;
    cc_tlast = 1'b1;
    cc_tvalid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    cc_tvalid = 1'b0;
    while (!tx_tvalid) @(negedge clk);
    if (tx_tdata[7:0] !== RIVET_TLP_B0_CPLD) $fatal(1, "cpld type");
    if (tx_tlast !== 1'b0) $fatal(1, "first beat is not last");
    tx_tready = 1;
    @(posedge clk);
    @(negedge clk);
    tx_tready = 0;
    if (tx_tdata[7:0] !== 8'h00) $fatal(1, "req id lo");
    if (tx_tdata[15:8] !== 8'h01) $fatal(1, "req id hi");
    if (tx_tdata[23:16] !== 8'hAB) $fatal(1, "tag");
    if (tx_tdata[39:32] !== 8'hD4) $fatal(1, "data0");
    if (tx_tdata[63:56] !== 8'hA1) $fatal(1, "data3");
    if (tx_tlast !== 1'b1) $fatal(1, "eop");
    $display("PASS: cc256 cpld");
    $finish;
  end
endmodule
