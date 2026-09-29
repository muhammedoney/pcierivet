// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// EP dual-role AXI-ST app for BFM: BAR0 CQ/CC completer + optional RQ/RC bus-master.

module rivet_ep_dual_app #(
  parameter int unsigned PIO_N = 256
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Completer (BAR0)
  input  logic [63:0] m_axis_cq_tdata,
  input  logic [1:0]  m_axis_cq_tkeep,
  input  logic        m_axis_cq_tlast,
  input  logic        m_axis_cq_tvalid,
  output logic        m_axis_cq_tready,
  input  logic [87:0] m_axis_cq_tuser,

  output logic [63:0] s_axis_cc_tdata,
  output logic [1:0]  s_axis_cc_tkeep,
  output logic        s_axis_cc_tlast,
  output logic        s_axis_cc_tvalid,
  input  logic [3:0]  s_axis_cc_tready,
  output logic [32:0] s_axis_cc_tuser,

  // Requester (bus master)
  output logic [63:0] s_axis_rq_tdata,
  output logic [1:0]  s_axis_rq_tkeep,
  output logic        s_axis_rq_tlast,
  output logic        s_axis_rq_tvalid,
  input  logic [3:0]  s_axis_rq_tready,
  output logic [84:0] s_axis_rq_tuser,

  input  logic [63:0] m_axis_rc_tdata,
  input  logic [1:0]  m_axis_rc_tkeep,
  input  logic        m_axis_rc_tlast,
  input  logic        m_axis_rc_tvalid,
  output logic        m_axis_rc_tready,
  input  logic [74:0] m_axis_rc_tuser,

  // Bus-master stimulus (host Mem32 window)
  input  logic        bm_go_i,
  input  logic        bm_do_wr_i,
  input  logic        bm_do_rd_i,
  input  logic [31:0] bm_host_addr_i,
  input  logic [31:0] bm_wr_data_i,
  output logic [31:0] bm_rd_data_o,
  output logic        bm_busy_o,
  output logic        bm_done_o,
  output logic        bm_err_o
);

  import rivet_pkg::*;

  // ---- Completer ----
  rivet_tl_pio_app #(.PIO_N(PIO_N)) u_pio (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .m_axis_cq_tdata(m_axis_cq_tdata), .m_axis_cq_tkeep(m_axis_cq_tkeep),
    .m_axis_cq_tlast(m_axis_cq_tlast), .m_axis_cq_tvalid(m_axis_cq_tvalid),
    .m_axis_cq_tready(m_axis_cq_tready), .m_axis_cq_tuser(m_axis_cq_tuser),
    .s_axis_cc_tdata(s_axis_cc_tdata), .s_axis_cc_tkeep(s_axis_cc_tkeep),
    .s_axis_cc_tlast(s_axis_cc_tlast), .s_axis_cc_tvalid(s_axis_cc_tvalid),
    .s_axis_cc_tready(s_axis_cc_tready), .s_axis_cc_tuser(s_axis_cc_tuser)
  );

  // ---- Requester FSM (1 DW Mem32) ----
  typedef enum logic [3:0] {
    ST_IDLE   = 4'd0,
    ST_WR0    = 4'd1,
    ST_WR1    = 4'd2,
    ST_WRD    = 4'd3,
    ST_RD0    = 4'd4,
    ST_RD1    = 4'd5,
    ST_RC0    = 4'd6,
    ST_RC1    = 4'd7,
    ST_RCD    = 4'd8,
    ST_DONE   = 4'd9
  } bm_e;

  bm_e          bm_q;
  logic         do_wr_q, do_rd_q;
  logic [31:0]  addr_q, wr_data_q, rd_data_q;
  logic [7:0]   tag_q;
  logic         err_q, done_q;

  assign bm_busy_o   = (bm_q != ST_IDLE) && (bm_q != ST_DONE);
  assign bm_done_o   = done_q;
  assign bm_err_o    = err_q;
  assign bm_rd_data_o = rd_data_q;

  assign s_axis_rq_tkeep = 2'b11;
  assign s_axis_rq_tuser = {77'h0, 8'h0F}; // first_be=F, last_be=0
  assign s_axis_rq_tvalid = (bm_q == ST_WR0) || (bm_q == ST_WR1) || (bm_q == ST_WRD) ||
                            (bm_q == ST_RD0) || (bm_q == ST_RD1);
  assign s_axis_rq_tlast  = (bm_q == ST_WRD) || (bm_q == ST_RD1);
  assign m_axis_rc_tready = (bm_q == ST_RC0) || (bm_q == ST_RC1) || (bm_q == ST_RCD);

  always_comb begin
    s_axis_rq_tdata = '0;
    unique case (bm_q)
      ST_WR0, ST_RD0: s_axis_rq_tdata = {32'h0, addr_q[31:2], 2'b00};
      ST_WR1: s_axis_rq_tdata = {8'h00, tag_q, 16'h0000, 32'h0000_0801}; // MemWr len=1
      ST_RD1: s_axis_rq_tdata = {8'h00, tag_q, 16'h0000, 32'h0000_0001}; // MemRd len=1
      ST_WRD: s_axis_rq_tdata = {32'h0, wr_data_q};
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bm_q      <= ST_IDLE;
      do_wr_q   <= 1'b0;
      do_rd_q   <= 1'b0;
      addr_q    <= '0;
      wr_data_q <= '0;
      rd_data_q <= '0;
      tag_q     <= 8'h10;
      err_q     <= 1'b0;
      done_q    <= 1'b0;
    end else begin
      unique case (bm_q)
        ST_IDLE: begin
          // Level-sensitive go: hold until accepted into WR/RD
          if (bm_go_i && (bm_do_wr_i || bm_do_rd_i)) begin
            do_wr_q   <= bm_do_wr_i;
            do_rd_q   <= bm_do_rd_i;
            addr_q    <= bm_host_addr_i;
            wr_data_q <= bm_wr_data_i;
            err_q     <= 1'b0;
            done_q    <= 1'b0; // clear sticky done on new request
            tag_q     <= tag_q + 8'd1;
            if (bm_do_wr_i)
              bm_q <= ST_WR0;
            else
              bm_q <= ST_RD0;
          end
        end
        ST_WR0: if (s_axis_rq_tvalid && s_axis_rq_tready[0]) bm_q <= ST_WR1;
        ST_WR1: if (s_axis_rq_tvalid && s_axis_rq_tready[0]) bm_q <= ST_WRD;
        ST_WRD: begin
          if (s_axis_rq_tvalid && s_axis_rq_tready[0]) begin
            if (do_rd_q)
              bm_q <= ST_RD0;
            else begin
              done_q <= 1'b1; // sticky until next go
              bm_q   <= ST_DONE;
            end
          end
        end
        ST_RD0: if (s_axis_rq_tvalid && s_axis_rq_tready[0]) bm_q <= ST_RD1;
        ST_RD1: if (s_axis_rq_tvalid && s_axis_rq_tready[0]) bm_q <= ST_RC0;
        ST_RC0: if (m_axis_rc_tvalid && m_axis_rc_tready) bm_q <= ST_RC1;
        ST_RC1: begin
          if (m_axis_rc_tvalid && m_axis_rc_tready) begin
            if (m_axis_rc_tlast) begin
              err_q  <= 1'b1;
              done_q <= 1'b1;
              bm_q   <= ST_DONE;
            end else
              bm_q <= ST_RCD;
          end
        end
        ST_RCD: begin
          if (m_axis_rc_tvalid && m_axis_rc_tready) begin
            rd_data_q <= m_axis_rc_tdata[31:0];
            done_q    <= 1'b1;
            bm_q      <= ST_DONE;
          end
        end
        ST_DONE: bm_q <= ST_IDLE;
        default: bm_q <= ST_IDLE;
      endcase
    end
  end

  wire unused_rc_k = |m_axis_rc_tkeep;
  wire unused_rc_u = |m_axis_rc_tuser;

endmodule : rivet_ep_dual_app
