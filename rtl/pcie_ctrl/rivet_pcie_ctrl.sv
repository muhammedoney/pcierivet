// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rivet PCIe soft controller — multi-mode (EP / RC / USP / DSP), PIPE boundary.
// User application IF: AXI-ST CQ/CC/RQ/RC + cfg_mgmt (PG213-style). No AXI-Lite.
// Integrates MAC (pclk); TL/DLL stubs remain at this top until layered.

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
  // Simulation knobs forwarded to the LTSSM (see rivet_mac).
  parameter int unsigned LTSSM_TIMER_SCALE = 1,
  parameter int unsigned N_TS1_POLLING     = rivet_pkg::RIVET_N_TS1_POLLING
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

  // Configuration Management (PG213 Table 26)
  input  logic [9:0]                 cfg_mgmt_addr,
  input  logic [7:0]                 cfg_mgmt_function_number,
  input  logic                       cfg_mgmt_write,
  input  logic [31:0]                cfg_mgmt_write_data,
  input  logic [3:0]                 cfg_mgmt_byte_enable,
  input  logic                       cfg_mgmt_read,
  output logic [31:0]                cfg_mgmt_read_data,
  output logic                       cfg_mgmt_read_write_done,
  input  logic                       cfg_mgmt_debug_access,

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

  // Link status (PG213-style)
  output logic [5:0] cfg_ltssm_state,
  output logic       link_up
);

  import rivet_pkg::*;

