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

  // PG213 Configuration Flow Control (Table 32)
  output logic [7:0]                 cfg_fc_ph,
  output logic [11:0]                cfg_fc_pd,
  output logic [7:0]                 cfg_fc_nph,
  output logic [11:0]                cfg_fc_npd,
  output logic [7:0]                 cfg_fc_cplh,
  output logic [11:0]                cfg_fc_cpld,
  input  logic [2:0]                 cfg_fc_sel,

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

  // Interrupts (PG213 MSI / MSI-X subset)
  input  logic [31:0]                cfg_interrupt_msi_int,
  output logic                       cfg_interrupt_msi_enable,
  output logic                       cfg_interrupt_msi_sent,
  output logic                       cfg_interrupt_msi_fail,
  input  logic [63:0]                cfg_interrupt_msix_address,
  input  logic [31:0]                cfg_interrupt_msix_data,
  input  logic                       cfg_interrupt_msix_int,
  output logic                       cfg_interrupt_msix_enable,
  output logic                       cfg_interrupt_msix_sent,
  output logic                       cfg_interrupt_msix_fail,

  // AER / advisory (PG213 subset)
  input  logic                       cfg_err_cor_in,
  input  logic                       cfg_err_uncor_in,
  output logic                       cfg_err_cor_out,
  output logic                       cfg_err_nonfatal_out,
  output logic                       cfg_err_fatal_out,

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
    if (!(GEN == 1 || GEN == 2))
      $error("rivet_pcie_ctrl Phase 1 supports GEN=1 or 2 only (got %0d)", GEN);
    if (!(LANES == 1 || LANES == 2 || LANES == 4))
      $error("rivet_pcie_ctrl LANES must be 1, 2, or 4");
  end
