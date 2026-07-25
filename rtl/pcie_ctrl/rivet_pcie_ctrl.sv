// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rivet PCIe soft controller — multi-mode (EP / RC / USP / DSP), PIPE boundary.
// User application IF: AXI-ST CQ/CC/RQ/RC (PG213-style) + AXI-Lite.
// Phase 0: synthesizable stub; development focus MODE=EP, GEN=2.

module rivet_pcie_ctrl #(
  parameter int unsigned MODE            = 0,  // rivet_pkg::RIVET_MODE_EP
  parameter int unsigned GEN             = 2,
  parameter int unsigned LANES           = 1,
  parameter int unsigned AXI_DATA_WIDTH  = 64,
  parameter int unsigned AXI_KEEP_WIDTH  = AXI_DATA_WIDTH / 32,
  parameter int unsigned AXI_CQ_USER_W   = 88,
  parameter int unsigned AXI_CC_USER_W   = 33,
  parameter int unsigned AXI_RQ_USER_W   = 85,
  parameter int unsigned AXI_RC_USER_W   = 75,
  parameter int unsigned PIPE_DATA_WIDTH = 16,
  parameter int unsigned AXIL_ADDR_WIDTH = 32,
  parameter int unsigned AXIL_DATA_WIDTH = 32
) (
  input  logic user_clk,
  input  logic user_resetn,
  input  logic pclk,
  input  logic preset_n,

  // AXI-ST CQ (Completer Request): controller -> user
  output logic [AXI_DATA_WIDTH-1:0]  m_axis_cq_tdata,
  output logic [AXI_KEEP_WIDTH-1:0]  m_axis_cq_tkeep,
  output logic                       m_axis_cq_tlast,
  output logic                       m_axis_cq_tvalid,
  input  logic                       m_axis_cq_tready,
  output logic [AXI_CQ_USER_W-1:0]   m_axis_cq_tuser,

  // AXI-ST CC (Completer Completion): user -> controller
  input  logic [AXI_DATA_WIDTH-1:0]  s_axis_cc_tdata,
  input  logic [AXI_KEEP_WIDTH-1:0]  s_axis_cc_tkeep,
  input  logic                       s_axis_cc_tlast,
  input  logic                       s_axis_cc_tvalid,
  output logic [3:0]                 s_axis_cc_tready,
  input  logic [AXI_CC_USER_W-1:0]   s_axis_cc_tuser,

  // AXI-ST RQ (Requester Request): user -> controller
  input  logic [AXI_DATA_WIDTH-1:0]  s_axis_rq_tdata,
  input  logic [AXI_KEEP_WIDTH-1:0]  s_axis_rq_tkeep,
  input  logic                       s_axis_rq_tlast,
  input  logic                       s_axis_rq_tvalid,
  output logic [3:0]                 s_axis_rq_tready,
  input  logic [AXI_RQ_USER_W-1:0]   s_axis_rq_tuser,

  // AXI-ST RC (Requester Completion): controller -> user
  output logic [AXI_DATA_WIDTH-1:0]  m_axis_rc_tdata,
  output logic [AXI_KEEP_WIDTH-1:0]  m_axis_rc_tkeep,
  output logic                       m_axis_rc_tlast,
  output logic                       m_axis_rc_tvalid,
  input  logic                       m_axis_rc_tready,
  output logic [AXI_RC_USER_W-1:0]   m_axis_rc_tuser,

  // PG213 companion flow-control / tracking ports (single request per cycle)
  input  logic [1:0]                 pcie_cq_np_req,
  output logic [5:0]                 pcie_cq_np_req_count,
  output logic [5:0]                 pcie_rq_seq_num0,
  output logic                       pcie_rq_seq_num_vld0,
  output logic [9:0]                 pcie_rq_tag0,
  output logic                       pcie_rq_tag_vld0,
  output logic [9:0]                 pcie_rq_tag1,
  output logic                       pcie_rq_tag_vld1,
  output logic [3:0]                 pcie_rq_tag_av,
  output logic [3:0]                 pcie_tfc_nph_av,
  output logic [3:0]                 pcie_tfc_npd_av,

  // AXI-Lite config (CSR Phase 1+)
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

  // PIPE (controller / MAC view) — PG239-aligned; see rivet_pipe_if
  output logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata,
  output logic [2*LANES-1:0]               pipe_txdatak,
  output logic [LANES-1:0]                 pipe_txdata_valid,
  output logic [LANES-1:0]                 pipe_txstart_block,
  output logic [2*LANES-1:0]               pipe_txsync_header,
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata,
  input  logic [2*LANES-1:0]               pipe_rxdatak,
  input  logic [LANES-1:0]                 pipe_rxdata_valid,
  input  logic [2*LANES-1:0]               pipe_rxstart_block,
  input  logic [2*LANES-1:0]               pipe_rxsync_header,
  output logic                             pipe_txdetectrx,
  output logic [LANES-1:0]                 pipe_txelecidle,
  output logic [LANES-1:0]                 pipe_txcompliance,
  output logic [LANES-1:0]                 pipe_rxpolarity,
  output logic [1:0]                       pipe_powerdown,
  output logic [2:0]                       pipe_rate,
  input  logic [LANES-1:0]                 pipe_rxvalid,
  input  logic [LANES-1:0]                 pipe_phystatus,
  input  logic [LANES-1:0]                 pipe_phystatus_rst,
  input  logic [LANES-1:0]                 pipe_rxelecidle,
  input  logic [3*LANES-1:0]               pipe_rxstatus,
  output logic [2:0]                       pipe_txmargin,
  output logic                             pipe_txswing,
  output logic                             pipe_txdeemph,
  output logic [2*LANES-1:0]               pipe_txeq_ctrl,
  output logic [4*LANES-1:0]               pipe_txeq_preset,
  output logic [6*LANES-1:0]               pipe_txeq_coeff,
  input  logic [5:0]                       pipe_txeq_fs,
  input  logic [5:0]                       pipe_txeq_lf,
  input  logic [18*LANES-1:0]              pipe_txeq_new_coeff,
  input  logic [LANES-1:0]                 pipe_txeq_done,
  output logic [2*LANES-1:0]               pipe_rxeq_ctrl,
  output logic [4*LANES-1:0]               pipe_rxeq_txpreset,
  input  logic [LANES-1:0]                 pipe_rxeq_preset_sel,
  input  logic [18*LANES-1:0]              pipe_rxeq_new_txcoeff,
  input  logic [LANES-1:0]                 pipe_rxeq_adapt_done,
  input  logic [LANES-1:0]                 pipe_rxeq_done,
  output logic                             pipe_as_mac_in_detect,
  output logic                             pipe_as_cdr_hold_req,
  output logic                             pipe_as_mac_in_L0,
  output logic [1:0]                       pipe_cfg_rx_pm_state,

  output logic link_up
);

