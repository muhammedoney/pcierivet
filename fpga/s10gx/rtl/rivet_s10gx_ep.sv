// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Stratix 10 GX FPGA Development Kit (DK-DEV-1SGX-H-A) Endpoint shell.
// Rivet Gen2 controller + L/H-tile Native PHY in PIPE Gen2 x4 mode.
// Config completions stay inside the controller. BAR0 Mem32 uses rivet_tl_pio_app.
// Requester (RQ/RC) is idle until a later host-memory step.
//
// rivet_s10gx_link is written by fpga/s10gx/create_project.tcl (not checked in).
// It stitches the generated ATX PLL, Native PHY, and reset controller.
// This top packs Rivet's 16-bit PIPE symbols into the L/H-tile Native PHY
// 80-bit word (simplified interface off, PMA width 10, byte serializer x2).
// Stratix 10 L- and H-Tile PHY user guide / native_s10_htile interfaces.tcl:
//   byte0 data [7:0], datak [8], compliance [9], elecidle [10]
//   byte1 data [18:11], datak [19]
//   detectrx [20], powerdown [22:21], margin [25:23], deemph [26], swing [27]
//   rate [33:32], rxpolarity [34]
//   RX data [7:0] and [23:16], datak [8] and [24]
//   phystatus [32], rxvalid [33], rxstatus [36:34]
// Each lane owns 80 bits. Logical lane 0 is edge lane 0 and the PCS
// bonding master.
//
// PERST# is AJ34 (active-low, 3.0 V). CPU_RESETn (S4, A20) and USER_PB0
// (S5, B20) are active-low buttons on the LED daughter card.

