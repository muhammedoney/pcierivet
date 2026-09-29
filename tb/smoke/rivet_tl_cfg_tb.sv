// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Fabric CfgRd0/CfgWr0 + cfg_mgmt against rivet_tl_cfg_space.

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

  logic        fab_req, fab_write, fab_ack, fab_busy;
  logic [9:0]  fab_addr;
  logic [3:0]  fab_be;
  logic [31:0] fab_wdata, fab_rdata;

  logic [9:0]  mgmt_addr;
  logic [7:0]  mgmt_fn;
  logic        mgmt_wr, mgmt_rd, mgmt_done;
  logic [31:0] mgmt_wdata, mgmt_rdata;
  logic [3:0]  mgmt_be;

  logic [31:0] bar0_base, bar0_mask;
  logic        bar0_mem_en;

  rivet_tl_cfg_space u_space (
    .clk_i(clk), .rst_ni(rst_n),
    .fab_req_i(fab_req), .fab_write_i(fab_write),
    .fab_addr_i(fab_addr), .fab_be_i(fab_be), .fab_wdata_i(fab_wdata),
    .fab_rdata_o(fab_rdata), .fab_ack_o(fab_ack), .fab_busy_o(fab_busy),
    .cfg_mgmt_addr_i(mgmt_addr), .cfg_mgmt_function_number_i(mgmt_fn),
    .cfg_mgmt_write_i(mgmt_wr), .cfg_mgmt_write_data_i(mgmt_wdata),
    .cfg_mgmt_byte_enable_i(mgmt_be), .cfg_mgmt_read_i(mgmt_rd),
    .cfg_mgmt_read_data_o(mgmt_rdata), .cfg_mgmt_read_write_done_o(mgmt_done),
    .cfg_mgmt_debug_access_i(1'b0),
    .bar0_base_o(bar0_base), .bar0_mask_o(bar0_mask), .bar0_mem_en_o(bar0_mem_en),
    .link_up_i(1'b1), .link_speed_i(4'h1), .link_width_i(6'h4)
  );

  rivet_tl_cfg u_dut (
    .clk_i(clk), .rst_ni(rst_n),
    .rx_tdata_i(rx_d), .rx_tkeep_i(rx_k), .rx_tlast_i(rx_l),
    .rx_tvalid_i(rx_v), .rx_tready_o(rx_r),
    .tx_tdata_o(tx_d), .tx_tkeep_o(tx_k), .tx_tlast_o(tx_l),
    .tx_tvalid_o(tx_v), .tx_tready_i(tx_r),
    .fab_req_o(fab_req), .fab_write_o(fab_write),
    .fab_addr_o(fab_addr), .fab_be_o(fab_be), .fab_wdata_o(fab_wdata),
    .fab_rdata_i(fab_rdata), .fab_ack_i(fab_ack), .fab_busy_i(fab_busy),
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

  task automatic mgmt_read(input logic [9:0] a, output logic [31:0] d);
    @(posedge clk);
    mgmt_addr = a; mgmt_fn = 8'h00; mgmt_be = 4'hF;
    mgmt_rd = 1'b1; mgmt_wr = 1'b0;
    @(posedge clk);
    mgmt_rd = 1'b0;
    wait (mgmt_done);
    d = mgmt_rdata;
    @(posedge clk);
  endtask

  task automatic mgmt_write(input logic [9:0] a, input logic [31:0] d,
                            input logic [3:0] be);
    @(posedge clk);
    mgmt_addr = a; mgmt_fn = 8'h00; mgmt_be = be; mgmt_wdata = d;
    mgmt_wr = 1'b1; mgmt_rd = 1'b0;
    @(posedge clk);
    mgmt_wr = 1'b0;
    wait (mgmt_done);
    @(posedge clk);
  endtask

  initial begin
    rst_n = 1'b0;
    rx_v = 1'b0; rx_l = 1'b0; rx_d = '0; rx_k = '0; tx_r = 1'b1;
    mgmt_addr = '0; mgmt_fn = '0; mgmt_wr = 1'b0; mgmt_rd = 1'b0;
    mgmt_wdata = '0; mgmt_be = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // --- cfg_mgmt: Vendor/Device ---
    begin
      automatic logic [31:0] d;
      mgmt_read(10'd0, d);
      if (d[15:0] !== RIVET_CFG_VENDOR_ID || d[31:16] !== RIVET_CFG_DEVICE_ID) begin
        $error("mgmt vendor %08h", d);
        $fatal(1);
      end
    end

    // Enable Memory Space via cfg_mgmt
    mgmt_write(10'd1, 32'h0000_0002, 4'h1);

    // BAR0 size probe
    mgmt_write(10'd4, 32'hFFFF_FFFF, 4'hF);
    begin
      automatic logic [31:0] d;
      mgmt_read(10'd4, d);
      if (d !== RIVET_CFG_BAR0_MASK) begin
        $error("BAR0 mask mgmt %08h", d);
        $fatal(1);
      end
    end
    // Program BAR0 base 0
    mgmt_write(10'd4, 32'h0000_0000, 4'hF);

    // Cap pointer
    begin
      automatic logic [31:0] d;
      mgmt_read(10'd13, d);
      if (d[7:0] !== RIVET_CFG_CAP_PTR) begin
        $error("cap ptr %02h", d[7:0]);
        $fatal(1);
      end
      mgmt_read(10'd16, d); // PM
      if (d[7:0] !== 8'h01) begin $error("PM id"); $fatal(1); end
      mgmt_read(10'd20, d); // MSI
      if (d[7:0] !== 8'h05) begin $error("MSI id"); $fatal(1); end
      mgmt_read(10'd28, d); // PCIe
      if (d[7:0] !== 8'h10) begin $error("PCIe id"); $fatal(1); end
    end

    // --- Fabric CfgRd0 Vendor ---
    beat0 = {8'h0F, 8'h11, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_CFGRD0};
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

    // Fabric CfgWr0 BAR0 FFFFFFFF → mask
    beat0 = {8'h0F, 8'h11, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_CFGWR0};
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

    beat0 = {8'h0F, 8'h11, 8'h00, 8'h01, 8'h00, 8'h01, 8'h00, RIVET_TLP_B0_CFGRD0};
    beat1 = {32'h0, 8'h10, 8'h00, 8'h00, 8'h00};
    drive_two(beat0, beat1, 8'h0F);
    wait (tx_v);
    @(posedge clk);
    wait (tx_v && tx_l);
    if (tx_d[63:32] !== RIVET_CFG_BAR0_MASK) begin
      $error("BAR0 mask got %08h", tx_d[63:32]);
      $fatal(1);
    end

    if (!bar0_mem_en) begin
      $error("MSE not set");
      $fatal(1);
    end

    $display("PASS: rivet_tl_cfg_tb");
    $finish;
  end

  initial begin
    #50000;
    $error("timeout cfg tb");
    $fatal(1);
  end
endmodule : rivet_tl_cfg_tb
