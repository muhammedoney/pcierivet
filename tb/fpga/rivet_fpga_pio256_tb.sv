// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
module rivet_fpga_pio256_tb;
  import rivet_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_ni, cq_tvalid, cq_tready, cq_tlast, cc_tvalid, cc_tlast;
  logic [255:0] cq_tdata, cc_tdata;
  logic [7:0] cq_tkeep, cc_tkeep;
  logic [3:0] cc_tready;
  int cycles;
  int guard;

  rivet_fpga_pio256 u (
    .clk_i(clk), .rst_ni(rst_ni),
    .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
    .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
    .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser('0),
    .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
    .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
    .s_axis_cc_tready(cc_tready), .s_axis_cc_tuser()
  );

  initial begin
    cycles = 0;
    forever begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > 800) $fatal(1, "pio256 timeout");
    end
  end

  task automatic cq(input logic wr, input logic [31:0] addr,
                    input logic [31:0] data, input logic [9:0] len);
    @(negedge clk);
    cq_tdata = '0;
    cq_tdata[31:2] = addr[31:2];
    cq_tdata[73:64] = len;
    cq_tdata[78:75] = wr ? RIVET_CQ_REQ_MEMWR : RIVET_CQ_REQ_MEMRD;
    cq_tdata[111:96] = 16'h0100;
    cq_tdata[119:112] = 8'h11;
    cq_tdata[159:128] = data;
    cq_tkeep = wr ? 8'h3F : 8'h0F;
    cq_tlast = 1'b1;
    cq_tvalid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    cq_tvalid = 1'b0;
  endtask

  initial begin
    rst_ni = 0; cq_tvalid = 0; cc_tready = 4'h0; cq_tdata = '0; cq_tlast = 0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_ni = 1;
    repeat (300) @(posedge clk);
    cq(1'b1, 32'h0000_0010, 32'hA1B2C3D4, 10'd1);
    guard = 0;
    repeat (4) begin
      @(negedge clk);
      if (cc_tvalid) $fatal(1, "posted write completed");
      guard = guard + 1;
    end
    cq(1'b0, 32'h0000_0010, 32'h0, 10'd1);
    while (!cc_tvalid) @(negedge clk);
    if (cc_tdata[159:128] !== 32'hA1B2C3D4) $fatal(1, "read data");
    if (cc_tkeep !== 8'h3F || cc_tlast !== 1'b1) $fatal(1, "cpld shape");
    if (cc_tdata[45:43] !== 3'b000) $fatal(1, "status");
    cc_tready = 4'hF;
    @(posedge clk);
    @(negedge clk);
    cc_tready = 4'h0;
    cq(1'b0, 32'h0000_0020, 32'h0, 10'd2);
    repeat (8) @(negedge clk);
    if (cc_tvalid) $fatal(1, "multi-DW produced a completion");
    $display("PASS: pio256");
    $finish;
  end
endmodule
