// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
module rivet_tl_cq256_tb;
  import rivet_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_ni;
  logic [63:0] rx_tdata;
  logic        rx_tlast, rx_tvalid, rx_tready;
  logic [255:0] cq_tdata;
  logic [7:0]   cq_tkeep;
  logic         cq_tlast, cq_tvalid;
  logic         cq_tready;
  logic [87:0]  cq_tuser;
  int cycles;

  rivet_tl_cq256 u (
    .clk_i(clk), .rst_ni(rst_ni),
    .rx_tdata_i(rx_tdata), .rx_tkeep_i(8'hFF),
    .rx_tlast_i(rx_tlast), .rx_tvalid_i(rx_tvalid), .rx_tready_o(rx_tready),
    .bar0_base_i(32'h0), .bar0_mask_i(32'hFFFF_F000), .bar0_mem_en_i(1'b1),
    .cq_np_req_i(2'b00), .cq_np_req_count_o(),
    .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
    .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
    .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser(cq_tuser),
    .rx_accept_o(), .rx_hdr0_o(), .rx_len_dw_o()
  );

  initial begin
    cycles = 0;
    forever begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > 40) $fatal(1, "cq256 timeout");
    end
  end

  task automatic drive(input logic [63:0] data, input logic last);
    @(negedge clk);
    rx_tdata  = data;
    rx_tlast  = last;
    rx_tvalid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    rx_tvalid = 1'b0;
  endtask

  initial begin
    rst_ni = 0; rx_tvalid = 0; rx_tlast = 0; cq_tready = 0; rx_tdata = '0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_ni = 1;
    drive(64'h0FAB_0100_0100_0040, 1'b0);
    drive({32'hA1B2C3D4, 32'h1000_0000}, 1'b1);
    while (!cq_tvalid) @(negedge clk);
    if (cq_tdata[63:0] !== {32'h0, 32'h0000_0010}) $fatal(1, "DESC0");
    if (cq_tdata[78:75] !== RIVET_CQ_REQ_MEMWR) $fatal(1, "type");
    if (cq_tdata[73:64] !== 10'd1) $fatal(1, "len");
    if (cq_tdata[111:96] !== 16'h0100) $fatal(1, "req");
    if (cq_tdata[119:112] !== 8'hAB) $fatal(1, "tag");
    if (cq_tdata[191:128] !== {32'h0, 32'hA1B2C3D4}) $fatal(1, "data");
    if (cq_tkeep !== 8'h3F || cq_tlast !== 1'b1) $fatal(1, "keep/last");
    cq_tready = 1;
    @(posedge clk);
    @(negedge clk);
    if (cq_tvalid) $fatal(1, "extra beat");
    $display("PASS: cq256 memwr");
    $finish;
  end
endmodule
