// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Thin AXI-ST async FIFO wrapper around alexforencich axis_async_fifo (MIT).

module rivet_cdc_axis #(
  parameter int unsigned DATA_W  = 64,
  parameter int unsigned KEEP_W  = DATA_W / 32,
  parameter int unsigned USER_W  = 1,
  parameter int unsigned DEPTH   = 32  // KEEP_W-scaled depth → ~16 beats
) (
  input  logic               s_clk_i,
  input  logic               s_rst_ni,
  input  logic [DATA_W-1:0]  s_tdata_i,
  input  logic [KEEP_W-1:0]  s_tkeep_i,
  input  logic               s_tlast_i,
  input  logic               s_tvalid_i,
  output logic               s_tready_o,
  input  logic [USER_W-1:0]  s_tuser_i,

  input  logic               m_clk_i,
  input  logic               m_rst_ni,
  output logic [DATA_W-1:0]  m_tdata_o,
  output logic [KEEP_W-1:0]  m_tkeep_o,
  output logic               m_tlast_o,
  output logic               m_tvalid_o,
  input  logic               m_tready_i,
  output logic [USER_W-1:0]  m_tuser_o
);

  axis_async_fifo #(
    .DEPTH        (DEPTH),
    .DATA_WIDTH   (DATA_W),
    .KEEP_ENABLE  (1),
    .KEEP_WIDTH   (KEEP_W),
    .LAST_ENABLE  (1),
    .ID_ENABLE    (0),
    .DEST_ENABLE  (0),
    .USER_ENABLE  (1),
    .USER_WIDTH   (USER_W),
    .FRAME_FIFO   (0),
    .RAM_PIPELINE (1)
  ) u_fifo (
    .s_clk               (s_clk_i),
    .s_rst               (~s_rst_ni),
    .s_axis_tdata        (s_tdata_i),
    .s_axis_tkeep        (s_tkeep_i),
    .s_axis_tvalid       (s_tvalid_i),
    .s_axis_tready       (s_tready_o),
    .s_axis_tlast        (s_tlast_i),
    .s_axis_tid          ('0),
    .s_axis_tdest        ('0),
    .s_axis_tuser        (s_tuser_i),
    .m_clk               (m_clk_i),
    .m_rst               (~m_rst_ni),
    .m_axis_tdata        (m_tdata_o),
    .m_axis_tkeep        (m_tkeep_o),
    .m_axis_tvalid       (m_tvalid_o),
    .m_axis_tready       (m_tready_i),
    .m_axis_tlast        (m_tlast_o),
    .m_axis_tid          (),
    .m_axis_tdest        (),
    .m_axis_tuser        (m_tuser_o),
    .s_pause_req         (1'b0),
    .s_pause_ack         (),
    .m_pause_req         (1'b0),
    .m_pause_ack         (),
    .s_status_depth      (),
    .s_status_depth_commit(),
    .s_status_overflow   (),
    .s_status_bad_frame  (),
    .s_status_good_frame (),
    .m_status_depth      (),
    .m_status_depth_commit(),
    .m_status_overflow   (),
    .m_status_bad_frame  (),
    .m_status_good_frame ()
  );

endmodule : rivet_cdc_axis