`endif

  // -------------------------------------------------------------------------
  // CDC resets (async assert both domains; sync deassert per clk)
  // -------------------------------------------------------------------------
  logic rst_n_por;
  logic user_rst_sync_n, pclk_rst_sync_n;
  logic user_rst_init_n, pclk_rst_init_n;

  assign rst_n_por = user_resetn & preset_n;

  cc_rstgen u_rst_user (
    .clk_i       (user_clk),
    .rst_ni      (rst_n_por),
    .test_mode_i (1'b0),
    .rst_no      (user_rst_sync_n),
    .init_no     (user_rst_init_n)
  );
  cc_rstgen u_rst_pclk (
    .clk_i       (pclk),
    .rst_ni      (rst_n_por),
    .test_mode_i (1'b0),
    .rst_no      (pclk_rst_sync_n),
    .init_no     (pclk_rst_init_n)
  );

  // -------------------------------------------------------------------------
  // DLL + TL (pclk); user AXI-ST / cfg_mgmt via CDC
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
  rivet_tl_dll_fc_sb_t    tl_to_dll_fc;
  rivet_dll_tl_fc_sb_t    dll_to_tl_fc;

  logic        cr_rx_acc, cr_tx_acc;
  logic [7:0]  cr_rx_h0, cr_tx_h0;
  logic [9:0]  cr_rx_len, cr_tx_len;
  logic        cr_rx_acc_cfg, cr_rx_acc_cq, cr_rx_acc_rc;
  logic [7:0]  cr_rx_h0_cfg, cr_rx_h0_cq, cr_rx_h0_rc;
  logic [9:0]  cr_rx_len_cfg, cr_rx_len_cq, cr_rx_len_rc;
  logic        cr_tx_acc_cfg, cr_tx_acc_cc, cr_tx_acc_rq, cr_tx_acc_msi;
  logic [7:0]  cr_tx_h0_cfg, cr_tx_h0_cc, cr_tx_h0_rq, cr_tx_h0_msi;
  logic [9:0]  cr_tx_len_cfg, cr_tx_len_cc, cr_tx_len_rq, cr_tx_len_msi;
  logic        cr_free_ph, cr_free_pd, cr_free_nph, cr_free_npd, cr_free_cplh, cr_free_cpld;
  logic [7:0]  cr_free_ph_a, cr_free_nph_a, cr_free_cplh_a;
  logic [11:0] cr_free_pd_a, cr_free_npd_a, cr_free_cpld_a;
  logic        cr_cons_ph, cr_cons_pd, cr_cons_nph, cr_cons_npd, cr_cons_cplh, cr_cons_cpld;
  logic [7:0]  cr_cons_ph_a, cr_cons_nph_a, cr_cons_cplh_a;
  logic [11:0] cr_cons_pd_a, cr_cons_npd_a, cr_cons_cpld_a;

  logic [63:0] tl_rx_tdata, tl_tx_tdata;
  logic [7:0]  tl_rx_tkeep, tl_tx_tkeep;
  logic        tl_rx_tlast, tl_tx_tlast;
  logic        tl_rx_tvalid, tl_tx_tvalid;
  logic        tl_rx_tready, tl_tx_tready;

  logic [63:0] cfg_rx_d, cq_rx_d, rc_rx_d, cfg_tx_d, cc_tx_d, rq_tx_d, msi_tx_d;
  logic [7:0]  cfg_rx_k, cq_rx_k, rc_rx_k, cfg_tx_k, cc_tx_k, rq_tx_k, msi_tx_k;
  logic        cfg_rx_l, cq_rx_l, rc_rx_l, cfg_tx_l, cc_tx_l, rq_tx_l, msi_tx_l;
  logic        cfg_rx_v, cq_rx_v, rc_rx_v, cfg_tx_v, cc_tx_v, rq_tx_v, msi_tx_v;
  logic        cfg_rx_r, cq_rx_r, rc_rx_r, cfg_tx_r, cc_tx_r, rq_tx_r, msi_tx_r;

  logic        msi_enable_p, msix_enable_p;
  logic [31:0] msi_addr_p;
  logic [15:0] msi_data_p;
  logic [31:0] msi_int_p;
  logic [63:0] msix_addr_p;
  logic [31:0] msix_data_p;
  logic        msix_int_p;
  logic        msi_sent_p, msi_fail_p, msix_sent_p, msix_fail_p;
  logic        err_cor_p, err_uncor_p;
  logic        aer_set_cor, aer_set_nf;
  logic [5:0]  rq_seq_p;
  logic        rq_seq_vld_p, rq_tag_vld_p;
  logic [9:0]  rq_tag_p;
  logic [3:0]  rq_tag_av_p;
  logic        rq_tag_free_p;

  logic        fab_req, fab_write, fab_ack, fab_busy;
  logic [9:0]  fab_addr;
  logic [3:0]  fab_be;
  logic [31:0] fab_wdata, fab_rdata;
  logic [31:0] bar0_base, bar0_mask;
  logic        bar0_mem_en, bus_master_en;

  // Credit OR of Cfg + CQ/CC + RC/RQ paths
  assign cr_rx_acc = cr_rx_acc_cfg | cr_rx_acc_cq | cr_rx_acc_rc;
  assign cr_rx_h0  = cr_rx_acc_cfg ? cr_rx_h0_cfg :
                     (cr_rx_acc_cq ? cr_rx_h0_cq : cr_rx_h0_rc);
  assign cr_rx_len = cr_rx_acc_cfg ? cr_rx_len_cfg :
                     (cr_rx_acc_cq ? cr_rx_len_cq : cr_rx_len_rc);
  assign cr_tx_acc = cr_tx_acc_cfg | cr_tx_acc_cc | cr_tx_acc_rq | cr_tx_acc_msi;
  assign cr_tx_h0  = cr_tx_acc_cfg ? cr_tx_h0_cfg :
                     (cr_tx_acc_msi ? cr_tx_h0_msi :
                     (cr_tx_acc_cc ? cr_tx_h0_cc : cr_tx_h0_rq));
  assign cr_tx_len = cr_tx_acc_cfg ? cr_tx_len_cfg :
                     (cr_tx_acc_msi ? cr_tx_len_msi :
                     (cr_tx_acc_cc ? cr_tx_len_cc : cr_tx_len_rq));

  logic [9:0]  mgmt_p_addr;
  logic [7:0]  mgmt_p_fn;
  logic        mgmt_p_write, mgmt_p_read, mgmt_p_done;
  logic [31:0] mgmt_p_wdata, mgmt_p_rdata;
  logic [3:0]  mgmt_p_be;
  logic        mgmt_p_debug;

  rivet_cdc_cfg_mgmt u_cdc_cfg_mgmt (
    .user_clk_i                   (user_clk),
    .user_rst_ni                  (user_rst_sync_n),
    .pclk_i                       (pclk),
    .preset_ni                    (pclk_rst_sync_n),
    .cfg_mgmt_addr_i              (cfg_mgmt_addr),
    .cfg_mgmt_function_number_i   (cfg_mgmt_function_number),
    .cfg_mgmt_write_i             (cfg_mgmt_write),
    .cfg_mgmt_write_data_i        (cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable_i       (cfg_mgmt_byte_enable),
    .cfg_mgmt_read_i              (cfg_mgmt_read),
    .cfg_mgmt_read_data_o         (cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done_o   (cfg_mgmt_read_write_done),
    .cfg_mgmt_debug_access_i      (cfg_mgmt_debug_access),
    .space_addr_o                 (mgmt_p_addr),
    .space_function_number_o      (mgmt_p_fn),
    .space_write_o                (mgmt_p_write),
    .space_write_data_o           (mgmt_p_wdata),
    .space_byte_enable_o          (mgmt_p_be),
    .space_read_o                 (mgmt_p_read),
    .space_read_data_i            (mgmt_p_rdata),
    .space_read_write_done_i      (mgmt_p_done),
    .space_debug_access_o         (mgmt_p_debug)
  );

  rivet_tl_cfg_space u_cfg_space (
    .clk_i                        (pclk),
    .rst_ni                       (pclk_rst_sync_n),
    .fab_req_i                    (fab_req),
    .fab_write_i                  (fab_write),
    .fab_addr_i                   (fab_addr),
    .fab_be_i                     (fab_be),
    .fab_wdata_i                  (fab_wdata),
    .fab_rdata_o                  (fab_rdata),
    .fab_ack_o                    (fab_ack),
    .fab_busy_o                   (fab_busy),
    .cfg_mgmt_addr_i              (mgmt_p_addr),
    .cfg_mgmt_function_number_i   (mgmt_p_fn),
    .cfg_mgmt_write_i             (mgmt_p_write),
    .cfg_mgmt_write_data_i        (mgmt_p_wdata),
    .cfg_mgmt_byte_enable_i       (mgmt_p_be),
    .cfg_mgmt_read_i              (mgmt_p_read),
    .cfg_mgmt_read_data_o         (mgmt_p_rdata),
    .cfg_mgmt_read_write_done_o   (mgmt_p_done),
    .cfg_mgmt_debug_access_i      (mgmt_p_debug),
    .bar0_base_o                  (bar0_base),
    .bar0_mask_o                  (bar0_mask),
    .bar0_mem_en_o                (bar0_mem_en),
    .bus_master_en_o              (bus_master_en),
    .msi_enable_o                 (msi_enable_p),
    .msi_addr_o                   (msi_addr_p),
    .msi_data_o                   (msi_data_p),
    .aer_set_cor_i                (aer_set_cor),
    .aer_set_nonfatal_i           (aer_set_nf),
    .link_up_i                    (link_up),
    .link_speed_i                 (4'h1),
    .link_width_i                 (6'(LANES))
  );

  rivet_tl_rx_route u_rx_route (
    .clk_i       (pclk),
    .rst_ni      (preset_n),
    .s_tdata_i   (tl_rx_tdata),
    .s_tkeep_i   (tl_rx_tkeep),
    .s_tlast_i   (tl_rx_tlast),
    .s_tvalid_i  (tl_rx_tvalid),
    .s_tready_o  (tl_rx_tready),
    .cfg_tdata_o (cfg_rx_d),
    .cfg_tkeep_o (cfg_rx_k),
    .cfg_tlast_o (cfg_rx_l),
    .cfg_tvalid_o(cfg_rx_v),
    .cfg_tready_i(cfg_rx_r),
    .cq_tdata_o  (cq_rx_d),
    .cq_tkeep_o  (cq_rx_k),
    .cq_tlast_o  (cq_rx_l),
    .cq_tvalid_o (cq_rx_v),
    .cq_tready_i (cq_rx_r),
    .rc_tdata_o  (rc_rx_d),
    .rc_tkeep_o  (rc_rx_k),
    .rc_tlast_o  (rc_rx_l),
    .rc_tvalid_o (rc_rx_v),
    .rc_tready_i (rc_rx_r)
  );

  rivet_tl_cfg u_tl_cfg (
    .clk_i        (pclk),
    .rst_ni       (preset_n),
    .rx_tdata_i   (cfg_rx_d),
    .rx_tkeep_i   (cfg_rx_k),
    .rx_tlast_i   (cfg_rx_l),
    .rx_tvalid_i  (cfg_rx_v),
    .rx_tready_o  (cfg_rx_r),
    .tx_tdata_o   (cfg_tx_d),
    .tx_tkeep_o   (cfg_tx_k),
    .tx_tlast_o   (cfg_tx_l),
    .tx_tvalid_o  (cfg_tx_v),
    .tx_tready_i  (cfg_tx_r),
    .fab_req_o    (fab_req),
    .fab_write_o  (fab_write),
    .fab_addr_o   (fab_addr),
    .fab_be_o     (fab_be),
    .fab_wdata_o  (fab_wdata),
    .fab_rdata_i  (fab_rdata),
    .fab_ack_i    (fab_ack),
    .fab_busy_i   (fab_busy),
    .rx_accept_o  (cr_rx_acc_cfg),
    .rx_hdr0_o    (cr_rx_h0_cfg),
    .rx_len_dw_o  (cr_rx_len_cfg),
    .tx_accept_o  (cr_tx_acc_cfg),
    .tx_hdr0_o    (cr_tx_h0_cfg),
    .tx_len_dw_o  (cr_tx_len_cfg)
  );

  logic [AXI_DATA_WIDTH-1:0] cq_p_tdata, cq_u_tdata;
  logic [AXI_KEEP_WIDTH-1:0] cq_p_tkeep, cq_u_tkeep;
  logic                      cq_p_tlast, cq_p_tvalid, cq_p_tready;
  logic                      cq_u_tlast, cq_u_tvalid;
  logic [AXI_CQ_USER_W-1:0]  cq_p_tuser, cq_u_tuser;
  logic [1:0]                cq_np_req_p;
  logic [5:0]                cq_np_cnt_p;

  rivet_cdc_sync_bus #(.WIDTH(2)) u_sync_np_req (
    .dst_clk_i  (pclk),
    .dst_rst_ni (pclk_rst_sync_n),
    .src_i      (pcie_cq_np_req),
    .dst_o      (cq_np_req_p)
  );
  rivet_cdc_sync_bus #(.WIDTH(6)) u_sync_np_cnt (
    .dst_clk_i  (user_clk),
    .dst_rst_ni (user_rst_sync_n),
    .src_i      (cq_np_cnt_p),
    .dst_o      (pcie_cq_np_req_count)
  );

  rivet_tl_cq u_tl_cq (
    .clk_i              (pclk),
    .rst_ni             (pclk_rst_sync_n),
    .rx_tdata_i         (cq_rx_d),
    .rx_tkeep_i         (cq_rx_k),
    .rx_tlast_i         (cq_rx_l),
    .rx_tvalid_i        (cq_rx_v),
    .rx_tready_o        (cq_rx_r),
    .bar0_base_i        (bar0_base),
    .bar0_mask_i        (bar0_mask),
    .bar0_mem_en_i      (bar0_mem_en),
    .cq_np_req_i        (cq_np_req_p),
    .cq_np_req_count_o  (cq_np_cnt_p),
    .m_axis_cq_tdata    (cq_p_tdata),
    .m_axis_cq_tkeep    (cq_p_tkeep),
    .m_axis_cq_tlast    (cq_p_tlast),
    .m_axis_cq_tvalid   (cq_p_tvalid),
    .m_axis_cq_tready   (cq_p_tready),
    .m_axis_cq_tuser    (cq_p_tuser),
    .rx_accept_o        (cr_rx_acc_cq),
    .rx_hdr0_o          (cr_rx_h0_cq),
    .rx_len_dw_o        (cr_rx_len_cq)
  );

  rivet_cdc_axis #(
    .DATA_W (AXI_DATA_WIDTH),
    .KEEP_W (AXI_KEEP_WIDTH),
    .USER_W (AXI_CQ_USER_W),
    .DEPTH  (32)
  ) u_cdc_cq (
    .s_clk_i    (pclk),
    .s_rst_ni   (pclk_rst_sync_n),
    .s_tdata_i  (cq_p_tdata),
    .s_tkeep_i  (cq_p_tkeep),
    .s_tlast_i  (cq_p_tlast),
    .s_tvalid_i (cq_p_tvalid),
    .s_tready_o (cq_p_tready),
    .s_tuser_i  (cq_p_tuser),
    .m_clk_i    (user_clk),
    .m_rst_ni   (user_rst_sync_n),
    .m_tdata_o  (cq_u_tdata),
    .m_tkeep_o  (cq_u_tkeep),
    .m_tlast_o  (cq_u_tlast),
    .m_tvalid_o (cq_u_tvalid),
    .m_tready_i (m_axis_cq_tready),
    .m_tuser_o  (cq_u_tuser)
  );

  assign m_axis_cq_tdata  = cq_u_tdata;
  assign m_axis_cq_tkeep  = cq_u_tkeep;
  assign m_axis_cq_tlast  = cq_u_tlast;
  assign m_axis_cq_tvalid = cq_u_tvalid;
  assign m_axis_cq_tuser  = cq_u_tuser;

  logic [AXI_DATA_WIDTH-1:0] cc_u_tdata, cc_p_tdata;
  logic [AXI_KEEP_WIDTH-1:0] cc_u_tkeep, cc_p_tkeep;
  logic                      cc_u_tlast, cc_u_tvalid, cc_u_tready;
  logic                      cc_p_tlast, cc_p_tvalid, cc_p_tready;
  logic [AXI_CC_USER_W-1:0]  cc_u_tuser, cc_p_tuser;

  assign cc_u_tdata  = s_axis_cc_tdata;
  assign cc_u_tkeep  = s_axis_cc_tkeep;
  assign cc_u_tlast  = s_axis_cc_tlast;
  assign cc_u_tvalid = s_axis_cc_tvalid;
  assign cc_u_tuser  = s_axis_cc_tuser;
  assign s_axis_cc_tready = {4{cc_u_tready}};

  rivet_cdc_axis #(
    .DATA_W (AXI_DATA_WIDTH),
    .KEEP_W (AXI_KEEP_WIDTH),
    .USER_W (AXI_CC_USER_W),
    .DEPTH  (32)
  ) u_cdc_cc (
    .s_clk_i    (user_clk),
    .s_rst_ni   (user_rst_sync_n),
    .s_tdata_i  (cc_u_tdata),
    .s_tkeep_i  (cc_u_tkeep),
    .s_tlast_i  (cc_u_tlast),
    .s_tvalid_i (cc_u_tvalid),
    .s_tready_o (cc_u_tready),
    .s_tuser_i  (cc_u_tuser),
    .m_clk_i    (pclk),
    .m_rst_ni   (pclk_rst_sync_n),
    .m_tdata_o  (cc_p_tdata),
    .m_tkeep_o  (cc_p_tkeep),
    .m_tlast_o  (cc_p_tlast),
    .m_tvalid_o (cc_p_tvalid),
    .m_tready_i (cc_p_tready),
    .m_tuser_o  (cc_p_tuser)
  );

  rivet_tl_cc u_tl_cc (
    .clk_i            (pclk),
    .rst_ni           (pclk_rst_sync_n),
    .s_axis_cc_tdata  (cc_p_tdata),
    .s_axis_cc_tkeep  (cc_p_tkeep[1:0]),
    .s_axis_cc_tlast  (cc_p_tlast),
    .s_axis_cc_tvalid (cc_p_tvalid),
    .s_axis_cc_tready (cc_p_tready),
    .s_axis_cc_tuser  (cc_p_tuser),
    .tx_tdata_o       (cc_tx_d),
    .tx_tkeep_o       (cc_tx_k),
    .tx_tlast_o       (cc_tx_l),
    .tx_tvalid_o      (cc_tx_v),
    .tx_tready_i      (cc_tx_r),
    .tx_accept_o      (cr_tx_acc_cc),
    .tx_hdr0_o        (cr_tx_h0_cc),
    .tx_len_dw_o      (cr_tx_len_cc)
  );

  // ---- RQ (user → pclk) + RC (pclk → user) ----
  logic [AXI_DATA_WIDTH-1:0] rq_u_tdata, rq_p_tdata;
  logic [AXI_KEEP_WIDTH-1:0] rq_u_tkeep, rq_p_tkeep;
  logic                      rq_u_tlast, rq_u_tvalid, rq_u_tready;
  logic                      rq_p_tlast, rq_p_tvalid, rq_p_tready;
  logic [AXI_RQ_USER_W-1:0]  rq_u_tuser, rq_p_tuser;

  assign rq_u_tdata  = s_axis_rq_tdata;
  assign rq_u_tkeep  = s_axis_rq_tkeep;
  assign rq_u_tlast  = s_axis_rq_tlast;
  assign rq_u_tvalid = s_axis_rq_tvalid;
  assign rq_u_tuser  = s_axis_rq_tuser;
  assign s_axis_rq_tready = {4{rq_u_tready}};

  rivet_cdc_axis #(
    .DATA_W (AXI_DATA_WIDTH),
    .KEEP_W (AXI_KEEP_WIDTH),
    .USER_W (AXI_RQ_USER_W),
    .DEPTH  (32)
  ) u_cdc_rq (
    .s_clk_i    (user_clk),
    .s_rst_ni   (user_rst_sync_n),
    .s_tdata_i  (rq_u_tdata),
    .s_tkeep_i  (rq_u_tkeep),
    .s_tlast_i  (rq_u_tlast),
    .s_tvalid_i (rq_u_tvalid),
    .s_tready_o (rq_u_tready),
    .s_tuser_i  (rq_u_tuser),
    .m_clk_i    (pclk),
    .m_rst_ni   (pclk_rst_sync_n),
    .m_tdata_o  (rq_p_tdata),
    .m_tkeep_o  (rq_p_tkeep),
    .m_tlast_o  (rq_p_tlast),
    .m_tvalid_o (rq_p_tvalid),
    .m_tready_i (rq_p_tready),
    .m_tuser_o  (rq_p_tuser)
  );

  rivet_tl_rq u_tl_rq (
    .clk_i             (pclk),
    .rst_ni            (pclk_rst_sync_n),
    .bus_master_en_i   (bus_master_en),
    .s_axis_rq_tdata   (rq_p_tdata),
    .s_axis_rq_tkeep   (rq_p_tkeep[1:0]),
    .s_axis_rq_tlast   (rq_p_tlast),
    .s_axis_rq_tvalid  (rq_p_tvalid),
    .s_axis_rq_tready  (rq_p_tready),
    .s_axis_rq_tuser   (rq_p_tuser),
    .tx_tdata_o        (rq_tx_d),
    .tx_tkeep_o        (rq_tx_k),
    .tx_tlast_o        (rq_tx_l),
    .tx_tvalid_o       (rq_tx_v),
    .tx_tready_i       (rq_tx_r),
    .tx_accept_o       (cr_tx_acc_rq),
    .tx_hdr0_o         (cr_tx_h0_rq),
    .tx_len_dw_o       (cr_tx_len_rq),
    .rq_seq_num_o      (rq_seq_p),
    .rq_seq_num_vld_o  (rq_seq_vld_p),
    .rq_tag_o          (rq_tag_p),
    .rq_tag_vld_o      (rq_tag_vld_p),
    .rq_tag_av_o       (rq_tag_av_p),
    .tag_free_i        (rq_tag_free_p)
  );

  logic [AXI_DATA_WIDTH-1:0] rc_p_tdata, rc_u_tdata;
  logic [AXI_KEEP_WIDTH-1:0] rc_p_tkeep, rc_u_tkeep;
  logic                      rc_p_tlast, rc_p_tvalid, rc_p_tready;
  logic                      rc_u_tlast, rc_u_tvalid;
  logic [AXI_RC_USER_W-1:0]  rc_p_tuser, rc_u_tuser;

  rivet_tl_rc u_tl_rc (
    .clk_i            (pclk),
    .rst_ni           (pclk_rst_sync_n),
    .rx_tdata_i       (rc_rx_d),
    .rx_tkeep_i       (rc_rx_k),
    .rx_tlast_i       (rc_rx_l),
    .rx_tvalid_i      (rc_rx_v),
    .rx_tready_o      (rc_rx_r),
    .m_axis_rc_tdata  (rc_p_tdata),
    .m_axis_rc_tkeep  (rc_p_tkeep),
    .m_axis_rc_tlast  (rc_p_tlast),
    .m_axis_rc_tvalid (rc_p_tvalid),
    .m_axis_rc_tready (rc_p_tready),
    .m_axis_rc_tuser  (rc_p_tuser),
    .rx_accept_o      (cr_rx_acc_rc),
    .rx_hdr0_o        (cr_rx_h0_rc),
    .rx_len_dw_o      (cr_rx_len_rc),
    .tag_free_o       (rq_tag_free_p)
  );

  rivet_cdc_axis #(
    .DATA_W (AXI_DATA_WIDTH),
    .KEEP_W (AXI_KEEP_WIDTH),
    .USER_W (AXI_RC_USER_W),
    .DEPTH  (32)
  ) u_cdc_rc (
    .s_clk_i    (pclk),
    .s_rst_ni   (pclk_rst_sync_n),
    .s_tdata_i  (rc_p_tdata),
    .s_tkeep_i  (rc_p_tkeep),
    .s_tlast_i  (rc_p_tlast),
    .s_tvalid_i (rc_p_tvalid),
    .s_tready_o (rc_p_tready),
    .s_tuser_i  (rc_p_tuser),
    .m_clk_i    (user_clk),
    .m_rst_ni   (user_rst_sync_n),
    .m_tdata_o  (rc_u_tdata),
    .m_tkeep_o  (rc_u_tkeep),
    .m_tlast_o  (rc_u_tlast),
    .m_tvalid_o (rc_u_tvalid),
    .m_tready_i (m_axis_rc_tready),
    .m_tuser_o  (rc_u_tuser)
  );

  assign m_axis_rc_tdata  = rc_u_tdata;
  assign m_axis_rc_tkeep  = rc_u_tkeep;
  assign m_axis_rc_tlast  = rc_u_tlast;
  assign m_axis_rc_tvalid = rc_u_tvalid;
  assign m_axis_rc_tuser  = rc_u_tuser;

  // Sync interrupt / AER inputs user_clk → pclk
  rivet_cdc_sync_bus #(.WIDTH(32)) u_sync_msi_int (
    .dst_clk_i(pclk), .dst_rst_ni(pclk_rst_sync_n),
    .src_i(cfg_interrupt_msi_int), .dst_o(msi_int_p)
  );
  rivet_cdc_sync_bus #(.WIDTH(64)) u_sync_msix_addr (
    .dst_clk_i(pclk), .dst_rst_ni(pclk_rst_sync_n),
    .src_i(cfg_interrupt_msix_address), .dst_o(msix_addr_p)
  );
  rivet_cdc_sync_bus #(.WIDTH(32)) u_sync_msix_data (
    .dst_clk_i(pclk), .dst_rst_ni(pclk_rst_sync_n),
    .src_i(cfg_interrupt_msix_data), .dst_o(msix_data_p)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_msix_int (
    .dst_clk_i(pclk), .dst_rst_ni(pclk_rst_sync_n),
    .src_i(cfg_interrupt_msix_int), .dst_o(msix_int_p)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_err_cor (
    .dst_clk_i(pclk), .dst_rst_ni(pclk_rst_sync_n),
    .src_i(cfg_err_cor_in), .dst_o(err_cor_p)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_err_uncor (
    .dst_clk_i(pclk), .dst_rst_ni(pclk_rst_sync_n),
    .src_i(cfg_err_uncor_in), .dst_o(err_uncor_p)
  );

  assign msix_enable_p = 1'b1; // external-table path; no MSI-X cap table yet

  rivet_tl_msi u_tl_msi (
    .clk_i           (pclk),
    .rst_ni          (pclk_rst_sync_n),
    .bus_master_en_i (bus_master_en),
    .link_up_i       (link_up),
    .msi_enable_i    (msi_enable_p),
    .msi_addr_i      (msi_addr_p),
    .msi_data_i      (msi_data_p),
    .msi_int_i       (msi_int_p),
    .msi_enable_o    (),
    .msi_sent_o      (msi_sent_p),
    .msi_fail_o      (msi_fail_p),
    .msix_enable_i   (msix_enable_p),
    .msix_addr_i     (msix_addr_p),
    .msix_data_i     (msix_data_p),
    .msix_int_i      (msix_int_p),
    .msix_sent_o     (msix_sent_p),
    .msix_fail_o     (msix_fail_p),
    .tx_tdata_o      (msi_tx_d),
    .tx_tkeep_o      (msi_tx_k),
    .tx_tlast_o      (msi_tx_l),
    .tx_tvalid_o     (msi_tx_v),
    .tx_tready_i     (msi_tx_r),
    .tx_accept_o     (cr_tx_acc_msi),
    .tx_hdr0_o       (cr_tx_h0_msi),
    .tx_len_dw_o     (cr_tx_len_msi)
  );

  logic err_cor_out_p, err_nf_out_p, err_fatal_out_p;

  rivet_tl_aer u_tl_aer (
    .clk_i              (pclk),
    .rst_ni             (pclk_rst_sync_n),
    .err_cor_in_i       (err_cor_p),
    .err_uncor_in_i     (err_uncor_p),
    .err_cor_out_o      (err_cor_out_p),
    .err_nonfatal_out_o (err_nf_out_p),
    .err_fatal_out_o    (err_fatal_out_p),
    .set_cor_o          (aer_set_cor),
    .set_nonfatal_o     (aer_set_nf)
  );

  // MSI / AER status → user_clk
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_msi_en (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(msi_enable_p), .dst_o(cfg_interrupt_msi_enable)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_msi_sent (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(msi_sent_p), .dst_o(cfg_interrupt_msi_sent)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_msi_fail (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(msi_fail_p), .dst_o(cfg_interrupt_msi_fail)
  );
  assign cfg_interrupt_msix_enable = 1'b1;
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_msix_sent (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(msix_sent_p), .dst_o(cfg_interrupt_msix_sent)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_msix_fail (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(msix_fail_p), .dst_o(cfg_interrupt_msix_fail)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_err_cor_o (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(err_cor_out_p), .dst_o(cfg_err_cor_out)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_err_nf_o (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(err_nf_out_p), .dst_o(cfg_err_nonfatal_out)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_err_fatal_o (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(err_fatal_out_p), .dst_o(cfg_err_fatal_out)
  );

  // Companion RQ tag/seq → user
  rivet_cdc_sync_bus #(.WIDTH(6)) u_sync_rq_seq (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(rq_seq_p), .dst_o(pcie_rq_seq_num0)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_rq_seq_v (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(rq_seq_vld_p), .dst_o(pcie_rq_seq_num_vld0)
  );
  rivet_cdc_sync_bus #(.WIDTH(10)) u_sync_rq_tag (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(rq_tag_p), .dst_o(pcie_rq_tag0)
  );
  rivet_cdc_sync_bus #(.WIDTH(1)) u_sync_rq_tag_v (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(rq_tag_vld_p), .dst_o(pcie_rq_tag_vld0)
  );
  assign pcie_rq_tag1     = '0;
  assign pcie_rq_tag_vld1 = 1'b0;
  rivet_cdc_sync_bus #(.WIDTH(4)) u_sync_rq_tag_av (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(rq_tag_av_p), .dst_o(pcie_rq_tag_av)
  );

  rivet_tl_tx_mux u_tx_mux (
    .clk_i        (pclk),
    .rst_ni       (preset_n),
    .cfg_tdata_i  (cfg_tx_d),
    .cfg_tkeep_i  (cfg_tx_k),
    .cfg_tlast_i  (cfg_tx_l),
    .cfg_tvalid_i (cfg_tx_v),
    .cfg_tready_o (cfg_tx_r),
    .msi_tdata_i  (msi_tx_d),
    .msi_tkeep_i  (msi_tx_k),
    .msi_tlast_i  (msi_tx_l),
    .msi_tvalid_i (msi_tx_v),
    .msi_tready_o (msi_tx_r),
    .cc_tdata_i   (cc_tx_d),
    .cc_tkeep_i   (cc_tx_k),
    .cc_tlast_i   (cc_tx_l),
    .cc_tvalid_i  (cc_tx_v),
    .cc_tready_o  (cc_tx_r),
    .rq_tdata_i   (rq_tx_d),
    .rq_tkeep_i   (rq_tx_k),
    .rq_tlast_i   (rq_tx_l),
    .rq_tvalid_i  (rq_tx_v),
    .rq_tready_o  (rq_tx_r),
    .m_tdata_o    (tl_tx_tdata),
    .m_tkeep_o    (tl_tx_tkeep),
    .m_tlast_o    (tl_tx_tlast),
    .m_tvalid_o   (tl_tx_tvalid),
    .m_tready_i   (tl_tx_tready)
  );

  rivet_tl_credit u_tl_credit (
    .clk_i               (pclk),
    .rst_ni              (preset_n),
    .rx_accept_i         (cr_rx_acc),
    .rx_hdr0_i           (cr_rx_h0),
    .rx_len_dw_i         (cr_rx_len),
    .tx_accept_i         (cr_tx_acc),
    .tx_hdr0_i           (cr_tx_h0),
    .tx_len_dw_i         (cr_tx_len),
    .free_ph_o           (cr_free_ph),
    .free_pd_o           (cr_free_pd),
    .free_nph_o          (cr_free_nph),
    .free_npd_o          (cr_free_npd),
    .free_cplh_o         (cr_free_cplh),
    .free_cpld_o         (cr_free_cpld),
    .free_ph_amt_o       (cr_free_ph_a),
    .free_pd_amt_o       (cr_free_pd_a),
    .free_nph_amt_o      (cr_free_nph_a),
    .free_npd_amt_o      (cr_free_npd_a),
    .free_cplh_amt_o     (cr_free_cplh_a),
    .free_cpld_amt_o     (cr_free_cpld_a),
    .consume_ph_o        (cr_cons_ph),
    .consume_pd_o        (cr_cons_pd),
    .consume_nph_o       (cr_cons_nph),
    .consume_npd_o       (cr_cons_npd),
    .consume_cplh_o      (cr_cons_cplh),
    .consume_cpld_o      (cr_cons_cpld),
    .consume_ph_amt_o    (cr_cons_ph_a),
    .consume_pd_amt_o    (cr_cons_pd_a),
    .consume_nph_amt_o   (cr_cons_nph_a),
    .consume_npd_amt_o   (cr_cons_npd_a),
    .consume_cplh_amt_o  (cr_cons_cplh_a),
    .consume_cpld_amt_o  (cr_cons_cpld_a)
  );

  rivet_tl_fc_stub u_tl_fc (
    .clk_i              (pclk),
    .rst_ni             (preset_n),
    .free_ph_i          (cr_free_ph),
    .free_pd_i          (cr_free_pd),
    .free_nph_i         (cr_free_nph),
    .free_npd_i         (cr_free_npd),
    .free_cplh_i        (cr_free_cplh),
    .free_cpld_i        (cr_free_cpld),
    .free_ph_amt_i      (cr_free_ph_a),
    .free_pd_amt_i      (cr_free_pd_a),
    .free_nph_amt_i     (cr_free_nph_a),
    .free_npd_amt_i     (cr_free_npd_a),
    .free_cplh_amt_i    (cr_free_cplh_a),
    .free_cpld_amt_i    (cr_free_cpld_a),
    .consume_ph_i       (cr_cons_ph),
    .consume_pd_i       (cr_cons_pd),
    .consume_nph_i      (cr_cons_nph),
    .consume_npd_i      (cr_cons_npd),
    .consume_cplh_i     (cr_cons_cplh),
    .consume_cpld_i     (cr_cons_cpld),
    .consume_ph_amt_i   (cr_cons_ph_a),
    .consume_pd_amt_i   (cr_cons_pd_a),
    .consume_nph_amt_i  (cr_cons_nph_a),
    .consume_npd_amt_i  (cr_cons_npd_a),
    .consume_cplh_amt_i (cr_cons_cplh_a),
    .consume_cpld_amt_i (cr_cons_cpld_a),
    .tl_to_dll_fc_o     (tl_to_dll_fc),
    .dll_to_tl_fc_i     (dll_to_tl_fc)
  );

  rivet_dll #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_dll (
    .pclk_i         (pclk),
    .rst_ni         (preset_n),
    .dll_tx_beat_o  (dll_tx_beat),
    .dll_tx_valid_o (dll_tx_valid),
    .dll_tx_ready_i (dll_tx_ready),
    .dll_rx_beat_i  (dll_rx_beat),
    .dll_rx_valid_i (dll_rx_valid),
    .dll_rx_ready_o (dll_rx_ready),
    .mac_to_dll_sb_i (mac_to_dll_sb),
    .dll_to_mac_sb_o (dll_to_mac_sb),
    .tl_to_dll_fc_i (tl_to_dll_fc),
    .dll_to_tl_fc_o (dll_to_tl_fc),
    .tl_tx_tdata_i  (tl_tx_tdata),
    .tl_tx_tkeep_i  (tl_tx_tkeep),
    .tl_tx_tlast_i  (tl_tx_tlast),
    .tl_tx_tvalid_i (tl_tx_tvalid),
    .tl_tx_tready_o (tl_tx_tready),
    .tl_rx_tdata_o  (tl_rx_tdata),
    .tl_rx_tkeep_o  (tl_rx_tkeep),
    .tl_rx_tlast_o  (tl_rx_tlast),
    .tl_rx_tvalid_o (tl_rx_tvalid),
    .tl_rx_tready_i (tl_rx_tready),
    .tl_rx_seq_o    ()
  );

  // PG213 tfc / cfg_fc on pclk, then sync to user_clk
  logic [3:0]  tfc_nph_p, tfc_npd_p;
  logic [2:0]  cfg_fc_sel_p;
  logic [7:0]  cfg_fc_ph_p, cfg_fc_nph_p, cfg_fc_cplh_p;
  logic [11:0] cfg_fc_pd_p, cfg_fc_npd_p, cfg_fc_cpld_p;

  assign tfc_nph_p = dll_to_tl_fc.tx_gate_ready
      ? rivet_fc_tfc_scale({4'h0, dll_to_tl_fc.av.nph}, dll_to_tl_fc.av.nph_inf)
      : 4'h0;
  assign tfc_npd_p = dll_to_tl_fc.tx_gate_ready
      ? rivet_fc_tfc_scale(dll_to_tl_fc.av.npd, dll_to_tl_fc.av.npd_inf)
      : 4'h0;

  rivet_cdc_sync_bus #(.WIDTH(3)) u_sync_fc_sel (
    .dst_clk_i(pclk), .dst_rst_ni(pclk_rst_sync_n),
    .src_i(cfg_fc_sel), .dst_o(cfg_fc_sel_p)
  );
  rivet_cdc_sync_bus #(.WIDTH(4)) u_sync_tfc_nph (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(tfc_nph_p), .dst_o(pcie_tfc_nph_av)
  );
  rivet_cdc_sync_bus #(.WIDTH(4)) u_sync_tfc_npd (
    .dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n),
    .src_i(tfc_npd_p), .dst_o(pcie_tfc_npd_av)
  );

  always_comb begin
    cfg_fc_ph_p   = '0;
    cfg_fc_pd_p   = '0;
    cfg_fc_nph_p  = '0;
    cfg_fc_npd_p  = '0;
    cfg_fc_cplh_p = '0;
    cfg_fc_cpld_p = '0;
    unique case (cfg_fc_sel_p)
      RIVET_CFG_FC_SEL_RX_AVAIL: begin
        cfg_fc_ph_p   = tl_to_dll_fc.ca.ph_inf   ? 8'h00  : tl_to_dll_fc.ca.ph;
        cfg_fc_pd_p   = tl_to_dll_fc.ca.pd_inf   ? 12'h000 : tl_to_dll_fc.ca.pd;
        cfg_fc_nph_p  = tl_to_dll_fc.ca.nph_inf  ? 8'h00  : tl_to_dll_fc.ca.nph;
        cfg_fc_npd_p  = tl_to_dll_fc.ca.npd_inf  ? 12'h000 : tl_to_dll_fc.ca.npd;
        cfg_fc_cplh_p = tl_to_dll_fc.ca.cplh_inf ? 8'h00  : tl_to_dll_fc.ca.cplh;
        cfg_fc_cpld_p = tl_to_dll_fc.ca.cpld_inf ? 12'h000 : tl_to_dll_fc.ca.cpld;
      end
      RIVET_CFG_FC_SEL_RX_CONS: begin
        cfg_fc_ph_p = '0; cfg_fc_pd_p = '0; cfg_fc_nph_p = '0;
        cfg_fc_npd_p = '0; cfg_fc_cplh_p = '0; cfg_fc_cpld_p = '0;
      end
      RIVET_CFG_FC_SEL_TX_AVAIL: begin
        if (!dll_to_tl_fc.tx_gate_ready) begin
          cfg_fc_ph_p = '0; cfg_fc_pd_p = '0; cfg_fc_nph_p = '0;
          cfg_fc_npd_p = '0; cfg_fc_cplh_p = '0; cfg_fc_cpld_p = '0;
        end else begin
          cfg_fc_ph_p   = dll_to_tl_fc.av.ph_inf   ? RIVET_CFG_FC_HDR_INF_TX_AV  : dll_to_tl_fc.av.ph;
          cfg_fc_pd_p   = dll_to_tl_fc.av.pd_inf   ? RIVET_CFG_FC_DATA_INF_TX_AV : dll_to_tl_fc.av.pd;
          cfg_fc_nph_p  = dll_to_tl_fc.av.nph_inf  ? RIVET_CFG_FC_HDR_INF_TX_AV  : dll_to_tl_fc.av.nph;
          cfg_fc_npd_p  = dll_to_tl_fc.av.npd_inf  ? RIVET_CFG_FC_DATA_INF_TX_AV : dll_to_tl_fc.av.npd;
          cfg_fc_cplh_p = dll_to_tl_fc.av.cplh_inf ? RIVET_CFG_FC_HDR_INF_TX_AV  : dll_to_tl_fc.av.cplh;
          cfg_fc_cpld_p = dll_to_tl_fc.av.cpld_inf ? RIVET_CFG_FC_DATA_INF_TX_AV : dll_to_tl_fc.av.cpld;
        end
      end
      RIVET_CFG_FC_SEL_TX_LIMIT: begin
        cfg_fc_ph_p   = dll_to_tl_fc.cl.ph_inf   ? 8'h00  : dll_to_tl_fc.cl.ph;
        cfg_fc_pd_p   = dll_to_tl_fc.cl.pd_inf   ? 12'h000 : dll_to_tl_fc.cl.pd;
        cfg_fc_nph_p  = dll_to_tl_fc.cl.nph_inf  ? 8'h00  : dll_to_tl_fc.cl.nph;
        cfg_fc_npd_p  = dll_to_tl_fc.cl.npd_inf  ? 12'h000 : dll_to_tl_fc.cl.npd;
        cfg_fc_cplh_p = dll_to_tl_fc.cl.cplh_inf ? 8'h00  : dll_to_tl_fc.cl.cplh;
        cfg_fc_cpld_p = dll_to_tl_fc.cl.cpld_inf ? 12'h000 : dll_to_tl_fc.cl.cpld;
      end
      RIVET_CFG_FC_SEL_TX_CONS: begin
        cfg_fc_ph_p   = dll_to_tl_fc.cl.ph_inf   ? 8'h00  : dll_to_tl_fc.cc.ph;
        cfg_fc_pd_p   = dll_to_tl_fc.cl.pd_inf   ? 12'h000 : dll_to_tl_fc.cc.pd;
        cfg_fc_nph_p  = dll_to_tl_fc.cl.nph_inf  ? 8'h00  : dll_to_tl_fc.cc.nph;
        cfg_fc_npd_p  = dll_to_tl_fc.cl.npd_inf  ? 12'h000 : dll_to_tl_fc.cc.npd;
        cfg_fc_cplh_p = dll_to_tl_fc.cl.cplh_inf ? 8'h00  : dll_to_tl_fc.cc.cplh;
        cfg_fc_cpld_p = dll_to_tl_fc.cl.cpld_inf ? 12'h000 : dll_to_tl_fc.cc.cpld;
      end
      default: ;
    endcase
  end

  rivet_cdc_sync_bus #(.WIDTH(8))  u_sync_fc_ph   (.dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n), .src_i(cfg_fc_ph_p),   .dst_o(cfg_fc_ph));
  rivet_cdc_sync_bus #(.WIDTH(12)) u_sync_fc_pd   (.dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n), .src_i(cfg_fc_pd_p),   .dst_o(cfg_fc_pd));
  rivet_cdc_sync_bus #(.WIDTH(8))  u_sync_fc_nph  (.dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n), .src_i(cfg_fc_nph_p),  .dst_o(cfg_fc_nph));
  rivet_cdc_sync_bus #(.WIDTH(12)) u_sync_fc_npd  (.dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n), .src_i(cfg_fc_npd_p),  .dst_o(cfg_fc_npd));
  rivet_cdc_sync_bus #(.WIDTH(8))  u_sync_fc_cplh (.dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n), .src_i(cfg_fc_cplh_p), .dst_o(cfg_fc_cplh));
  rivet_cdc_sync_bus #(.WIDTH(12)) u_sync_fc_cpld (.dst_clk_i(user_clk), .dst_rst_ni(user_rst_sync_n), .src_i(cfg_fc_cpld_p), .dst_o(cfg_fc_cpld));

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

  logic _unused_tie;
  assign _unused_tie = dll_tx_ready ^ dll_rx_valid ^
                       (|mac_to_dll_sb) ^
                       user_rst_init_n ^ pclk_rst_init_n;

endmodule : rivet_pcie_ctrl
