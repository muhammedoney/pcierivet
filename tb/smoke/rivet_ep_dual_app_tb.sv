// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Dual-app completer + bus-master MemWr smoke (RQ→wire).

`timescale 1ns/1ps

module rivet_ep_dual_app_tb;
  import rivet_pkg::*;

  logic clk, rst_n;

  logic [63:0] cq_tdata, cc_tdata, rq_tdata, rq_tx_d, rc_tdata;
  logic [1:0]  cq_tkeep, cc_tkeep, rq_tkeep, rc_tkeep;
  logic        cq_tlast, cq_tvalid, cq_tready;
  logic        cc_tlast, cc_tvalid;
  logic [3:0]  cc_tready, rq_tready;
  logic        rq_tlast, rq_tvalid;
  logic        rc_tlast, rc_tvalid, rc_tready;
  logic [87:0] cq_tuser;
  logic [32:0] cc_tuser;
  logic [84:0] rq_tuser;
  logic [74:0] rc_tuser;
  logic [7:0]  rq_tx_k;
  logic        rq_tx_l, rq_tx_v, rq_tx_r, rq_acc, rq_rdy;
  logic [7:0]  rq_h0;
  logic [9:0]  rq_ln;

  logic        bm_go, bm_do_wr, bm_do_rd, bm_busy, bm_done, bm_err;
  logic [31:0] bm_host_addr, bm_wr_data, bm_rd_data;

  // Idle CQ/RC (completer unused in this smoke)
  assign cq_tdata  = '0;
  assign cq_tkeep  = '0;
  assign cq_tlast  = 1'b0;
  assign cq_tvalid = 1'b0;
  assign cq_tuser  = '0;
  assign rc_tdata  = '0;
  assign rc_tkeep  = '0;
  assign rc_tlast  = 1'b0;
  assign rc_tvalid = 1'b0;
  assign rc_tuser  = '0;

  rivet_ep_dual_app u_app (
    .clk_i(clk), .rst_ni(rst_n),
    .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
    .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
    .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser(cq_tuser),
    .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
    .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
    .s_axis_cc_tready(cc_tready), .s_axis_cc_tuser(cc_tuser),
    .s_axis_rq_tdata(rq_tdata), .s_axis_rq_tkeep(rq_tkeep),
    .s_axis_rq_tlast(rq_tlast), .s_axis_rq_tvalid(rq_tvalid),
    .s_axis_rq_tready(rq_tready), .s_axis_rq_tuser(rq_tuser),
    .m_axis_rc_tdata(rc_tdata), .m_axis_rc_tkeep(rc_tkeep),
    .m_axis_rc_tlast(rc_tlast), .m_axis_rc_tvalid(rc_tvalid),
    .m_axis_rc_tready(rc_tready), .m_axis_rc_tuser(rc_tuser),
    .bm_go_i(bm_go), .bm_do_wr_i(bm_do_wr), .bm_do_rd_i(bm_do_rd),
    .bm_host_addr_i(bm_host_addr), .bm_wr_data_i(bm_wr_data),
    .bm_rd_data_o(bm_rd_data), .bm_busy_o(bm_busy),
    .bm_done_o(bm_done), .bm_err_o(bm_err)
  );

  rivet_tl_rq u_rq (
    .clk_i(clk), .rst_ni(rst_n),
    .bus_master_en_i(1'b1),
    .s_axis_rq_tdata(rq_tdata), .s_axis_rq_tkeep(rq_tkeep),
    .s_axis_rq_tlast(rq_tlast), .s_axis_rq_tvalid(rq_tvalid),
    .s_axis_rq_tready(rq_rdy), .s_axis_rq_tuser(rq_tuser),
    .tx_tdata_o(rq_tx_d), .tx_tkeep_o(rq_tx_k),
    .tx_tlast_o(rq_tx_l), .tx_tvalid_o(rq_tx_v), .tx_tready_i(rq_tx_r),
    .tx_accept_o(rq_acc), .tx_hdr0_o(rq_h0), .tx_len_dw_o(rq_ln)
  );

  assign rq_tready = {4{rq_rdy}};
  assign rq_tx_r = 1'b1;
  assign cc_tready = 4'hF;

  initial clk = 1'b0;
  always #4 clk = ~clk;

  initial begin
    rst_n = 1'b0;
    bm_go = 1'b0; bm_do_wr = 1'b0; bm_do_rd = 1'b0;
    bm_host_addr = '0; bm_wr_data = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    bm_host_addr = 32'h0000_1000;
    bm_wr_data   = 32'hAABB_CCDD;
    bm_do_wr     = 1'b1;
    bm_do_rd     = 1'b0;
    bm_go        = 1'b1;
    repeat (2) @(posedge clk);
    while (!bm_busy) @(posedge clk);
    bm_go = 1'b0;

    wait (rq_tx_v);
    if (rq_tx_d[7:0] !== RIVET_TLP_B0_MEMWR32) begin
      $error("dual BM MemWr hdr %02h", rq_tx_d[7:0]);
      $fatal(1);
    end
    @(posedge clk);
    wait (rq_tx_v && rq_tx_l);
    if (rq_tx_d[63:32] !== 32'hAABB_CCDD) begin
      $error("dual BM data %08h", rq_tx_d[63:32]);
      $fatal(1);
    end
    wait (bm_done);
    if (bm_err) begin
      $error("bm_err");
      $fatal(1);
    end

    $display("PASS: rivet_ep_dual_app_tb");
    $finish;
  end

  initial begin
    #50000;
    $error("timeout dual_app tb");
    $fatal(1);
  end
endmodule : rivet_ep_dual_app_tb
