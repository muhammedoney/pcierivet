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
  localparam int unsigned KEEP_W = AXI_W / 32; // PG213: one TKEEP bit per Dword

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
  logic               s_axis_cc_tlast, s_axis_cc_tvalid;
  logic [3:0]         s_axis_cc_tready;
  logic [32:0]        s_axis_cc_tuser;
  // RQ
  logic [AXI_W-1:0]   s_axis_rq_tdata;
  logic [KEEP_W-1:0]  s_axis_rq_tkeep;
  logic               s_axis_rq_tlast, s_axis_rq_tvalid;
  logic [3:0]         s_axis_rq_tready;
  logic [84:0]        s_axis_rq_tuser;
  // RC
  logic [AXI_W-1:0]   m_axis_rc_tdata;
  logic [KEEP_W-1:0]  m_axis_rc_tkeep;
  logic               m_axis_rc_tlast, m_axis_rc_tvalid, m_axis_rc_tready;
  logic [74:0]        m_axis_rc_tuser;
  // PG213 companion flow-control / tracking
  logic [1:0]         pcie_cq_np_req;
  logic [5:0]         pcie_cq_np_req_count, pcie_rq_seq_num0;
  logic               pcie_rq_seq_num_vld0;
  logic [9:0]         pcie_rq_tag0, pcie_rq_tag1;
  logic               pcie_rq_tag_vld0, pcie_rq_tag_vld1;
  logic [3:0]         pcie_rq_tag_av, pcie_tfc_nph_av, pcie_tfc_npd_av;
  // Configuration Management (PG213)
  logic [9:0]         cfg_mgmt_addr;
  logic [7:0]         cfg_mgmt_function_number;
  logic               cfg_mgmt_write, cfg_mgmt_read, cfg_mgmt_read_write_done;
  logic               cfg_mgmt_debug_access;
  logic [31:0]        cfg_mgmt_write_data, cfg_mgmt_read_data;
  logic [3:0]         cfg_mgmt_byte_enable;
  // PIPE (PG239-aligned widths; Gen2 smoke uses 16-bit datapath)
  logic [16*LANES-1:0]  pipe_txdata, pipe_rxdata;
  logic [2*LANES-1:0]   pipe_txdatak, pipe_rxdatak;
  logic [LANES-1:0]     pipe_txdata_valid, pipe_txstart_block;
  logic [2*LANES-1:0]   pipe_txsync_header;
  logic [LANES-1:0]     pipe_rxdata_valid;
  logic [2*LANES-1:0]   pipe_rxstart_block, pipe_rxsync_header;
  logic                 pipe_txdetectrx;
  logic [LANES-1:0]     pipe_txelecidle, pipe_txcompliance, pipe_rxpolarity;
  logic [1:0]           pipe_powerdown;
  logic [2:0]           pipe_rate;
  logic [LANES-1:0]     pipe_rxvalid, pipe_phystatus, pipe_phystatus_rst, pipe_rxelecidle;
  logic [3*LANES-1:0]   pipe_rxstatus;
  logic [2:0]           pipe_txmargin;
  logic                 pipe_txswing, pipe_txdeemph;
  logic [2*LANES-1:0]   pipe_txeq_ctrl;
  logic [4*LANES-1:0]   pipe_txeq_preset;
  logic [6*LANES-1:0]   pipe_txeq_coeff;
  logic [5:0]           pipe_txeq_fs, pipe_txeq_lf;
  logic [18*LANES-1:0]  pipe_txeq_new_coeff;
  logic [LANES-1:0]     pipe_txeq_done;
  logic [2*LANES-1:0]   pipe_rxeq_ctrl;
  logic [4*LANES-1:0]   pipe_rxeq_txpreset;
  logic [LANES-1:0]     pipe_rxeq_preset_sel, pipe_rxeq_adapt_done, pipe_rxeq_done;
  logic [18*LANES-1:0]  pipe_rxeq_new_txcoeff;
  logic                 pipe_as_mac_in_detect, pipe_as_cdr_hold_req, pipe_as_mac_in_L0;
  logic [1:0]           pipe_cfg_rx_pm_state;
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
  assign pcie_cq_np_req = 2'b01;
  assign cfg_mgmt_addr = '0;
  assign cfg_mgmt_function_number = '0;
  assign cfg_mgmt_write = 1'b0;
  assign cfg_mgmt_write_data = '0;
  assign cfg_mgmt_byte_enable = '0;
  assign cfg_mgmt_read = 1'b0;
  assign cfg_mgmt_debug_access = 1'b0;
  assign pipe_rxdata = '0;
  assign pipe_rxdatak = '0;
  assign pipe_rxdata_valid = '0;
  assign pipe_rxstart_block = '0;
  assign pipe_rxsync_header = '0;
  assign pipe_rxvalid = '0;
  assign pipe_rxelecidle = '1;
  assign pipe_rxstatus = '0;
  assign pipe_phystatus = '0;
  assign pipe_phystatus_rst = '0;
  assign pipe_txeq_fs = '0;
  assign pipe_txeq_lf = '0;
  assign pipe_txeq_new_coeff = '0;
  assign pipe_txeq_done = '0;
  assign pipe_rxeq_preset_sel = '0;
  assign pipe_rxeq_new_txcoeff = '0;
  assign pipe_rxeq_adapt_done = '0;
  assign pipe_rxeq_done = '0;

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
    .pcie_cq_np_req(pcie_cq_np_req),
    .pcie_cq_np_req_count(pcie_cq_np_req_count),
    .pcie_rq_seq_num0(pcie_rq_seq_num0),
    .pcie_rq_seq_num_vld0(pcie_rq_seq_num_vld0),
    .pcie_rq_tag0(pcie_rq_tag0),
    .pcie_rq_tag_vld0(pcie_rq_tag_vld0),
    .pcie_rq_tag1(pcie_rq_tag1),
    .pcie_rq_tag_vld1(pcie_rq_tag_vld1),
    .pcie_rq_tag_av(pcie_rq_tag_av),
    .pcie_tfc_nph_av(pcie_tfc_nph_av),
    .pcie_tfc_npd_av(pcie_tfc_npd_av),
    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_function_number(cfg_mgmt_function_number),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),
    .cfg_mgmt_debug_access(cfg_mgmt_debug_access),
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

  initial begin
    run_test();
  end
endmodule : rivet_tb_top
