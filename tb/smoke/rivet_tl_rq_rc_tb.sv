// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// RQ Mem32 pack + RC CplD unpack smoke.

`timescale 1ns/1ps

module rivet_tl_rq_rc_tb;
  import rivet_pkg::*;

  logic clk, rst_n;

  logic [63:0] rq_tdata, rq_tx_d, rc_rx_d, rc_tdata;
  logic [1:0]  rq_tkeep, rc_tkeep;
  logic        rq_tlast, rq_tvalid, rq_tready;
  logic        rq_tx_l, rq_tx_v, rq_tx_r;
  logic [7:0]  rq_tx_k;
  logic [84:0] rq_tuser;
  logic        rc_rx_l, rc_rx_v, rc_rx_r;
  logic [7:0]  rc_rx_k;
  logic        rc_tlast, rc_tvalid, rc_tready;
  logic [74:0] rc_tuser;
  logic        rq_acc, rc_acc;
  logic [7:0]  rq_h0, rc_h0;
  logic [9:0]  rq_ln, rc_ln;

  rivet_tl_rq u_rq (
    .clk_i(clk), .rst_ni(rst_n),
    .bus_master_en_i(1'b1),
    .s_axis_rq_tdata(rq_tdata), .s_axis_rq_tkeep(rq_tkeep),
    .s_axis_rq_tlast(rq_tlast), .s_axis_rq_tvalid(rq_tvalid),
    .s_axis_rq_tready(rq_tready), .s_axis_rq_tuser(rq_tuser),
    .tx_tdata_o(rq_tx_d), .tx_tkeep_o(rq_tx_k),
    .tx_tlast_o(rq_tx_l), .tx_tvalid_o(rq_tx_v), .tx_tready_i(rq_tx_r),
    .tx_accept_o(rq_acc), .tx_hdr0_o(rq_h0), .tx_len_dw_o(rq_ln)
  );

  rivet_tl_rc u_rc (
    .clk_i(clk), .rst_ni(rst_n),
    .rx_tdata_i(rc_rx_d), .rx_tkeep_i(rc_rx_k), .rx_tlast_i(rc_rx_l),
    .rx_tvalid_i(rc_rx_v), .rx_tready_o(rc_rx_r),
    .m_axis_rc_tdata(rc_tdata), .m_axis_rc_tkeep(rc_tkeep),
    .m_axis_rc_tlast(rc_tlast), .m_axis_rc_tvalid(rc_tvalid),
    .m_axis_rc_tready(rc_tready), .m_axis_rc_tuser(rc_tuser),
    .rx_accept_o(rc_acc), .rx_hdr0_o(rc_h0), .rx_len_dw_o(rc_ln)
  );

  assign rq_tx_r  = 1'b1;
  assign rc_tready = 1'b1;

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic push_rq(input logic [63:0] d, input logic last);
    @(posedge clk);
    rq_tdata = d; rq_tkeep = 2'b11; rq_tlast = last; rq_tvalid = 1'b1;
    while (!(rq_tvalid && rq_tready)) @(posedge clk);
    @(posedge clk);
    rq_tvalid = 1'b0; rq_tlast = 1'b0;
  endtask

  task automatic push_rc(input logic [63:0] a, input logic [63:0] b);
    @(posedge clk);
    rc_rx_d = a; rc_rx_k = 8'hFF; rc_rx_l = 1'b0; rc_rx_v = 1'b1;
    while (!(rc_rx_v && rc_rx_r)) @(posedge clk);
    @(posedge clk);
    rc_rx_d = b; rc_rx_l = 1'b1;
    while (!(rc_rx_v && rc_rx_r)) @(posedge clk);
    @(posedge clk);
    rc_rx_v = 1'b0; rc_rx_l = 1'b0;
  endtask

  initial begin
    rst_n = 1'b0;
    rq_tdata = '0; rq_tkeep = '0; rq_tlast = 1'b0; rq_tvalid = 1'b0;
    rq_tuser = '0;
    rc_rx_d = '0; rc_rx_k = '0; rc_rx_l = 1'b0; rc_rx_v = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // RQ MemWr32 1DW @ 0x20 data DEADBEEF
    rq_tuser[7:0] = 8'h0F; // first_be=F last_be=0
    push_rq({32'h0, 32'h0000_0020}, 1'b0); // addr 0x20 (AT=0)
    push_rq({8'h00, 8'h44, 16'h0000, 32'h0000_0801}, 1'b0); // tag=0x44, MemWr, len=1
    push_rq({32'h0, 32'hDEAD_BEEF}, 1'b1);

    wait (rq_tx_v);
    if (rq_tx_d[7:0] !== RIVET_TLP_B0_MEMWR32) begin
      $error("RQ MemWr hdr %02h", rq_tx_d[7:0]);
      $fatal(1);
    end
    @(posedge clk);
    wait (rq_tx_v && rq_tx_l);
    if (rq_tx_d[63:32] !== 32'hDEAD_BEEF) begin
      $error("RQ MemWr data %08h", rq_tx_d[63:32]);
      $fatal(1);
    end
    // Wire addr byte order matches CQ unpack (A[7:0] in [31:24])
    if (rq_tx_d[31:24] !== 8'h20) begin
      $error("RQ MemWr addr byte %02h", rq_tx_d[31:24]);
      $fatal(1);
    end

    // RC CplD 1DW data CAFEBABE tag 0x55
    push_rc(
      {8'h04, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, 8'h00, RIVET_TLP_B0_CPLD},
      {32'hCAFE_BABE, 8'h00, 8'h55, 8'h00, 8'h01}
    );

    wait (rc_tvalid && rc_tlast);
    // Last beat is data
    if (rc_tdata[31:0] !== 32'hCAFE_BABE) begin
      $error("RC data %08h", rc_tdata[31:0]);
      $fatal(1);
    end

    $display("PASS: rivet_tl_rq_rc_tb");
    $finish;
  end

  initial begin
    #50000;
    $error("timeout rq_rc tb");
    $fatal(1);
  end
endmodule : rivet_tl_rq_rc_tb