module rivet_s10gx_ep (
  input  logic       pcie_refclk_p,
  input  logic       clk50,
  input  logic       pcie_perstn,
  input  logic       cpu_resetn,
  input  logic       user_pb0,

  output logic [3:0] pci_exp_txp,
  input  logic [3:0] pci_exp_rxp,

  output logic [3:0] led
);

  localparam int unsigned LANES           = 4;
  localparam int unsigned PIPE_DATA_WIDTH = 16;
  localparam int unsigned WORD            = 80;

  logic sys_rst_n;
  logic pipe_clk;
  logic phy_ready;
  logic link_up;
  logic [5:0] cfg_ltssm_state;
  logic [23:0] hb_q;

  logic [WORD*LANES-1:0] tx_parallel_data;
  logic [WORD*LANES-1:0] rx_parallel_data;
  logic [LANES-1:0]      rx_elecidle_w;

  logic [PIPE_DATA_WIDTH*LANES-1:0] mac_txdata;
  logic [2*LANES-1:0]               mac_txdatak;
  logic [LANES-1:0]                 mac_txdata_valid;
  logic [LANES-1:0]                 mac_txstart_block;
  logic [2*LANES-1:0]               mac_txsync_header;
  logic [PIPE_DATA_WIDTH*LANES-1:0] mac_rxdata;
  logic [2*LANES-1:0]               mac_rxdatak;
  logic                             mac_txdetectrx;
  logic [LANES-1:0]                 mac_txelecidle;
  logic [LANES-1:0]                 mac_txcompliance;
  logic [LANES-1:0]                 mac_rxpolarity;
  logic [1:0]                       mac_powerdown;
  logic [2:0]                       mac_rate;
  logic [LANES-1:0]                 mac_rxvalid;
  logic [LANES-1:0]                 mac_phystatus;
  logic [LANES-1:0]                 mac_rxelecidle;
  logic [3*LANES-1:0]               mac_rxstatus;
  logic [2:0]                       mac_txmargin;
  logic                             mac_txswing;
  logic                             mac_txdeemph;
  logic [2*LANES-1:0]               mac_txeq_ctrl;
  logic [4*LANES-1:0]               mac_txeq_preset;
  logic [6*LANES-1:0]               mac_txeq_coeff;
  logic [2*LANES-1:0]               mac_rxeq_ctrl;
  logic [4*LANES-1:0]               mac_rxeq_txpreset;
  logic                             as_mac_in_detect;
  logic                             as_cdr_hold_req;
  logic                             as_mac_in_l0;
  logic [1:0]                       cfg_rx_pm;

  logic [63:0] cq_tdata, cc_tdata;
  logic [1:0]  cq_tkeep, cc_tkeep;
  logic        cq_tlast, cq_tvalid, cq_tready;
  logic        cc_tlast, cc_tvalid;
  logic [3:0]  cc_tready;
  logic [87:0] cq_tuser;
  logic [32:0] cc_tuser;

  // All three are active-low and released high.
  assign sys_rst_n = pcie_perstn & cpu_resetn & user_pb0;

  always_comb begin
    tx_parallel_data = '0;
    mac_rxdata       = '0;
    mac_rxdatak      = '0;
    mac_phystatus    = '0;
    mac_rxvalid      = '0;
    mac_rxstatus     = '0;
    for (int i = 0; i < LANES; i++) begin
      tx_parallel_data[i*WORD +: 8]       = mac_txdata[i*16 +: 8];
      tx_parallel_data[i*WORD + 8]        = mac_txdatak[i*2];
      tx_parallel_data[i*WORD + 9]        = mac_txcompliance[i];
      tx_parallel_data[i*WORD + 10]       = mac_txelecidle[i];
      tx_parallel_data[i*WORD + 11 +: 8]  = mac_txdata[i*16 + 8 +: 8];
      tx_parallel_data[i*WORD + 19]       = mac_txdatak[i*2 + 1];
      tx_parallel_data[i*WORD + 20]       = mac_txdetectrx;
      tx_parallel_data[i*WORD + 21 +: 2]  = mac_powerdown;
      tx_parallel_data[i*WORD + 23 +: 3]  = mac_txmargin;
      tx_parallel_data[i*WORD + 26]       = mac_txdeemph;
      tx_parallel_data[i*WORD + 27]       = mac_txswing;
      tx_parallel_data[i*WORD + 32 +: 2]  = mac_rate[1:0];
      tx_parallel_data[i*WORD + 34]       = mac_rxpolarity[i];

      mac_rxdata[i*16 +: 8]      = rx_parallel_data[i*WORD +: 8];
      mac_rxdata[i*16 + 8 +: 8]  = rx_parallel_data[i*WORD + 16 +: 8];
      mac_rxdatak[i*2]           = rx_parallel_data[i*WORD + 8];
      mac_rxdatak[i*2 + 1]       = rx_parallel_data[i*WORD + 24];
      mac_phystatus[i]           = rx_parallel_data[i*WORD + 32];
      mac_rxvalid[i]             = rx_parallel_data[i*WORD + 33];
      mac_rxstatus[i*3 +: 3]     = rx_parallel_data[i*WORD + 34 +: 3];
    end
  end

  assign mac_rxelecidle = rx_elecidle_w;

  // The refclk complement is pcie_refclk_p(n) in s10gx_pins.tcl.
  // Serial complements are paired by Quartus from the positive pin.
  rivet_s10gx_link u_link (
    .refclk            (pcie_refclk_p),
    .clk50             (clk50),
    .reset_n           (sys_rst_n),
    .tx_serial_data    (pci_exp_txp),
    .rx_serial_data    (pci_exp_rxp),
    .pipe_clk          (pipe_clk),
    .phy_ready         (phy_ready),
    .tx_parallel_data  (tx_parallel_data),
    .rx_parallel_data  (rx_parallel_data),
    .rx_elecidle       (rx_elecidle_w)
  );

  rivet_tl_pio_app u_pio (
    .clk_i            (pipe_clk),
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
    .user_clk    (pipe_clk),
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
    .pipe_txdata_valid   (mac_txdata_valid),
    .pipe_txstart_block  (mac_txstart_block),
    .pipe_txsync_header  (mac_txsync_header),
    .pipe_rxdata         (mac_rxdata),
    .pipe_rxdatak        (mac_rxdatak),
    .pipe_rxdata_valid   ({LANES{1'b1}}),
    .pipe_rxstart_block  ('0),
    .pipe_rxsync_header  ('0),
    .pipe_txdetectrx     (mac_txdetectrx),
    .pipe_txelecidle     (mac_txelecidle),
    .pipe_txcompliance   (mac_txcompliance),
    .pipe_rxpolarity     (mac_rxpolarity),
    .pipe_powerdown      (mac_powerdown),
    .pipe_rate           (mac_rate),
    .pipe_rxvalid        (mac_rxvalid),
    .pipe_phystatus      (mac_phystatus),
    .pipe_phystatus_rst  ({LANES{~phy_ready}}),
    .pipe_rxelecidle     (mac_rxelecidle),
    .pipe_rxstatus       (mac_rxstatus),
    .pipe_txmargin       (mac_txmargin),
    .pipe_txswing        (mac_txswing),
    .pipe_txdeemph       (mac_txdeemph),
    .pipe_txeq_ctrl      (mac_txeq_ctrl),
    .pipe_txeq_preset    (mac_txeq_preset),
    .pipe_txeq_coeff     (mac_txeq_coeff),
    .pipe_txeq_fs        (6'b0),
    .pipe_txeq_lf        (6'b0),
    .pipe_txeq_new_coeff ('0),
    .pipe_txeq_done      ('0),
    .pipe_rxeq_ctrl        (mac_rxeq_ctrl),
    .pipe_rxeq_txpreset    (mac_rxeq_txpreset),
    .pipe_rxeq_preset_sel  ('0),
    .pipe_rxeq_new_txcoeff ('0),
    .pipe_rxeq_adapt_done  ('0),
    .pipe_rxeq_done        ('0),
    .pipe_as_mac_in_detect (as_mac_in_detect),
    .pipe_as_cdr_hold_req  (as_cdr_hold_req),
    .pipe_as_mac_in_L0     (as_mac_in_l0),
    .pipe_cfg_rx_pm_state  (cfg_rx_pm),

    .cfg_ltssm_state (cfg_ltssm_state),
    .link_up         (link_up)
  );

  always_ff @(posedge clk50 or negedge sys_rst_n) begin
    if (!sys_rst_n) hb_q <= '0;
    else            hb_q <= hb_q + 24'd1;
  end

  // USER_LED_G0..G3 light when driven low. L0 is 6'h10.
  assign led[0] = ~link_up;
  assign led[1] = ~phy_ready;
  assign led[2] = ~hb_q[23];
  assign led[3] = (cfg_ltssm_state != 6'h10);

  wire _unused_mac = (|mac_txdata_valid) ^ (|mac_txstart_block) ^ (|mac_txsync_header)
                   ^ mac_rate[2] ^ as_mac_in_detect ^ as_cdr_hold_req
                   ^ as_mac_in_l0 ^ (|cfg_rx_pm) ^ (|mac_txeq_ctrl)
                   ^ (|mac_txeq_preset) ^ (|mac_txeq_coeff)
                   ^ (|mac_rxeq_ctrl) ^ (|mac_rxeq_txpreset);

endmodule
