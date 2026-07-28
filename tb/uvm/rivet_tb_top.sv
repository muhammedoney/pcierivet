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
  logic link_up;

  // PIPE interface (UVM PHY agent binds here)
  rivet_pipe_if #(.LANES(LANES), .PIPE_DATA_WIDTH(16)) pipe_if (.pclk(pclk), .preset_n(preset_n));

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
    // MAC -> PHY (DUT drives; mirror into IF for monitor)
    .pipe_txdata(pipe_if.txdata),
    .pipe_txdatak(pipe_if.txdatak),
    .pipe_txdata_valid(pipe_if.txdata_valid),
    .pipe_txstart_block(pipe_if.txstart_block),
    .pipe_txsync_header(pipe_if.txsync_header),
    // PHY -> MAC (IF driven by UVM pipe agent)
    .pipe_rxdata(pipe_if.rxdata),
    .pipe_rxdatak(pipe_if.rxdatak),
    .pipe_rxdata_valid(pipe_if.rxdata_valid),
    .pipe_rxstart_block(pipe_if.rxstart_block),
    .pipe_rxsync_header(pipe_if.rxsync_header),
    .pipe_txdetectrx(pipe_if.txdetectrx),
    .pipe_txelecidle(pipe_if.txelecidle),
    .pipe_txcompliance(pipe_if.txcompliance),
    .pipe_rxpolarity(pipe_if.rxpolarity),
    .pipe_powerdown(pipe_if.powerdown),
    .pipe_rate(pipe_if.rate),
    .pipe_rxvalid(pipe_if.rxvalid),
    .pipe_phystatus(pipe_if.phystatus),
    .pipe_phystatus_rst(pipe_if.phystatus_rst),
    .pipe_rxelecidle(pipe_if.rxelecidle),
    .pipe_rxstatus(pipe_if.rxstatus),
    .pipe_txmargin(pipe_if.txmargin),
    .pipe_txswing(pipe_if.txswing),
    .pipe_txdeemph(pipe_if.txdeemph),
    .pipe_txeq_ctrl(pipe_if.txeq_ctrl),
    .pipe_txeq_preset(pipe_if.txeq_preset),
    .pipe_txeq_coeff(pipe_if.txeq_coeff),
    .pipe_txeq_fs(pipe_if.txeq_fs),
    .pipe_txeq_lf(pipe_if.txeq_lf),
    .pipe_txeq_new_coeff(pipe_if.txeq_new_coeff),
    .pipe_txeq_done(pipe_if.txeq_done),
    .pipe_rxeq_ctrl(pipe_if.rxeq_ctrl),
    .pipe_rxeq_txpreset(pipe_if.rxeq_txpreset),
    .pipe_rxeq_preset_sel(pipe_if.rxeq_preset_sel),
    .pipe_rxeq_new_txcoeff(pipe_if.rxeq_new_txcoeff),
    .pipe_rxeq_adapt_done(pipe_if.rxeq_adapt_done),
    .pipe_rxeq_done(pipe_if.rxeq_done),
    .pipe_as_mac_in_detect(pipe_if.as_mac_in_detect),
    .pipe_as_cdr_hold_req(pipe_if.as_cdr_hold_req),
    .pipe_as_mac_in_L0(pipe_if.as_mac_in_L0),
    .pipe_cfg_rx_pm_state(pipe_if.cfg_rx_pm_state),
    .link_up(link_up)
  );

  initial begin
    uvm_config_db#(rivet_pipe_vif)::set(null, "uvm_test_top.env.pipe_agent.*", "vif", pipe_if);
    uvm_config_db#(rivet_pipe_vif)::set(null, "uvm_test_top.env.pipe_agent", "vif", pipe_if);
    uvm_config_db#(int unsigned)::set(null, "*", "lanes", LANES);
    run_test();
  end
endmodule : rivet_tb_top
