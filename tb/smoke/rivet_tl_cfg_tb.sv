// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Type 0 CfgRd0 → CplD Vendor/Device; CfgWr0 BAR0 masked.

`timescale 1ns/1ps

module rivet_tl_cfg_tb;
  import rivet_pkg::*;

  logic clk, rst_n;
  logic [63:0] rx_d, tx_d;
  logic [7:0]  rx_k, tx_k;
  logic        rx_l, rx_v, rx_r;
  logic        tx_l, tx_v, tx_r;
  logic        rx_acc, tx_acc;
  logic [7:0]  rx_h0, tx_h0;
  logic [9:0]  rx_ln, tx_ln;

  rivet_tl_cfg u_dut (
    .clk_i(clk), .rst_ni(rst_n),
    .rx_tdata_i(rx_d), .rx_tkeep_i(rx_k), .rx_tlast_i(rx_l),
    .rx_tvalid_i(rx_v), .rx_tready_o(rx_r),
    .tx_tdata_o(tx_d), .tx_tkeep_o(tx_k), .tx_tlast_o(tx_l),
    .tx_tvalid_o(tx_v), .tx_tready_i(tx_r),
    .rx_accept_o(rx_acc), .rx_hdr0_o(rx_h0), .rx_len_dw_o(rx_ln),
    .tx_accept_o(tx_acc), .tx_hdr0_o(tx_h0), .tx_len_dw_o(tx_ln)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  logic [63:0] beat0, beat1;

  task automatic drive_two(input logic [63:0] a, input logic [63:0] b,
                           input logic [7:0] kb);
    @(posedge clk);
    rx_d = a; rx_k = 8'hFF; rx_l = 1'b0; rx_v = 1'b1;
    @(posedge clk);
    rx_d = b; rx_k = kb; rx_l = 1'b1;
    @(posedge clk);
    rx_v = 1'b0; rx_l = 1'b0;
  endtask

  initial begin
    rst_n = 1'b0;
    rx_v = 1'b0;
    rx_l = 1'b0;
    rx_d = '0;
    rx_k = '0;
    tx_r = 1'b1;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    beat0 = {8'h0F, 8'h11, 8'h01, 8'h00, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_CFGRD0};
    beat1 = {32'h0, 8'h00, 8'h00, 8'h00, 8'h00};
    drive_two(beat0, beat1, 8'h0F);

    wait (tx_v);
    if (tx_d[7:0] !== RIVET_TLP_B0_CPLD) begin
      $error("beat0 not CplD %02h", tx_d[7:0]);
      $fatal(1);
    end
    @(posedge clk);
    wait (tx_v && tx_l);
    if (tx_d[47:32] !== RIVET_CFG_VENDOR_ID) begin
      $error("vendor mismatch %04h", tx_d[47:32]);
      $fatal(1);
    end
    if (tx_d[63:48] !== RIVET_CFG_DEVICE_ID) begin
      $error("device mismatch %04h", tx_d[63:48]);
      $fatal(1);
    end
    @(posedge clk);

    beat0 = {8'h0F, 8'h11, 8'h01, 8'h00, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_CFGWR0};
    beat1 = {32'hFFFF_FFFF, 8'h10, 8'h00, 8'h00, 8'h00};
    drive_two(beat0, beat1, 8'hFF);
    wait (tx_v);
    if (tx_d[7:0] !== RIVET_TLP_B0_CPL) begin
      $error("expected Cpl %02h", tx_d[7:0]);
      $fatal(1);
    end
    @(posedge clk);
    wait (tx_v && tx_l);
    @(posedge clk);

    beat0 = {8'h0F, 8'h11, 8'h01, 8'h00, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_CFGRD0};
    beat1 = {32'h0, 8'h10, 8'h00, 8'h00, 8'h00};
    drive_two(beat0, beat1, 8'h0F);
    wait (tx_v);
    @(posedge clk);
    wait (tx_v && tx_l);
    if (tx_d[63:32] !== RIVET_CFG_BAR0_MASK) begin
      $error("BAR0 mask got %08h", tx_d[63:32]);
      $fatal(1);
    end

    $display("PASS: rivet_tl_cfg_tb");
    $finish;
  end

  initial begin
    #20000;
    $error("timeout cfg tb");
    $fatal(1);
  end
endmodule : rivet_tl_cfg_tb
