// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// UVM testbench top — DUT = rivet_pcie_ctrl at PIPE (LANES via plusarg / define).

`timescale 1ns/1ps

module rivet_tb_top;
  import uvm_pkg::*;
  import rivet_uvm_pkg::*;
  `include "uvm_macros.svh"

`ifndef RIVET_TB_LANES
  `define RIVET_TB_LANES 1
`endif

  localparam int unsigned LANES = `RIVET_TB_LANES;
  localparam int unsigned AXI_W = 64;
  localparam int unsigned KEEP_W = AXI_W / 8;

  logic user_clk;
  logic user_resetn;
  logic pclk;
  logic preset_n;

  initial begin
    user_clk = 0;
    forever #4 user_clk = ~user_clk; // 125 MHz stub
  end

  initial begin
    pclk = 0;
    forever #2 pclk = ~pclk; // 250 MHz stub
  end

  initial begin
    user_resetn = 0;
    preset_n    = 0;
    repeat (10) @(posedge user_clk);
    user_resetn = 1;
    preset_n    = 1;
  end

  // AXI-ST CQ
  logic [AXI_W-1:0]   m_axis_cq_tdata;
  logic [KEEP_W-1:0]  m_axis_cq_tkeep;
  logic               m_axis_cq_tlast, m_axis_cq_tvalid, m_axis_cq_tready;
  logic [87:0]        m_axis_cq_tuser;
  // CC
  logic [AXI_W-1:0]   s_axis_cc_tdata;
  logic [KEEP_W-1:0]  s_axis_cc_tkeep;
  logic               s_axis_cc_tlast, s_axis_cc_tvalid, s_axis_cc_tready;
  logic [32:0]        s_axis_cc_tuser;
  // RQ
  logic [AXI_W-1:0]   s_axis_rq_tdata;
  logic [KEEP_W-1:0]  s_axis_rq_tkeep;
  logic               s_axis_rq_tlast, s_axis_rq_tvalid, s_axis_rq_tready;
  logic [61:0]        s_axis_rq_tuser;
  // RC
  logic [AXI_W-1:0]   m_axis_rc_tdata;
  logic [KEEP_W-1:0]  m_axis_rc_tkeep;
  logic               m_axis_rc_tlast, m_axis_rc_tvalid, m_axis_rc_tready;
  logic [74:0]        m_axis_rc_tuser;
  // AXI-Lite
  logic [31:0] s_axil_awaddr, s_axil_wdata, s_axil_araddr, s_axil_rdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_awvalid, s_axil_awready, s_axil_wvalid, s_axil_wready;
  logic        s_axil_bvalid, s_axil_bready, s_axil_arvalid, s_axil_arready;
  logic        s_axil_rvalid, s_axil_rready;
  logic [1:0]  s_axil_bresp, s_axil_rresp;
  // PIPE
  logic [16*LANES-1:0] pipe_txdata, pipe_rxdata;
  logic [LANES-1:0]    pipe_txdatak, pipe_rxdatak, pipe_txcompliance;
  logic pipe_txdetectrx, pipe_txelecidle, pipe_txdatavalid;
  logic pipe_rxvalid, pipe_rxelecidle, pipe_phystatus, pipe_rxpolarity;
  logic [2:0] pipe_rxstatus, pipe_rate;
  logic [1:0] pipe_powerdown;
  logic link_up;

  assign m_axis_cq_tready = 1'b1;
  assign m_axis_rc_tready = 1'b1;
  assign s_axis_cc_tdata = '0;
  assign s_axis_cc_tkeep = '0;
  assign s_axis_cc_tlast = 1'b0;
  assign s_axis_cc_tvalid = 1'b0;
  assign s_axis_cc_tuser = '0;
  assign s_axis_rq_tdata = '0;
  assign s_axis_rq_tkeep = '0;
  assign s_axis_rq_tlast = 1'b0;
  assign s_axis_rq_tvalid = 1'b0;
  assign s_axis_rq_tuser = '0;
  assign s_axil_awaddr = '0;
  assign s_axil_awvalid = 1'b0;
  assign s_axil_wdata = '0;
  assign s_axil_wstrb = '0;
  assign s_axil_wvalid = 1'b0;
  assign s_axil_bready = 1'b1;
  assign s_axil_araddr = '0;
  assign s_axil_arvalid = 1'b0;
  assign s_axil_rready = 1'b1;
  assign pipe_rxdata = '0;
  assign pipe_rxdatak = '0;
  assign pipe_rxvalid = 1'b0;
  assign pipe_rxelecidle = 1'b1;
  assign pipe_rxstatus = '0;
  assign pipe_phystatus = 1'b0;

  rivet_pcie_ctrl #(
    .MODE(0),
    .GEN(2),
    .LANES(LANES),
    .AXI_DATA_WIDTH(AXI_W)
  ) dut (
    .user_clk(user_clk),
    .user_resetn(user_resetn),
    .pclk(pclk),
    .preset_n(preset_n),
    .m_axis_cq_tdata(m_axis_cq_tdata),
    .m_axis_cq_tkeep(m_axis_cq_tkeep),
    .m_axis_cq_tlast(m_axis_cq_tlast),
    .m_axis_cq_tvalid(m_axis_cq_tvalid),
    .m_axis_cq_tready(m_axis_cq_tready),
    .m_axis_cq_tuser(m_axis_cq_tuser),
    .s_axis_cc_tdata(s_axis_cc_tdata),
    .s_axis_cc_tkeep(s_axis_cc_tkeep),
    .s_axis_cc_tlast(s_axis_cc_tlast),
    .s_axis_cc_tvalid(s_axis_cc_tvalid),
    .s_axis_cc_tready(s_axis_cc_tready),
    .s_axis_cc_tuser(s_axis_cc_tuser),
    .s_axis_rq_tdata(s_axis_rq_tdata),
    .s_axis_rq_tkeep(s_axis_rq_tkeep),
    .s_axis_rq_tlast(s_axis_rq_tlast),
    .s_axis_rq_tvalid(s_axis_rq_tvalid),
    .s_axis_rq_tready(s_axis_rq_tready),
    .s_axis_rq_tuser(s_axis_rq_tuser),
    .m_axis_rc_tdata(m_axis_rc_tdata),
    .m_axis_rc_tkeep(m_axis_rc_tkeep),
    .m_axis_rc_tlast(m_axis_rc_tlast),
    .m_axis_rc_tvalid(m_axis_rc_tvalid),
    .m_axis_rc_tready(m_axis_rc_tready),
    .m_axis_rc_tuser(m_axis_rc_tuser),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .pipe_txdata(pipe_txdata),
    .pipe_txdatak(pipe_txdatak),
    .pipe_txdetectrx(pipe_txdetectrx),
    .pipe_txelecidle(pipe_txelecidle),
    .pipe_txcompliance(pipe_txcompliance),
    .pipe_txdatavalid(pipe_txdatavalid),
    .pipe_rxdata(pipe_rxdata),
    .pipe_rxdatak(pipe_rxdatak),
    .pipe_rxvalid(pipe_rxvalid),
    .pipe_rxelecidle(pipe_rxelecidle),
    .pipe_rxstatus(pipe_rxstatus),
    .pipe_phystatus(pipe_phystatus),
    .pipe_powerdown(pipe_powerdown),
    .pipe_rate(pipe_rate),
    .pipe_rxpolarity(pipe_rxpolarity),
    .link_up(link_up)
  );

  initial begin
    run_test();
  end
endmodule : rivet_tb_top
