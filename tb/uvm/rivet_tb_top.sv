// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// UVM testbench top — DUT = rivet_pcie_ctrl at PIPE.
// LANES via RIVET_TB_LANES. MODE via RIVET_TB_MODE (0=EP default).

`timescale 1ns/1ps

module rivet_tb_top;
  import uvm_pkg::*;
  import rivet_uvm_pkg::*;
  `include "uvm_macros.svh"

`ifndef RIVET_TB_LANES
  `define RIVET_TB_LANES 1
`endif
`ifndef RIVET_TB_MODE
  `define RIVET_TB_MODE 0
`endif
`ifndef RIVET_TB_GEN
  `define RIVET_TB_GEN 2
`endif
`ifndef RIVET_TB_PIPE_W
  `define RIVET_TB_PIPE_W 16
`endif
`ifdef RIVET_RQ_G4
  `define RIVET_RQ_INST dut.g_rq256.u_tl_rq
`elsif RIVET_RQ_WIDE
  `define RIVET_RQ_INST dut.g_rq128.u_tl_rq
`else
  `define RIVET_RQ_INST dut.g_rq64.u_tl_rq
`endif

  localparam int unsigned LANES  = `RIVET_TB_LANES;
  localparam int unsigned MODE   = `RIVET_TB_MODE;
  localparam int unsigned GEN    = `RIVET_TB_GEN;
  localparam int unsigned PIPE_W = `RIVET_TB_PIPE_W;
  localparam int unsigned AXI_W = rivet_pkg::rivet_axi_data_width(GEN);
  localparam int unsigned KEEP_W = AXI_W / 32;

  logic user_clk;
  logic user_resetn;
  logic pclk;
  logic preset_n;
  logic link_up;
  logic [5:0] cfg_ltssm_state;

  // Shrink the LTSSM 12/24/48/2 ms timeouts and the 1024 TS1 quota so a smoke
  // test can reach L0 in a few thousand cycles.
  localparam int unsigned LTSSM_TIMER_SCALE = 500;
  localparam int unsigned N_TS1_POLLING     = 32;

  initial begin
    // 250 MHz, same rate as pclk. 64 bits is 4 Gbit/s per lane on Gen2 x4.
    user_clk = 0;
    forever #2 user_clk = ~user_clk;
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

  rivet_pipe_if #(.LANES(LANES), .PIPE_DATA_WIDTH(PIPE_W)) pipe_if (.pclk(pclk), .preset_n(preset_n));
  rivet_link_status_if status_if (.pclk(pclk), .preset_n(preset_n));
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
  rivet_interrupt_if intr_if (.aclk(user_clk), .aresetn(user_resetn));

  // cq_np_req driven by companion_agent (defaults to 2'b01 in driver).

  initial begin
    intr_if.msi_int       = '0;
    intr_if.msix_address  = '0;
    intr_if.msix_data     = '0;
    intr_if.msix_int      = 1'b0;
    intr_if.err_cor_in    = 1'b0;
    intr_if.err_uncor_in  = 1'b0;
  end

  rivet_pcie_ctrl #(
    .MODE(MODE),
    .GEN(GEN),
    .LANES(LANES),
    .AXI_DATA_WIDTH(AXI_W),
    .PIPE_DATA_WIDTH(PIPE_W),
    .LTSSM_TIMER_SCALE(LTSSM_TIMER_SCALE),
    .N_TS1_POLLING(N_TS1_POLLING)
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
    .cfg_fc_ph(),
    .cfg_fc_pd(),
    .cfg_fc_nph(),
    .cfg_fc_npd(),
    .cfg_fc_cplh(),
    .cfg_fc_cpld(),
    .cfg_fc_sel(3'b100),
    .cfg_mgmt_addr(cfg_if.addr),
    .cfg_mgmt_function_number(cfg_if.function_number),
    .cfg_mgmt_write(cfg_if.write),
    .cfg_mgmt_write_data(cfg_if.write_data),
    .cfg_mgmt_byte_enable(cfg_if.byte_enable),
    .cfg_mgmt_read(cfg_if.read),
    .cfg_mgmt_read_data(cfg_if.read_data),
    .cfg_mgmt_read_write_done(cfg_if.read_write_done),
    .cfg_mgmt_debug_access(cfg_if.debug_access),
    .cfg_interrupt_msi_int(intr_if.msi_int),
    .cfg_interrupt_msi_enable(intr_if.msi_enable),
    .cfg_interrupt_msi_sent(intr_if.msi_sent),
    .cfg_interrupt_msi_fail(intr_if.msi_fail),
    .cfg_interrupt_msix_address(intr_if.msix_address),
    .cfg_interrupt_msix_data(intr_if.msix_data),
    .cfg_interrupt_msix_int(intr_if.msix_int),
    .cfg_interrupt_msix_enable(intr_if.msix_enable),
    .cfg_interrupt_msix_sent(intr_if.msix_sent),
    .cfg_interrupt_msix_fail(intr_if.msix_fail),
    .cfg_err_cor_in(intr_if.err_cor_in),
    .cfg_err_uncor_in(intr_if.err_uncor_in),
    .cfg_err_cor_out(intr_if.err_cor_out),
    .cfg_err_nonfatal_out(intr_if.err_nonfatal_out),
    .cfg_err_fatal_out(intr_if.err_fatal_out),
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
    .cfg_ltssm_state(cfg_ltssm_state),
    .link_up(link_up)
  );

  assign status_if.link_up         = link_up;
  assign status_if.cfg_ltssm_state = cfg_ltssm_state;
  assign status_if.pipe_rate       = pipe_if.rate;

  // Minimal ASPM: vseqs drive status_if.aspm_*_req; force them onto the MAC
  // request nets (tied to 0 in rivet_mac) and release when deasserted.
  initial begin
    status_if.aspm_l0s_req     = 1'b0;
    status_if.aspm_l1_req      = 1'b0;
    status_if.hot_reset_req    = 1'b0;
    status_if.link_disable_req = 1'b0;
    status_if.cfg_inj_go       = 1'b0;
    status_if.cfg_inj_bus      = 8'h00;
    status_if.cfg_inj_done     = 1'b0;
    status_if.rq_stall_go      = 1'b0;
    status_if.rq_stall_done    = 1'b0;
    status_if.rq_stall_pass    = 1'b0;
    status_if.rq_watch_arm     = 1'b0;
    status_if.rq_watch_b0      = 8'h00;
    status_if.rq_watch_hit     = 1'b0;
    status_if.pipe_rate_force = 1'b0;
    status_if.pipe_rate_value = 3'd0;
    status_if.block_tx_go     = 1'b0;
    status_if.block_tx_done   = 1'b0;
    status_if.rx_word_vld     = 1'b0;
    status_if.rx_word         = '0;
    status_if.rx_word64       = '0;
    status_if.ts_lane_num     = '0;
    status_if.ts_rate_id      = '0;
    status_if.ts_link_num     = '0;
  end

  always @(posedge pclk) begin
    if (!status_if.rq_watch_arm)
      status_if.rq_watch_hit <= 1'b0;
    else if (`RIVET_RQ_INST.tx_tvalid_o &&
             (`RIVET_RQ_INST.tx_hdr0_o == status_if.rq_watch_b0))
      status_if.rq_watch_hit <= 1'b1;
  end

  initial begin
    forever begin
      wait (status_if.rq_watch_arm === 1'b1);
      force `RIVET_RQ_INST.tx_tready_i = 1'b1;
      wait (status_if.rq_watch_arm === 1'b0);
      release `RIVET_RQ_INST.tx_tready_i;
    end
  end

  // Push one CfgRd0 at cfg_inj_bus into the completer and publish the Cpl header.
  // tx_tready is held low so the header beat stays visible.
  initial begin
    forever begin
      wait (status_if.cfg_inj_go === 1'b1);
      @(posedge pclk);
      force dut.u_tl_cfg.tx_tready_i = 1'b0;
      force dut.u_tl_cfg.rx_tvalid_i = 1'b1;
      force dut.u_tl_cfg.rx_tlast_i  = 1'b0;
      force dut.u_tl_cfg.rx_tkeep_i  = 8'hFF;
      force dut.u_tl_cfg.rx_tdata_i  = 64'h0F01_0000_0100_0004;
      @(posedge pclk);
      while (dut.u_tl_cfg.rx_tready_o !== 1'b1) @(posedge pclk);
      @(posedge pclk);
      force dut.u_tl_cfg.rx_tlast_i = 1'b1;
      force dut.u_tl_cfg.rx_tdata_i = {56'h0, status_if.cfg_inj_bus};
      @(posedge pclk);
      while (dut.u_tl_cfg.rx_tready_o !== 1'b1) @(posedge pclk);
      @(posedge pclk);
      force dut.u_tl_cfg.rx_tvalid_i = 1'b0;
      force dut.u_tl_cfg.rx_tlast_i  = 1'b0;
      while (dut.u_tl_cfg.tx_tvalid_o !== 1'b1) @(posedge pclk);
      status_if.cfg_inj_b0     = dut.u_tl_cfg.tx_tdata_o[7:0];
      status_if.cfg_inj_status = dut.u_tl_cfg.tx_tdata_o[55:53];
      status_if.cfg_inj_done   = 1'b1;
      release dut.u_tl_cfg.rx_tvalid_i;
      release dut.u_tl_cfg.rx_tlast_i;
      release dut.u_tl_cfg.rx_tkeep_i;
      release dut.u_tl_cfg.rx_tdata_i;
      release dut.u_tl_cfg.tx_tready_i;
      wait (status_if.cfg_inj_go === 1'b0);
      status_if.cfg_inj_done = 1'b0;
    end
  end

  // Beat 1 of a CfgWr1 descriptor must not be accepted outside RC.
  initial begin
    integer guard;
    integer held;
    bit     pass;
    forever begin
      wait (status_if.rq_stall_go === 1'b1);
      pass = 1'b1;
      @(posedge user_clk);
      force dut.s_axis_rq_tvalid = 1'b1;
      force dut.s_axis_rq_tlast  = 1'b0;
      force dut.s_axis_rq_tkeep  = KEEP_W'(2'b11);
      force dut.s_axis_rq_tuser  = 85'hF;
      force dut.s_axis_rq_tdata  = AXI_W'(64'h0);
      guard = 0;
      while ((dut.s_axis_rq_tready == 4'h0) && (guard < 2000)) begin
        @(posedge user_clk);
        guard++;
      end
      if (dut.s_axis_rq_tready == 4'h0)
        pass = 1'b0;
      @(posedge user_clk);
      force dut.s_axis_rq_tlast = 1'b1;
      force dut.s_axis_rq_tdata = AXI_W'(64'h0000_0000_0000_5801);
      held = 0;
      repeat (50) begin
        @(posedge user_clk);
        if (dut.s_axis_rq_tready != 4'h0)
          pass = 1'b0;
        held++;
      end
      force dut.s_axis_rq_tvalid = 1'b0;
      release dut.s_axis_rq_tvalid;
      release dut.s_axis_rq_tlast;
      release dut.s_axis_rq_tkeep;
      release dut.s_axis_rq_tuser;
      release dut.s_axis_rq_tdata;
      status_if.rq_stall_pass = pass && (held == 50);
      status_if.rq_stall_done = 1'b1;
      wait (status_if.rq_stall_go === 1'b0);
      status_if.rq_stall_done = 1'b0;
    end
  end

  always @(status_if.aspm_l0s_req) begin
    if (status_if.aspm_l0s_req === 1'b1) force dut.u_mac.aspm_l0s_req = 1'b1;
    else                                 release dut.u_mac.aspm_l0s_req;
  end

  always @(status_if.aspm_l1_req) begin
    if (status_if.aspm_l1_req === 1'b1) force dut.u_mac.aspm_l1_req = 1'b1;
    else                                release dut.u_mac.aspm_l1_req;
  end

  always @(status_if.hot_reset_req) begin
    if (status_if.hot_reset_req === 1'b1) force dut.u_mac.hot_reset_req = 1'b1;
    else                                  release dut.u_mac.hot_reset_req;
  end

  always @(status_if.link_disable_req) begin
    if (status_if.link_disable_req === 1'b1) force dut.u_mac.link_disable_req = 1'b1;
    else                                     release dut.u_mac.link_disable_req;
  end

  // Directed Gen3 block test. Class code must not hierarchical-reference this module.
  always @(status_if.pipe_rate_force or status_if.pipe_rate_value) begin
    if (status_if.pipe_rate_force === 1'b1) begin
      force dut.u_mac.u_pipe_adapter.rate_i = status_if.pipe_rate_value;
      force dut.u_mac.u_os_tx.rate_i        = status_if.pipe_rate_value;
      force dut.u_mac.u_os_rx.rate_i        = status_if.pipe_rate_value;
      force dut.u_mac.u_scrambler.rate_i    = status_if.pipe_rate_value;
      force dut.u_mac.u_descrambler.rate_i  = status_if.pipe_rate_value;
    end else begin
      release dut.u_mac.u_pipe_adapter.rate_i;
      release dut.u_mac.u_os_tx.rate_i;
      release dut.u_mac.u_os_rx.rate_i;
      release dut.u_mac.u_scrambler.rate_i;
      release dut.u_mac.u_descrambler.rate_i;
    end
  end

  initial begin
    forever begin
      wait (status_if.block_tx_go === 1'b1);
      @(posedge pclk);
      force dut.u_mac.u_pipe_adapter.sym_tx_valid_i = 1'b1;
      repeat (8) @(posedge pclk);
      release dut.u_mac.u_pipe_adapter.sym_tx_valid_i;
      status_if.block_tx_done = 1'b1;
      wait (status_if.block_tx_go === 1'b0);
      status_if.block_tx_done = 1'b0;
    end
  end

  generate
    if (PIPE_W >= 32) begin : g_gen3_word
      always @(posedge pclk) begin
        status_if.rx_word_vld <= dut.u_mac.sym_rx_valid_raw[0];
        status_if.rx_word     <= dut.u_mac.sym_rx_data_raw[31:0];
        if (PIPE_W >= 64)
          status_if.rx_word64 <= dut.u_mac.sym_rx_data_raw[63:0];
        status_if.ts_lane_num <= dut.u_mac.rx_lane_num[31:0];
        status_if.ts_rate_id  <= dut.u_mac.rx_rate_id;
        status_if.ts_link_num <= dut.u_mac.rx_link_num;
      end
    end
  endgenerate

  // Negotiated width ≈ Lanes not held in Electrical Idle by the MAC.
  always_comb begin
    status_if.negotiated_width = 3'd0;
    for (int unsigned l = 0; l < LANES; l++) begin
      if (!pipe_if.txelecidle[l])
        status_if.negotiated_width = status_if.negotiated_width + 3'd1;
    end
  end

  initial begin
    uvm_config_db#(rivet_pipe_vif)::set(null, "uvm_test_top.env.pipe_agent*", "vif", pipe_if);
    uvm_config_db#(rivet_pipe_vif)::set(null, "uvm_test_top.env.ltssm_peer*", "vif", pipe_if);
    uvm_config_db#(rivet_pipe_vif)::set(null, "uvm_test_top.env.dllp_mon*", "vif", pipe_if);
    uvm_config_db#(rivet_link_status_vif)::set(null, "uvm_test_top", "status_vif", status_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.cq_agent*", "vif", cq_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.cc_agent*", "vif", cc_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.rq_agent*", "vif", rq_if);
    uvm_config_db#(rivet_axi_st_vif)::set(null, "uvm_test_top.env.rc_agent*", "vif", rc_if);
    uvm_config_db#(rivet_cfg_mgmt_vif)::set(null, "uvm_test_top.env.cfg_agent*", "vif", cfg_if);
    uvm_config_db#(rivet_companion_vif)::set(null, "uvm_test_top.env.companion_agent*", "vif", comp_if);
    uvm_config_db#(rivet_companion_vif)::set(null, "uvm_test_top", "comp_vif", comp_if);
    uvm_config_db#(virtual rivet_interrupt_if)::set(null, "uvm_test_top", "intr_vif", intr_if);
    uvm_config_db#(int unsigned)::set(null, "*", "lanes", LANES);
    uvm_config_db#(int unsigned)::set(null, "*", "axi_data_width", AXI_W);
    run_test();
  end
endmodule : rivet_tb_top
