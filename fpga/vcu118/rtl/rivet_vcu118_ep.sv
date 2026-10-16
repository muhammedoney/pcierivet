// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// VCU118 Endpoint shell: Rivet Gen2 controller + generated PG239 pcie_phy_0.
// Config completions stay inside the controller. BAR0 Mem32 uses rivet_tl_pio_app.
// Requester (RQ/RC) is idle until a later host-memory step.
//
// pcie_phy_0 is created by fpga/vcu118/create_project.tcl (not checked in).

module rivet_vcu118_ep (
  input  logic        sys_clk_p,
  input  logic        sys_clk_n,
  input  logic        pcie_perst_n,
  input  logic        cpu_reset,

  output logic [3:0]  pci_exp_txp,
  output logic [3:0]  pci_exp_txn,
  input  logic [3:0]  pci_exp_rxp,
  input  logic [3:0]  pci_exp_rxn,

  output logic [7:0]  led
);

  localparam int unsigned LANES           = 4;
  localparam int unsigned PIPE_DATA_WIDTH = 16;
  localparam int unsigned PHY_DATA_WIDTH  = 64;

  logic sys_rst_n;
  logic sys_clk;
  logic sys_clk_gt;
  logic sys_clk_bufg;
  logic pipe_clk;
  logic user_clk;
  logic core_clk;
  logic mcap_clk;
  logic phy_phystatus_rst;
  logic phy_ready;
  logic link_up;
  logic [5:0] cfg_ltssm_state;
  logic [LANES-1:0] gt_gtpowergood;
  logic [23:0] hb_q;

  logic [PHY_DATA_WIDTH*LANES-1:0] phy_txdata;
  logic [2*LANES-1:0]              phy_txdatak;
  logic [LANES-1:0]                phy_txdata_valid;
  logic [LANES-1:0]                phy_txstart_block;
  logic [2*LANES-1:0]              phy_txsync_header;
  logic [PHY_DATA_WIDTH*LANES-1:0] phy_rxdata;
  logic [2*LANES-1:0]              phy_rxdatak;
  logic [LANES-1:0]                phy_rxdata_valid;
  logic [2*LANES-1:0]              phy_rxstart_block;
  logic [2*LANES-1:0]              phy_rxsync_header;
  logic                            phy_txdetectrx;
  logic [LANES-1:0]                phy_txelecidle;
  logic [LANES-1:0]                phy_txcompliance;
  logic [LANES-1:0]                phy_rxpolarity;
  logic [1:0]                      phy_powerdown;
  logic [2:0]                      phy_rate_mac;
  logic [LANES-1:0]                phy_rxvalid;
  logic [LANES-1:0]                phy_phystatus;
  logic [LANES-1:0]                phy_rxelecidle;
  logic [3*LANES-1:0]              phy_rxstatus;
  logic [2:0]                      phy_txmargin;
  logic                            phy_txswing;
  logic                            phy_txdeemph;
  logic [2*LANES-1:0]              phy_txeq_ctrl;
  logic [4*LANES-1:0]              phy_txeq_preset;
  logic [6*LANES-1:0]              phy_txeq_coeff;
  logic [5:0]                      phy_txeq_fs;
  logic [5:0]                      phy_txeq_lf;
  logic [18*LANES-1:0]             phy_txeq_new_coeff;
  logic [LANES-1:0]                phy_txeq_done;
  logic [2*LANES-1:0]              phy_rxeq_ctrl;
  logic [4*LANES-1:0]              phy_rxeq_txpreset;
  logic [LANES-1:0]                phy_rxeq_preset_sel;
  logic [18*LANES-1:0]             phy_rxeq_new_txcoeff;
  logic [LANES-1:0]                phy_rxeq_adapt_done;
  logic [LANES-1:0]                phy_rxeq_done;
  logic                            as_mac_in_detect;
  logic                            as_cdr_hold_req;

  logic [PIPE_DATA_WIDTH*LANES-1:0] mac_txdata;
  logic [2*LANES-1:0]               mac_txdatak;
  logic [PIPE_DATA_WIDTH*LANES-1:0] mac_rxdata;
  logic [2*LANES-1:0]               mac_rxdatak;
  logic [LANES-1:0]                 pipe_phystatus_rst_bus;

  logic [63:0] cq_tdata, cc_tdata;
  logic [1:0]  cq_tkeep, cc_tkeep;
  logic        cq_tlast, cq_tvalid, cq_tready;
  logic        cc_tlast, cc_tvalid;
  logic [3:0]  cc_tready;
  logic [87:0] cq_tuser;
  logic [32:0] cc_tuser;

  // Slot PERST is active-low. CPU_RESET (SW9) is active-high.
  assign sys_rst_n = pcie_perst_n & ~cpu_reset;

  IBUFDS_GTE4 u_refclk (
    .O     (sys_clk_gt),
    .ODIV2 (sys_clk),
    .I     (sys_clk_p),
    .CEB   (1'b0),
    .IB    (sys_clk_n)
  );

  BUFG_GT u_bufg_ref (
    .CE      (gt_gtpowergood[0]),
    .CEMASK  (1'b0),
    .CLR     (1'b0),
    .CLRMASK (1'b0),
    .DIV     (3'd0),
    .I       (sys_clk),
    .O       (sys_clk_bufg)
  );

  assign phy_ready              = ~phy_phystatus_rst;
  assign pipe_phystatus_rst_bus = {LANES{phy_phystatus_rst}};

  pcie_phy_0 u_phy (
    .phy_refclk         (sys_clk_bufg),
    .phy_gtrefclk       (sys_clk_gt),
    .phy_rst_n          (sys_rst_n),
    .phy_userclk        (user_clk),
    .phy_mcapclk        (mcap_clk),
    .phy_pclk           (pipe_clk),
    .phy_coreclk        (core_clk),
    .phy_rxp            (pci_exp_rxp),
    .phy_rxn            (pci_exp_rxn),
    .phy_txp            (pci_exp_txp),
    .phy_txn            (pci_exp_txn),
    .phy_txdata         (phy_txdata),
    .phy_txdatak        (phy_txdatak),
    .phy_txdata_valid   (phy_txdata_valid),
    .phy_txstart_block  (phy_txstart_block),
    .phy_txsync_header  (phy_txsync_header),
    .phy_rxdata         (phy_rxdata),
    .phy_rxdatak        (phy_rxdatak),
    .phy_rxdata_valid   (phy_rxdata_valid),
    .phy_rxstart_block  (phy_rxstart_block),
    .phy_rxsync_header  (phy_rxsync_header),
    .phy_txdetectrx     (phy_txdetectrx),
    .phy_txelecidle     (phy_txelecidle),
    .phy_txcompliance   (phy_txcompliance),
    .phy_rxpolarity     (phy_rxpolarity),
    .phy_powerdown      (phy_powerdown),
    .phy_rate           (phy_rate_mac[1:0]),
    .phy_rxvalid        (phy_rxvalid),
    .phy_phystatus      (phy_phystatus),
    .phy_phystatus_rst  (phy_phystatus_rst),
    .phy_rxelecidle     (phy_rxelecidle),
    .phy_rxstatus       (phy_rxstatus),
    .phy_txmargin       (phy_txmargin),
    .phy_txswing        (phy_txswing),
    .phy_txdeemph       (phy_txdeemph),
    .phy_txeq_ctrl      (phy_txeq_ctrl),
    .phy_txeq_preset    (phy_txeq_preset),
    .phy_txeq_coeff     (phy_txeq_coeff),
    .phy_txeq_fs        (phy_txeq_fs),
    .phy_txeq_lf        (phy_txeq_lf),
    .phy_txeq_new_coeff (phy_txeq_new_coeff),
    .phy_txeq_done      (phy_txeq_done),
    .phy_rxeq_ctrl        (phy_rxeq_ctrl),
    .phy_rxeq_txpreset    (phy_rxeq_txpreset),
    .phy_rxeq_preset_sel  (phy_rxeq_preset_sel),
    .phy_rxeq_new_txcoeff (phy_rxeq_new_txcoeff),
    .phy_rxeq_done        (phy_rxeq_done),
    .phy_rxeq_adapt_done  (phy_rxeq_adapt_done),
    .gt_gtpowergood     (gt_gtpowergood),
    .as_mac_in_detect   (as_mac_in_detect),
    .as_cdr_hold_req    (as_cdr_hold_req)
  );

  rivet_pipe_pg239_pad #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH),
    .PHY_DATA_WIDTH  (PHY_DATA_WIDTH)
  ) u_pad (
    .mac_txdata  (mac_txdata),
    .mac_txdatak (mac_txdatak),
    .mac_rxdata  (mac_rxdata),
    .mac_rxdatak (mac_rxdatak),
    .phy_txdata  (phy_txdata),
    .phy_txdatak (phy_txdatak),
    .phy_rxdata  (phy_rxdata),
    .phy_rxdatak (phy_rxdatak)
  );

  rivet_tl_pio_app u_pio (
    .clk_i            (user_clk),
    .rst_ni           (sys_rst_n & phy_ready),
    .m_axis_cq_tdata  (cq_tdata),
    .m_axis_cq_tkeep  (cq_tkeep),
    .m_axis_cq_tlast  (cq_tlast),
    .m_axis_cq_tvalid (cq_tvalid),
    .m_axis_cq_tready (cq_tready),
    .m_axis_cq_tuser  (cq_tuser),
    .s_axis_cc_tdata  (cc_tdata),
    .s_axis_cc_tkeep  (cc_tkeep),
    .s_axis_cc_tlast  (cc_tlast),
    .s_axis_cc_tvalid (cc_tvalid),
    .s_axis_cc_tready (cc_tready),
    .s_axis_cc_tuser  (cc_tuser)
  );

  rivet_pcie_ctrl #(
    .MODE              (0),
    .GEN               (2),
    .SPEED_CHANGE_EN   (1'b1),
    .LANES             (LANES),
    .PIPE_DATA_WIDTH   (PIPE_DATA_WIDTH),
    .LTSSM_TIMER_SCALE (1),
    .N_TS1_POLLING     (1024)
  ) u_ctrl (
    .user_clk    (user_clk),
    .user_resetn (sys_rst_n & phy_ready),
    .pclk        (pipe_clk),
    .preset_n    (sys_rst_n & phy_ready),

    .m_axis_cq_tdata  (cq_tdata),
    .m_axis_cq_tkeep  (cq_tkeep),
    .m_axis_cq_tlast  (cq_tlast),
    .m_axis_cq_tvalid (cq_tvalid),
    .m_axis_cq_tready (cq_tready),
    .m_axis_cq_tuser  (cq_tuser),
    .s_axis_cc_tdata  (cc_tdata),
    .s_axis_cc_tkeep  (cc_tkeep),
    .s_axis_cc_tlast  (cc_tlast),
    .s_axis_cc_tvalid (cc_tvalid),
    .s_axis_cc_tready (cc_tready),
    .s_axis_cc_tuser  (cc_tuser),
    .s_axis_rq_tdata  ('0),
    .s_axis_rq_tkeep  ('0),
    .s_axis_rq_tlast  (1'b0),
    .s_axis_rq_tvalid (1'b0),
    .s_axis_rq_tready (),
    .s_axis_rq_tuser  ('0),
    .m_axis_rc_tdata  (),
    .m_axis_rc_tkeep  (),
    .m_axis_rc_tlast  (),
    .m_axis_rc_tvalid (),
    .m_axis_rc_tready (1'b1),
    .m_axis_rc_tuser  (),

    .pcie_cq_np_req       (2'b01),
    .pcie_cq_np_req_count (),
    .pcie_rq_seq_num0     (),
    .pcie_rq_seq_num_vld0 (),
    .pcie_rq_tag0         (),
    .pcie_rq_tag_vld0     (),
    .pcie_rq_tag1         (),
    .pcie_rq_tag_vld1     (),
    .pcie_rq_tag_av       (),
    .pcie_tfc_nph_av      (),
    .pcie_tfc_npd_av      (),

    .cfg_fc_ph                (),
    .cfg_fc_pd                (),
    .cfg_fc_nph               (),
    .cfg_fc_npd               (),
    .cfg_fc_cplh              (),
    .cfg_fc_cpld              (),
    .cfg_fc_sel               (3'b100),

    .cfg_mgmt_addr            ('0),
    .cfg_mgmt_function_number ('0),
    .cfg_mgmt_write           (1'b0),
    .cfg_mgmt_write_data      ('0),
    .cfg_mgmt_byte_enable     ('0),
    .cfg_mgmt_read            (1'b0),
    .cfg_mgmt_read_data       (),
    .cfg_mgmt_read_write_done (),
    .cfg_mgmt_debug_access    (1'b0),

    .cfg_interrupt_msi_int    ('0),
    .cfg_interrupt_msi_enable (),
    .cfg_interrupt_msi_sent   (),
    .cfg_interrupt_msi_fail   (),
    .cfg_interrupt_msix_address ('0),
    .cfg_interrupt_msix_data  ('0),
    .cfg_interrupt_msix_int   (1'b0),
    .cfg_interrupt_msix_enable (),
    .cfg_interrupt_msix_sent  (),
    .cfg_interrupt_msix_fail  (),
    .cfg_err_cor_in           (1'b0),
    .cfg_err_uncor_in         (1'b0),
    .cfg_err_cor_out          (),
    .cfg_err_nonfatal_out     (),
    .cfg_err_fatal_out        (),

    .pipe_txdata         (mac_txdata),
    .pipe_txdatak        (mac_txdatak),
    .pipe_txdata_valid   (phy_txdata_valid),
    .pipe_txstart_block  (phy_txstart_block),
    .pipe_txsync_header  (phy_txsync_header),
    .pipe_rxdata         (mac_rxdata),
    .pipe_rxdatak        (mac_rxdatak),
    .pipe_rxdata_valid   (phy_rxdata_valid),
    .pipe_rxstart_block  (phy_rxstart_block),
    .pipe_rxsync_header  (phy_rxsync_header),
    .pipe_txdetectrx     (phy_txdetectrx),
    .pipe_txelecidle     (phy_txelecidle),
    .pipe_txcompliance   (phy_txcompliance),
    .pipe_rxpolarity     (phy_rxpolarity),
    .pipe_powerdown      (phy_powerdown),
    .pipe_rate           (phy_rate_mac),
    .pipe_rxvalid        (phy_rxvalid),
    .pipe_phystatus      (phy_phystatus),
    .pipe_phystatus_rst  (pipe_phystatus_rst_bus),
    .pipe_rxelecidle     (phy_rxelecidle),
    .pipe_rxstatus       (phy_rxstatus),
    .pipe_txmargin       (phy_txmargin),
    .pipe_txswing        (phy_txswing),
    .pipe_txdeemph       (phy_txdeemph),
    .pipe_txeq_ctrl      (phy_txeq_ctrl),
    .pipe_txeq_preset    (phy_txeq_preset),
    .pipe_txeq_coeff     (phy_txeq_coeff),
    .pipe_txeq_fs        (phy_txeq_fs),
    .pipe_txeq_lf        (phy_txeq_lf),
    .pipe_txeq_new_coeff (phy_txeq_new_coeff),
    .pipe_txeq_done      (phy_txeq_done),
    .pipe_rxeq_ctrl        (phy_rxeq_ctrl),
    .pipe_rxeq_txpreset    (phy_rxeq_txpreset),
    .pipe_rxeq_preset_sel  (phy_rxeq_preset_sel),
    .pipe_rxeq_new_txcoeff (phy_rxeq_new_txcoeff),
    .pipe_rxeq_adapt_done  (phy_rxeq_adapt_done),
    .pipe_rxeq_done        (phy_rxeq_done),
    .pipe_as_mac_in_detect (as_mac_in_detect),
    .pipe_as_cdr_hold_req  (as_cdr_hold_req),
    .pipe_as_mac_in_L0     (),
    .pipe_cfg_rx_pm_state  (),

    .cfg_ltssm_state (cfg_ltssm_state),
    .link_up         (link_up)
  );

  always_ff @(posedge pipe_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) hb_q <= '0;
    else            hb_q <= hb_q + 24'd1;
  end

  // GPIO LEDs, DS37..DS30. L0 is 6'h10, so led[4] is the L0 bit of LTSSM.
  assign led[0]   = link_up;
  assign led[1]   = phy_ready;
  assign led[2]   = hb_q[23];
  assign led[7:3] = cfg_ltssm_state[4:0];

endmodule
