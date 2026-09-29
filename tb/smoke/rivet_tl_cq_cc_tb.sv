// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Mem32 → CQ → PIO app → CC → CplD loopback.

`timescale 1ns/1ps

module rivet_tl_cq_cc_tb;
  import rivet_pkg::*;

  logic clk, rst_n;

  // Fake TLP stream into CQ
  logic [63:0] rx_d;
  logic [7:0]  rx_k;
  logic        rx_l, rx_v, rx_r;

  logic [63:0] cq_tdata, cc_tdata, cc_to_dll_d;
  logic [1:0]  cq_tkeep, cc_tkeep;
  logic        cq_tlast, cq_tvalid, cq_tready;
  logic        cc_tlast, cc_tvalid;
  logic [3:0]  cc_tready;
  logic [87:0] cq_tuser;
  logic [32:0] cc_tuser;
  logic [7:0]  cc_dll_k;
  logic        cc_dll_l, cc_dll_v, cc_dll_r;
  logic        rx_acc, tx_acc;
  logic [7:0]  rx_h0, tx_h0;
  logic [9:0]  rx_ln, tx_ln;
  logic [5:0]  np_cnt;

  rivet_tl_cq u_cq (
    .clk_i(clk), .rst_ni(rst_n),
    .rx_tdata_i(rx_d), .rx_tkeep_i(rx_k), .rx_tlast_i(rx_l),
    .rx_tvalid_i(rx_v), .rx_tready_o(rx_r),
    .bar0_base_i(32'h0000_0000), .bar0_mask_i(RIVET_CFG_BAR0_MASK),
    .bar0_mem_en_i(1'b1),
    .cq_np_req_i(2'b01), .cq_np_req_count_o(np_cnt),
    .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
    .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
    .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser(cq_tuser),
    .rx_accept_o(rx_acc), .rx_hdr0_o(rx_h0), .rx_len_dw_o(rx_ln)
  );

  rivet_tl_pio_app u_pio (
    .clk_i(clk), .rst_ni(rst_n),
    .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
    .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
    .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser(cq_tuser),
    .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
    .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
    .s_axis_cc_tready(cc_tready), .s_axis_cc_tuser(cc_tuser)
  );

  rivet_tl_cc u_cc (
    .clk_i(clk), .rst_ni(rst_n),
    .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
    .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
    .s_axis_cc_tready(cc_tready[0]), .s_axis_cc_tuser(cc_tuser),
    .tx_tdata_o(cc_to_dll_d), .tx_tkeep_o(cc_dll_k),
    .tx_tlast_o(cc_dll_l), .tx_tvalid_o(cc_dll_v), .tx_tready_i(cc_dll_r),
    .tx_accept_o(tx_acc), .tx_hdr0_o(tx_h0), .tx_len_dw_o(tx_ln)
  );

  assign cc_tready[3:1] = '0;
  assign cc_dll_r = 1'b1;

  initial clk = 1'b0;
  always #4 clk = ~clk;

  task automatic drive_two(input logic [63:0] a, input logic [63:0] b);
    @(posedge clk);
    rx_d = a; rx_k = 8'hFF; rx_l = 1'b0; rx_v = 1'b1;
    while (!(rx_v && rx_r)) @(posedge clk);
    @(posedge clk);
    rx_d = b; rx_l = 1'b1;
    while (!(rx_v && rx_r)) @(posedge clk);
    @(posedge clk);
    rx_v = 1'b0; rx_l = 1'b0;
  endtask

  initial begin
    rst_n = 1'b0;
    rx_v = 1'b0; rx_l = 1'b0; rx_d = '0; rx_k = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // MemWr32 1DW @ 0x10 data A1B2C3D4
    drive_two(
      {8'h0F, 8'h22, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_MEMWR32},
      {32'hA1B2_C3D4, 8'h10, 8'h00, 8'h00, 8'h00}
    );
    repeat (8) @(posedge clk);

    // MemRd32 1DW @ 0x10
    drive_two(
      {8'h0F, 8'h23, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_MEMRD32},
      {32'h0, 8'h10, 8'h00, 8'h00, 8'h00}
    );

    wait (cc_dll_v);
    if (cc_to_dll_d[7:0] !== RIVET_TLP_B0_CPLD) begin
      $error("CplD hdr %02h", cc_to_dll_d[7:0]);
      $fatal(1);
    end
    @(posedge clk);
    wait (cc_dll_v && cc_dll_l);
    if (cc_to_dll_d[63:32] !== 32'hA1B2_C3D4) begin
      $error("PIO readback %08h", cc_to_dll_d[63:32]);
      $fatal(1);
    end

    $display("PASS: rivet_tl_cq_cc_tb");
    $finish;
  end

  initial begin
    #50000;
    $error("timeout cq_cc tb");
    $fatal(1);
  end
endmodule : rivet_tl_cq_cc_tb