`ifndef SYNTHESIS
  initial begin
    if (MODE != 0)
      $error("rivet_pcie_ctrl Phase 0 stub only exercises MODE=EP (0)");
    if (GEN != 2)
      $error("rivet_pcie_ctrl Phase 0 supports GEN=2 only");
    if (!(LANES == 1 || LANES == 2 || LANES == 4))
      $error("rivet_pcie_ctrl LANES must be 1, 2, or 4");
  end
`endif

  assign m_axis_cq_tdata  = '0;
  assign m_axis_cq_tkeep  = '0;
  assign m_axis_cq_tlast  = 1'b0;
  assign m_axis_cq_tvalid = 1'b0;
  assign m_axis_cq_tuser  = '0;

  assign m_axis_rc_tdata  = '0;
  assign m_axis_rc_tkeep  = '0;
  assign m_axis_rc_tlast  = 1'b0;
  assign m_axis_rc_tvalid = 1'b0;
  assign m_axis_rc_tuser  = '0;

  assign s_axis_cc_tready = '1;
  assign s_axis_rq_tready = '1;

  assign pcie_cq_np_req_count = '0;
  assign pcie_rq_seq_num0     = '0;
  assign pcie_rq_seq_num_vld0 = 1'b0;
  assign pcie_rq_tag0         = '0;
  assign pcie_rq_tag_vld0     = 1'b0;
  assign pcie_rq_tag1         = '0;
  assign pcie_rq_tag_vld1     = 1'b0;
  assign pcie_rq_tag_av       = '0;
  assign pcie_tfc_nph_av      = '0;
  assign pcie_tfc_npd_av      = '0;

  assign s_axil_awready = 1'b1;
  assign s_axil_wready  = 1'b1;
  assign s_axil_bresp   = 2'b00;
  assign s_axil_bvalid  = s_axil_awvalid && s_axil_wvalid;
  assign s_axil_arready = 1'b1;
  assign s_axil_rdata   = '0;
  assign s_axil_rresp   = 2'b00;
  assign s_axil_rvalid  = s_axil_arvalid;

  assign pipe_txdata            = '0;
  assign pipe_txdatak           = '0;
  assign pipe_txdata_valid      = '0;
  assign pipe_txstart_block     = '0;
  assign pipe_txsync_header     = '0;
  assign pipe_txdetectrx        = 1'b0;
  assign pipe_txelecidle        = '1;
  assign pipe_txcompliance      = '0;
  assign pipe_rxpolarity        = '0;
  assign pipe_powerdown         = 2'b10; // P1 idle stub
  assign pipe_rate              = 3'd1;  // Gen2
  assign pipe_txmargin          = 3'b000;
  assign pipe_txswing           = 1'b0;
  assign pipe_txdeemph          = 1'b1;  // -3.5 dB default (PG239)
  assign pipe_txeq_ctrl         = '0;
  assign pipe_txeq_preset       = '0;
  assign pipe_txeq_coeff        = '0;
  assign pipe_rxeq_ctrl         = '0;
  assign pipe_rxeq_txpreset     = '0;
  assign pipe_as_mac_in_detect  = 1'b1;  // Detect.* until LTSSM exists
  assign pipe_as_cdr_hold_req   = 1'b0;
  assign pipe_as_mac_in_L0      = 1'b0;
  assign pipe_cfg_rx_pm_state   = 2'b00;

  assign link_up = 1'b0;

  wire _unused_user = ^pcie_cq_np_req;

endmodule : rivet_pcie_ctrl
