// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Full Rivet PCIe soft IP: rivet_pcie_ctrl + family PHY (PG239).
// FPGA_FAMILY: 0 = UltraScale+, 1 = UltraScale

module rivet_pcie #(
  parameter int unsigned MODE            = 0,
  parameter int unsigned GEN             = 2,
  parameter int unsigned LANES           = 1,
  parameter int unsigned AXI_DATA_WIDTH  = 64,
  parameter int unsigned AXI_KEEP_WIDTH  = AXI_DATA_WIDTH / 8,
  parameter int unsigned AXI_CQ_USER_W   = 88,
  parameter int unsigned AXI_CC_USER_W   = 33,
  parameter int unsigned AXI_RQ_USER_W   = 62,
  parameter int unsigned AXI_RC_USER_W   = 75,
  parameter int unsigned PIPE_DATA_WIDTH = 16,
  parameter int unsigned AXIL_ADDR_WIDTH = 32,
  parameter int unsigned AXIL_DATA_WIDTH = 32,
  parameter int unsigned FPGA_FAMILY     = 0
) (
  input  logic user_clk,
  input  logic user_resetn,
  input  logic pclk,
  input  logic preset_n,
  input  logic sys_clk,
  input  logic sys_reset_n,

  output logic [AXI_DATA_WIDTH-1:0]  m_axis_cq_tdata,
  output logic [AXI_KEEP_WIDTH-1:0]  m_axis_cq_tkeep,
  output logic                       m_axis_cq_tlast,
  output logic                       m_axis_cq_tvalid,
  input  logic                       m_axis_cq_tready,
  output logic [AXI_CQ_USER_W-1:0]   m_axis_cq_tuser,

  input  logic [AXI_DATA_WIDTH-1:0]  s_axis_cc_tdata,
  input  logic [AXI_KEEP_WIDTH-1:0]  s_axis_cc_tkeep,
  input  logic                       s_axis_cc_tlast,
  input  logic                       s_axis_cc_tvalid,
  output logic                       s_axis_cc_tready,
  input  logic [AXI_CC_USER_W-1:0]   s_axis_cc_tuser,

  input  logic [AXI_DATA_WIDTH-1:0]  s_axis_rq_tdata,
  input  logic [AXI_KEEP_WIDTH-1:0]  s_axis_rq_tkeep,
  input  logic                       s_axis_rq_tlast,
  input  logic                       s_axis_rq_tvalid,
  output logic                       s_axis_rq_tready,
  input  logic [AXI_RQ_USER_W-1:0]   s_axis_rq_tuser,

  output logic [AXI_DATA_WIDTH-1:0]  m_axis_rc_tdata,
  output logic [AXI_KEEP_WIDTH-1:0]  m_axis_rc_tkeep,
  output logic                       m_axis_rc_tlast,
  output logic                       m_axis_rc_tvalid,
  input  logic                       m_axis_rc_tready,
  output logic [AXI_RC_USER_W-1:0]   m_axis_rc_tuser,

  input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_awaddr,
  input  logic                       s_axil_awvalid,
  output logic                       s_axil_awready,
  input  logic [AXIL_DATA_WIDTH-1:0] s_axil_wdata,
  input  logic [AXIL_DATA_WIDTH/8-1:0] s_axil_wstrb,
  input  logic                       s_axil_wvalid,
  output logic                       s_axil_wready,
  output logic [1:0]                 s_axil_bresp,
  output logic                       s_axil_bvalid,
  input  logic                       s_axil_bready,
  input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_araddr,
  input  logic                       s_axil_arvalid,
  output logic                       s_axil_arready,
  output logic [AXIL_DATA_WIDTH-1:0] s_axil_rdata,
  output logic [1:0]                 s_axil_rresp,
  output logic                       s_axil_rvalid,
  input  logic                       s_axil_rready,

  output logic [LANES-1:0]           pci_exp_txp,
  output logic [LANES-1:0]           pci_exp_txn,
  input  logic [LANES-1:0]           pci_exp_rxp,
  input  logic [LANES-1:0]           pci_exp_rxn,

  output logic                       link_up
);

  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata;
  logic [LANES-1:0]                 pipe_txdatak;
  logic                             pipe_txdetectrx;
  logic                             pipe_txelecidle;
  logic [LANES-1:0]                 pipe_txcompliance;
  logic                             pipe_txdatavalid;
  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata;
  logic [LANES-1:0]                 pipe_rxdatak;
  logic                             pipe_rxvalid;
  logic                             pipe_rxelecidle;
  logic [2:0]                       pipe_rxstatus;
  logic                             pipe_phystatus;
  logic [1:0]                       pipe_powerdown;
  logic [2:0]                       pipe_rate;
  logic                             pipe_rxpolarity;

  rivet_pcie_ctrl #(
    .MODE(MODE),
    .GEN(GEN),
    .LANES(LANES),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_KEEP_WIDTH(AXI_KEEP_WIDTH),
    .AXI_CQ_USER_W(AXI_CQ_USER_W),
    .AXI_CC_USER_W(AXI_CC_USER_W),
    .AXI_RQ_USER_W(AXI_RQ_USER_W),
    .AXI_RC_USER_W(AXI_RC_USER_W),
    .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH)
  ) u_ctrl (
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

  generate
    if (FPGA_FAMILY == 0) begin : g_usplus
      rivet_pcie_phy_usplus #(
        .LANES(LANES),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)
      ) u_phy (
        .pclk(pclk),
        .preset_n(preset_n),
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
        .pci_exp_txp(pci_exp_txp),
        .pci_exp_txn(pci_exp_txn),
        .pci_exp_rxp(pci_exp_rxp),
        .pci_exp_rxn(pci_exp_rxn),
        .sys_clk(sys_clk),
        .sys_reset_n(sys_reset_n)
      );
    end else begin : g_us
      rivet_pcie_phy_us #(
        .LANES(LANES),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)
      ) u_phy (
        .pclk(pclk),
        .preset_n(preset_n),
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
        .pci_exp_txp(pci_exp_txp),
        .pci_exp_txn(pci_exp_txn),
        .pci_exp_rxp(pci_exp_rxp),
        .pci_exp_rxn(pci_exp_rxn),
        .sys_clk(sys_clk),
        .sys_reset_n(sys_reset_n)
      );
    end
  endgenerate

endmodule : rivet_pcie
