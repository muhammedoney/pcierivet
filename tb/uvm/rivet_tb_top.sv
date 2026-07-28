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
  localparam int unsigned KEEP_W = AXI_W / 32;

  logic user_clk;
  logic user_resetn;
  logic pclk;
  logic preset_n;
  logic link_up;

  initial begin
    user_clk = 0;
    forever #4 user_clk = ~user_clk;
  end

  initial begin
    pclk = 0;
    forever #2 pclk = ~pclk;
  end

  initial begin
    user_resetn = 0;
    preset_n    = 0;
    repeat (10) @(posedge user_clk);
    user_resetn = 1;
    preset_n    = 1;
  end

  rivet_pipe_if #(.LANES(LANES), .PIPE_DATA_WIDTH(16)) pipe_if (.pclk(pclk), .preset_n(preset_n));
  rivet_axi_st_if #(.DATA_WIDTH(AXI_W), .KEEP_WIDTH(KEEP_W), .USER_WIDTH(88), .READY_WIDTH(4))
    cq_if (.aclk(user_clk), .aresetn(user_resetn));
  rivet_axi_st_if #(.DATA_WIDTH(AXI_W), .KEEP_WIDTH(KEEP_W), .USER_WIDTH(88), .READY_WIDTH(4))
    cc_if (.aclk(user_clk), .aresetn(user_resetn));
  rivet_axi_st_if #(.DATA_WIDTH(AXI_W), .KEEP_WIDTH(KEEP_W), .USER_WIDTH(88), .READY_WIDTH(4))
    rq_if (.aclk(user_clk), .aresetn(user_resetn));
  rivet_axi_st_if #(.DATA_WIDTH(AXI_W), .KEEP_WIDTH(KEEP_W), .USER_WIDTH(88), .READY_WIDTH(4))
    rc_if (.aclk(user_clk), .aresetn(user_resetn));
  rivet_cfg_mgmt_if cfg_if (.aclk(user_clk), .aresetn(user_resetn));
  rivet_companion_if comp_if (.aclk(user_clk), .aresetn(user_resetn));

  // Default CQ NP grant (PG213); sequences may override later via force/driver.
  assign comp_if.cq_np_req = 2'b01;

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
    .m_axis_cq_tdata(cq_if.tdata),
    .m_axis_cq_tkeep(cq_if.tkeep),
    .m_axis_cq_tlast(cq_if.tlast),
    .m_axis_cq_tvalid(cq_if.tvalid),
    .m_axis_cq_tready(cq_if.tready[0]),
    .m_axis_cq_tuser(cq_if.tuser[87:0]),
    .s_axis_cc_tdata(cc_if.tdata),
    .s_axis_cc_tkeep(cc_if.tkeep),
    .s_axis_cc_tlast(cc_if.tlast),
    .s_axis_cc_tvalid(cc_if.tvalid),
    .s_axis_cc_tready(cc_if.tready),
    .s_axis_cc_tuser(cc_if.tuser[32:0]),
    .s_axis_rq_tdata(rq_if.tdata),
    .s_axis_rq_tkeep(rq_if.tkeep),
    .s_axis_rq_tlast(rq_if.tlast),
    .s_axis_rq_tvalid(rq_if.tvalid),
    .s_axis_rq_tready(rq_if.tready),
    .s_axis_rq_tuser(rq_if.tuser[84:0]),
    .m_axis_rc_tdata(rc_if.tdata),
    .m_axis_rc_tkeep(rc_if.tkeep),
    .m_axis_rc_tlast(rc_if.tlast),
    .m_axis_rc_tvalid(rc_if.tvalid),
    .m_axis_rc_tready(rc_if.tready[0]),
    .m_axis_rc_tuser(rc_if.tuser[74:0]),
    .pcie_cq_np_req(comp_if.cq_np_req),
    .pcie_cq_np_req_count(comp_if.cq_np_req_count),
    .pcie_rq_seq_num0(comp_if.rq_seq_num0),
    .pcie_rq_seq_num_vld0(comp_if.rq_seq_num_vld0),
    .pcie_rq_tag0(comp_if.rq_tag0),
    .pcie_rq_tag_vld0(comp_if.rq_tag_vld0),
    .pcie_rq_tag1(comp_if.rq_tag1),
    .pcie_rq_tag_vld1(comp_if.rq_tag_vld1),
    .pcie_rq_tag_av(comp_if.rq_tag_av),
    .pcie_tfc_nph_av(comp_if.tfc_nph_av),
    .pcie_tfc_npd_av(comp_if.tfc_npd_av),
    .cfg_mgmt_addr(cfg_if.addr),
    .cfg_mgmt_function_number(cfg_if.function_number),
    .cfg_mgmt_write(cfg_if.write),
    .cfg_mgmt_write_data(cfg_if.write_data),
    .cfg_mgmt_byte_enable(cfg_if.byte_enable),
    .cfg_mgmt_read(cfg_if.read),
    .cfg_mgmt_read_data(cfg_if.read_data),
    .cfg_mgmt_read_write_done(cfg_if.read_write_done),
    .cfg_mgmt_debug_access(cfg_if.debug_access),
    .pipe_txdata(pipe_if.txdata),
    .pipe_txdatak(pipe_if.txdatak),
    .pipe_txdata_valid(pipe_if.txdata_valid),
    .pipe_txstart_block(pipe_if.txstart_block),
    .pipe_txsync_header(pipe_if.txsync_header),
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
    uvm_config_db#(rivet_pipe_vif)::set(null, "uvm_test_top.env.pipe_agent*", "vif", pipe_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.cq_agent*", "vif", cq_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.cc_agent*", "vif", cc_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.rq_agent*", "vif", rq_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.rc_agent*", "vif", rc_if);
    uvm_config_db#(rivet_cfg_mgmt_vif)::set(null, "uvm_test_top.env.cfg_agent*", "vif", cfg_if);
    uvm_config_db#(rivet_companion_vif)::set(null, "uvm_test_top.env.companion_mon*", "vif", comp_if);
    uvm_config_db#(int unsigned)::set(null, "*", "lanes", LANES);
    run_test();
  end
endmodule : rivet_tb_top