`ifndef SYNTHESIS
  initial begin
    if (!(MODE == RIVET_MODE_EP || MODE == RIVET_MODE_RC ||
          MODE == RIVET_MODE_USP || MODE == RIVET_MODE_DSP))
      $error("rivet_pcie_ctrl: MODE must be EP/RC/USP/DSP (got %0d)", MODE);
    if (GEN != 2)
      $error("rivet_pcie_ctrl Phase 1 supports GEN=2 only");
    if (!(LANES == 1 || LANES == 2 || LANES == 4))
      $error("rivet_pcie_ctrl LANES must be 1, 2, or 4");
  end
`endif

  // -------------------------------------------------------------------------
  // User / TL stubs (user_clk) — CDC to pclk later
  // -------------------------------------------------------------------------
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

  assign cfg_mgmt_read_data       = '0;
  assign cfg_mgmt_read_write_done = cfg_mgmt_read || cfg_mgmt_write;

  // -------------------------------------------------------------------------
  // DLL stubs on pclk (no traffic yet)
  // -------------------------------------------------------------------------
  rivet_dll_mac_tx_beat_t dll_tx_beat;
  logic                   dll_tx_valid;
  logic                   dll_tx_ready;
  rivet_dll_mac_rx_beat_t dll_rx_beat;
  logic                   dll_rx_valid;
  logic                   dll_rx_ready;
  rivet_mac_dll_sb_t      mac_to_dll_sb;
  rivet_dll_mac_sb_t      dll_to_mac_sb;
  rivet_ltssm_state_e     ltssm_state;

  assign dll_tx_beat    = '0;
  assign dll_tx_valid   = 1'b0;
  assign dll_rx_ready   = 1'b1;
  assign dll_to_mac_sb  = '0;

  rivet_mac #(
    .MODE              (MODE),
    .GEN               (GEN),
    .LANES             (LANES),
    .PIPE_DATA_WIDTH   (PIPE_DATA_WIDTH),
    .LTSSM_TIMER_SCALE (LTSSM_TIMER_SCALE),
    .N_TS1_POLLING     (N_TS1_POLLING)
  ) u_mac (
    .pclk_i                  (pclk),
    .rst_ni                  (preset_n),
    .dll_tx_beat_i           (dll_tx_beat),
    .dll_tx_valid_i          (dll_tx_valid),
    .dll_tx_ready_o          (dll_tx_ready),
    .dll_rx_beat_o           (dll_rx_beat),
    .dll_rx_valid_o          (dll_rx_valid),
    .dll_rx_ready_i          (dll_rx_ready),
    .mac_to_dll_sb_o         (mac_to_dll_sb),
    .dll_to_mac_sb_i         (dll_to_mac_sb),
    .ltssm_state_o           (ltssm_state),
    .link_up_o               (link_up),
    .pipe_txdata_o           (pipe_txdata),
    .pipe_txdatak_o          (pipe_txdatak),
    .pipe_txdata_valid_o     (pipe_txdata_valid),
    .pipe_txstart_block_o    (pipe_txstart_block),
    .pipe_txsync_header_o    (pipe_txsync_header),
    .pipe_rxdata_i           (pipe_rxdata),
    .pipe_rxdatak_i          (pipe_rxdatak),
    .pipe_rxdata_valid_i     (pipe_rxdata_valid),
    .pipe_rxstart_block_i    (pipe_rxstart_block),
    .pipe_rxsync_header_i    (pipe_rxsync_header),
    .pipe_txdetectrx_o       (pipe_txdetectrx),
    .pipe_txelecidle_o       (pipe_txelecidle),
    .pipe_txcompliance_o     (pipe_txcompliance),
    .pipe_rxpolarity_o       (pipe_rxpolarity),
    .pipe_powerdown_o        (pipe_powerdown),
    .pipe_rate_o             (pipe_rate),
    .pipe_rxvalid_i          (pipe_rxvalid),
    .pipe_phystatus_i        (pipe_phystatus),
    .pipe_phystatus_rst_i    (pipe_phystatus_rst),
    .pipe_rxelecidle_i       (pipe_rxelecidle),
    .pipe_rxstatus_i         (pipe_rxstatus),
    .pipe_txmargin_o         (pipe_txmargin),
    .pipe_txswing_o          (pipe_txswing),
    .pipe_txdeemph_o         (pipe_txdeemph),
    .pipe_txeq_ctrl_o        (pipe_txeq_ctrl),
    .pipe_txeq_preset_o      (pipe_txeq_preset),
    .pipe_txeq_coeff_o       (pipe_txeq_coeff),
    .pipe_txeq_fs_i          (pipe_txeq_fs),
    .pipe_txeq_lf_i          (pipe_txeq_lf),
    .pipe_txeq_new_coeff_i   (pipe_txeq_new_coeff),
    .pipe_txeq_done_i        (pipe_txeq_done),
    .pipe_rxeq_ctrl_o        (pipe_rxeq_ctrl),
    .pipe_rxeq_txpreset_o    (pipe_rxeq_txpreset),
    .pipe_rxeq_preset_sel_i  (pipe_rxeq_preset_sel),
    .pipe_rxeq_new_txcoeff_i (pipe_rxeq_new_txcoeff),
    .pipe_rxeq_adapt_done_i  (pipe_rxeq_adapt_done),
    .pipe_rxeq_done_i        (pipe_rxeq_done),
    .pipe_as_mac_in_detect_o (pipe_as_mac_in_detect),
    .pipe_as_cdr_hold_req_o  (pipe_as_cdr_hold_req),
    .pipe_as_mac_in_L0_o     (pipe_as_mac_in_L0),
    .pipe_cfg_rx_pm_state_o  (pipe_cfg_rx_pm_state)
  );

  assign cfg_ltssm_state = ltssm_state;

  logic _unused_user;
  assign _unused_user = user_clk ^ user_resetn ^ (|pcie_cq_np_req) ^
                        (|cfg_mgmt_addr) ^ (|cfg_mgmt_function_number) ^
                        (|cfg_mgmt_write_data) ^ (|cfg_mgmt_byte_enable) ^
                        cfg_mgmt_debug_access ^ dll_tx_ready ^ dll_rx_valid ^
                        (|mac_to_dll_sb) ^
                        m_axis_cq_tready ^ m_axis_rc_tready ^
                        s_axis_cc_tvalid ^ s_axis_rq_tvalid ^
                        (|s_axis_cc_tdata) ^ (|s_axis_rq_tdata);

endmodule : rivet_pcie_ctrl
