// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// DK-DEV-AGI027-RA-B compile check: Gen2 x4 soft controller on AGIB027.
// The kit PCIe edge is R-tile 14C (PIPE 5.1 SerDes). That is not this
// controller's 16-bit Gen2 PIPE, so nothing here is pinned to the edge.
// clk, reset_n, and led are virtual pins. RX PIPE is held in electrical idle.

module rivet_agi027_ep (
  input  logic       clk,
  input  logic       reset_n,
  output logic [3:0] led
);

  localparam int unsigned LANES           = 4;
  localparam int unsigned PIPE_DATA_WIDTH = 16;

  logic [23:0] hb_q;
  logic        link_up;
  logic [5:0]  cfg_ltssm_state;

  logic [63:0] cq_tdata, cc_tdata;
  logic [1:0]  cq_tkeep, cc_tkeep;
  logic        cq_tlast, cq_tvalid, cq_tready;
  logic        cc_tlast, cc_tvalid;
  logic [3:0]  cc_tready;
  logic [87:0] cq_tuser;
  logic [32:0] cc_tuser;

  logic [PIPE_DATA_WIDTH*LANES-1:0] mac_txdata;
  logic [2*LANES-1:0]               mac_txdatak;
  logic [LANES-1:0]                 mac_txdata_valid;
  logic [LANES-1:0]                 mac_txelecidle;

  rivet_tl_pio_app u_pio (
    .clk_i            (clk),
    .rst_ni           (reset_n),
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
    .user_clk    (clk),
    .user_resetn (reset_n),
    .pclk        (clk),
    .preset_n    (reset_n),

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

    .cfg_interrupt_msi_int      ('0),
    .cfg_interrupt_msi_enable   (),
    .cfg_interrupt_msi_sent     (),
    .cfg_interrupt_msi_fail     (),
    .cfg_interrupt_msix_address ('0),
    .cfg_interrupt_msix_data    ('0),
    .cfg_interrupt_msix_int     (1'b0),
    .cfg_interrupt_msix_enable  (),
    .cfg_interrupt_msix_sent    (),
    .cfg_interrupt_msix_fail    (),
    .cfg_err_cor_in             (1'b0),
    .cfg_err_uncor_in           (1'b0),
    .cfg_err_cor_out            (),
    .cfg_err_nonfatal_out       (),
    .cfg_err_fatal_out          (),

    .pipe_txdata         (mac_txdata),
    .pipe_txdatak        (mac_txdatak),
    .pipe_txdata_valid   (mac_txdata_valid),
    .pipe_txstart_block  (),
    .pipe_txsync_header  (),
    .pipe_rxdata         ('0),
    .pipe_rxdatak        ('0),
    .pipe_rxdata_valid   ('0),
    .pipe_rxstart_block  ('0),
    .pipe_rxsync_header  ('0),
    .pipe_txdetectrx     (),
    .pipe_txelecidle     (mac_txelecidle),
    .pipe_txcompliance   (),
    .pipe_rxpolarity     (),
    .pipe_powerdown      (),
    .pipe_rate           (),
    .pipe_rxvalid        ('0),
    .pipe_phystatus      ('0),
    .pipe_phystatus_rst  ('0),
    .pipe_rxelecidle     ({LANES{1'b1}}),
    .pipe_rxstatus       ('0),
    .pipe_txmargin       (),
    .pipe_txswing        (),
    .pipe_txdeemph       (),
    .pipe_txeq_ctrl      (),
    .pipe_txeq_preset    (),
    .pipe_txeq_coeff     (),
    .pipe_txeq_fs        ('0),
    .pipe_txeq_lf        ('0),
    .pipe_txeq_new_coeff ('0),
    .pipe_txeq_done      ('0),
    .pipe_rxeq_ctrl      (),
    .pipe_rxeq_txpreset  (),
    .pipe_rxeq_preset_sel  ('0),
    .pipe_rxeq_new_txcoeff ('0),
    .pipe_rxeq_adapt_done  ('0),
    .pipe_rxeq_done        ('0),
    .pipe_as_mac_in_detect (),
    .pipe_as_cdr_hold_req  (),
    .pipe_as_mac_in_L0     (),
    .pipe_cfg_rx_pm_state  (),

    .cfg_ltssm_state (cfg_ltssm_state),
    .link_up         (link_up)
  );

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) hb_q <= '0;
    else          hb_q <= hb_q + 24'd1;
  end

  assign led[0] = link_up;
  assign led[1] = (cfg_ltssm_state == 6'h10);
  assign led[2] = hb_q[23];
  assign led[3] = ^{mac_txdata, mac_txdatak, mac_txdata_valid, mac_txelecidle};

endmodule
