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
  logic [2*LANES-1:0]               pipe_txdatak;
  logic [LANES-1:0]                 pipe_txdata_valid;
  logic [LANES-1:0]                 pipe_txstart_block;
  logic [2*LANES-1:0]               pipe_txsync_header;
  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata;
  logic [2*LANES-1:0]               pipe_rxdatak;
  logic [LANES-1:0]                 pipe_rxdata_valid;
  logic [2*LANES-1:0]               pipe_rxstart_block;
  logic [2*LANES-1:0]               pipe_rxsync_header;
  logic                             pipe_txdetectrx;
  logic [LANES-1:0]                 pipe_txelecidle;
  logic [LANES-1:0]                 pipe_txcompliance;
  logic [LANES-1:0]                 pipe_rxpolarity;
  logic [1:0]                       pipe_powerdown;
  logic [2:0]                       pipe_rate;
  logic [LANES-1:0]                 pipe_rxvalid;
  logic [LANES-1:0]                 pipe_phystatus;
  logic [LANES-1:0]                 pipe_phystatus_rst;
  logic [LANES-1:0]                 pipe_rxelecidle;
  logic [3*LANES-1:0]               pipe_rxstatus;
  logic [2:0]                       pipe_txmargin;
  logic                             pipe_txswing;
  logic                             pipe_txdeemph;
  logic [2*LANES-1:0]               pipe_txeq_ctrl;
  logic [4*LANES-1:0]               pipe_txeq_preset;
  logic [6*LANES-1:0]               pipe_txeq_coeff;
  logic [5:0]                       pipe_txeq_fs;
  logic [5:0]                       pipe_txeq_lf;
  logic [18*LANES-1:0]              pipe_txeq_new_coeff;
  logic [LANES-1:0]                 pipe_txeq_done;
  logic [2*LANES-1:0]               pipe_rxeq_ctrl;
  logic [4*LANES-1:0]               pipe_rxeq_txpreset;
  logic [LANES-1:0]                 pipe_rxeq_preset_sel;
  logic [18*LANES-1:0]              pipe_rxeq_new_txcoeff;
  logic [LANES-1:0]                 pipe_rxeq_adapt_done;
  logic [LANES-1:0]                 pipe_rxeq_done;
  logic                             pipe_as_mac_in_detect;
  logic                             pipe_as_cdr_hold_req;
  logic                             pipe_as_mac_in_L0;
  logic [1:0]                       pipe_cfg_rx_pm_state;

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
    .pipe_txdata_valid(pipe_txdata_valid),
    .pipe_txstart_block(pipe_txstart_block),
    .pipe_txsync_header(pipe_txsync_header),
    .pipe_rxdata(pipe_rxdata),
    .pipe_rxdatak(pipe_rxdatak),
    .pipe_rxdata_valid(pipe_rxdata_valid),
    .pipe_rxstart_block(pipe_rxstart_block),
    .pipe_rxsync_header(pipe_rxsync_header),
    .pipe_txdetectrx(pipe_txdetectrx),
    .pipe_txelecidle(pipe_txelecidle),
    .pipe_txcompliance(pipe_txcompliance),
    .pipe_rxpolarity(pipe_rxpolarity),
    .pipe_powerdown(pipe_powerdown),
    .pipe_rate(pipe_rate),
    .pipe_rxvalid(pipe_rxvalid),
    .pipe_phystatus(pipe_phystatus),
    .pipe_phystatus_rst(pipe_phystatus_rst),
    .pipe_rxelecidle(pipe_rxelecidle),
    .pipe_rxstatus(pipe_rxstatus),
    .pipe_txmargin(pipe_txmargin),
    .pipe_txswing(pipe_txswing),
    .pipe_txdeemph(pipe_txdeemph),
    .pipe_txeq_ctrl(pipe_txeq_ctrl),
    .pipe_txeq_preset(pipe_txeq_preset),
    .pipe_txeq_coeff(pipe_txeq_coeff),
    .pipe_txeq_fs(pipe_txeq_fs),
    .pipe_txeq_lf(pipe_txeq_lf),
    .pipe_txeq_new_coeff(pipe_txeq_new_coeff),
    .pipe_txeq_done(pipe_txeq_done),
    .pipe_rxeq_ctrl(pipe_rxeq_ctrl),
    .pipe_rxeq_txpreset(pipe_rxeq_txpreset),
    .pipe_rxeq_preset_sel(pipe_rxeq_preset_sel),
    .pipe_rxeq_new_txcoeff(pipe_rxeq_new_txcoeff),
    .pipe_rxeq_adapt_done(pipe_rxeq_adapt_done),
    .pipe_rxeq_done(pipe_rxeq_done),
    .pipe_as_mac_in_detect(pipe_as_mac_in_detect),
    .pipe_as_cdr_hold_req(pipe_as_cdr_hold_req),
    .pipe_as_mac_in_L0(pipe_as_mac_in_L0),
    .pipe_cfg_rx_pm_state(pipe_cfg_rx_pm_state),
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
        .pipe_txdata_valid(pipe_txdata_valid),
        .pipe_txstart_block(pipe_txstart_block),
        .pipe_txsync_header(pipe_txsync_header),
        .pipe_rxdata(pipe_rxdata),
        .pipe_rxdatak(pipe_rxdatak),
        .pipe_rxdata_valid(pipe_rxdata_valid),
        .pipe_rxstart_block(pipe_rxstart_block),
        .pipe_rxsync_header(pipe_rxsync_header),
        .pipe_txdetectrx(pipe_txdetectrx),
        .pipe_txelecidle(pipe_txelecidle),
        .pipe_txcompliance(pipe_txcompliance),
        .pipe_rxpolarity(pipe_rxpolarity),
        .pipe_powerdown(pipe_powerdown),
        .pipe_rate(pipe_rate),
        .pipe_rxvalid(pipe_rxvalid),
        .pipe_phystatus(pipe_phystatus),
        .pipe_phystatus_rst(pipe_phystatus_rst),
        .pipe_rxelecidle(pipe_rxelecidle),
        .pipe_rxstatus(pipe_rxstatus),
        .pipe_txmargin(pipe_txmargin),
        .pipe_txswing(pipe_txswing),
        .pipe_txdeemph(pipe_txdeemph),
        .pipe_txeq_ctrl(pipe_txeq_ctrl),
        .pipe_txeq_preset(pipe_txeq_preset),
        .pipe_txeq_coeff(pipe_txeq_coeff),
        .pipe_txeq_fs(pipe_txeq_fs),
        .pipe_txeq_lf(pipe_txeq_lf),
        .pipe_txeq_new_coeff(pipe_txeq_new_coeff),
        .pipe_txeq_done(pipe_txeq_done),
        .pipe_rxeq_ctrl(pipe_rxeq_ctrl),
        .pipe_rxeq_txpreset(pipe_rxeq_txpreset),
        .pipe_rxeq_preset_sel(pipe_rxeq_preset_sel),
        .pipe_rxeq_new_txcoeff(pipe_rxeq_new_txcoeff),
        .pipe_rxeq_adapt_done(pipe_rxeq_adapt_done),
        .pipe_rxeq_done(pipe_rxeq_done),
        .pipe_as_mac_in_detect(pipe_as_mac_in_detect),
        .pipe_as_cdr_hold_req(pipe_as_cdr_hold_req),
        .pipe_as_mac_in_L0(pipe_as_mac_in_L0),
        .pipe_cfg_rx_pm_state(pipe_cfg_rx_pm_state),
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
        .pipe_txdata_valid(pipe_txdata_valid),
        .pipe_txstart_block(pipe_txstart_block),
        .pipe_txsync_header(pipe_txsync_header),
        .pipe_rxdata(pipe_rxdata),
        .pipe_rxdatak(pipe_rxdatak),
        .pipe_rxdata_valid(pipe_rxdata_valid),
        .pipe_rxstart_block(pipe_rxstart_block),
        .pipe_rxsync_header(pipe_rxsync_header),
        .pipe_txdetectrx(pipe_txdetectrx),
        .pipe_txelecidle(pipe_txelecidle),
        .pipe_txcompliance(pipe_txcompliance),
        .pipe_rxpolarity(pipe_rxpolarity),
        .pipe_powerdown(pipe_powerdown),
        .pipe_rate(pipe_rate),
        .pipe_rxvalid(pipe_rxvalid),
        .pipe_phystatus(pipe_phystatus),
        .pipe_phystatus_rst(pipe_phystatus_rst),
        .pipe_rxelecidle(pipe_rxelecidle),
        .pipe_rxstatus(pipe_rxstatus),
        .pipe_txmargin(pipe_txmargin),
        .pipe_txswing(pipe_txswing),
        .pipe_txdeemph(pipe_txdeemph),
        .pipe_txeq_ctrl(pipe_txeq_ctrl),
        .pipe_txeq_preset(pipe_txeq_preset),
        .pipe_txeq_coeff(pipe_txeq_coeff),
        .pipe_txeq_fs(pipe_txeq_fs),
        .pipe_txeq_lf(pipe_txeq_lf),
        .pipe_txeq_new_coeff(pipe_txeq_new_coeff),
        .pipe_txeq_done(pipe_txeq_done),
        .pipe_rxeq_ctrl(pipe_rxeq_ctrl),
        .pipe_rxeq_txpreset(pipe_rxeq_txpreset),
        .pipe_rxeq_preset_sel(pipe_rxeq_preset_sel),
        .pipe_rxeq_new_txcoeff(pipe_rxeq_new_txcoeff),
        .pipe_rxeq_adapt_done(pipe_rxeq_adapt_done),
        .pipe_rxeq_done(pipe_rxeq_done),
        .pipe_as_mac_in_detect(pipe_as_mac_in_detect),
        .pipe_as_cdr_hold_req(pipe_as_cdr_hold_req),
        .pipe_as_mac_in_L0(pipe_as_mac_in_L0),
        .pipe_cfg_rx_pm_state(pipe_cfg_rx_pm_state),
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
