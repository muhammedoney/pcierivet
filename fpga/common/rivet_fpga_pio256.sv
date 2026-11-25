// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Gen4 lab BAR0. One 256-bit CQ beat, one DW Mem32. MemWr is posted.

module rivet_fpga_pio256 #(
  parameter int unsigned PIO_N = 256
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic [255:0] m_axis_cq_tdata,
  input  logic [7:0]   m_axis_cq_tkeep,
  input  logic         m_axis_cq_tlast,
  input  logic         m_axis_cq_tvalid,
  output logic         m_axis_cq_tready,
  input  logic [87:0]  m_axis_cq_tuser,

  output logic [255:0] s_axis_cc_tdata,
  output logic [7:0]   s_axis_cc_tkeep,
  output logic         s_axis_cc_tlast,
  output logic         s_axis_cc_tvalid,
  input  logic [3:0]   s_axis_cc_tready,
  output logic [32:0]  s_axis_cc_tuser
);

  import rivet_pkg::*;

  typedef enum logic [1:0] {
    ST_CQ  = 2'd0,
    ST_RD  = 2'd1,
    ST_CC  = 2'd2
  } st_e;

  localparam int unsigned PIO_AW = (PIO_N <= 1) ? 1 : $clog2(PIO_N);

  st_e               st_q;
  logic              pio_ready;
  logic [PIO_AW-1:0] pio_init_q;
  (* ram_style = "block" *) logic [31:0] pio_q [0:PIO_N-1];
  logic [31:0]       pio_rd_q;
  logic [31:0]       addr_q;
  logic [15:0]       req_id_q;
  logic [7:0]        tag_q;
  logic              we_q;
  logic [PIO_AW-1:0] waddr_q;
  logic [31:0]       wdata_q;

  wire [9:0]  cq_len  = m_axis_cq_tdata[73:64];
  wire [3:0]  cq_type = m_axis_cq_tdata[78:75];
  wire        cq_wr   = (cq_type == RIVET_CQ_REQ_MEMWR);
  wire        cq_rd   = (cq_type == RIVET_CQ_REQ_MEMRD);
  wire        cq_one  = m_axis_cq_tvalid && m_axis_cq_tready && (cq_len == 10'd1) &&
                        (cq_wr || cq_rd);
  wire [PIO_AW-1:0] cq_idx = m_axis_cq_tdata[2 +: PIO_AW];

  assign m_axis_cq_tready = pio_ready && (st_q == ST_CQ);
  assign s_axis_cc_tuser  = rivet_cc_tuser_pack(1'b0);
  assign s_axis_cc_tkeep  = 8'h3F;
  assign s_axis_cc_tlast  = 1'b1;
  assign s_axis_cc_tvalid = (st_q == ST_CC);

  always_comb begin
    s_axis_cc_tdata = '0;
    s_axis_cc_tdata[6:0]     = addr_q[6:0];
    s_axis_cc_tdata[27:16]   = 12'd4;
    s_axis_cc_tdata[41:32]   = 10'd1;
    s_axis_cc_tdata[45:43]   = 3'b000;
    s_axis_cc_tdata[71:64]   = tag_q;
    s_axis_cc_tdata[95:80]   = req_id_q;
    s_axis_cc_tdata[127:112] = 16'h0100;
    s_axis_cc_tdata[191:128] = {32'h0, pio_rd_q};
  end

  always_ff @(posedge clk_i) begin
    if (!pio_ready)
      pio_q[pio_init_q] <= '0;
    else if (we_q)
      pio_q[waddr_q] <= wdata_q;
    pio_rd_q <= pio_q[st_q == ST_CQ ? cq_idx : addr_q[2 +: PIO_AW]];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q       <= ST_CQ;
      pio_ready  <= 1'b0;
      pio_init_q <= '0;
      addr_q     <= '0;
      req_id_q   <= '0;
      tag_q      <= '0;
      we_q       <= 1'b0;
      waddr_q    <= '0;
      wdata_q    <= '0;
    end else if (!pio_ready) begin
      we_q <= 1'b0;
      if (pio_init_q == PIO_AW'(PIO_N - 1))
        pio_ready <= 1'b1;
      else
        pio_init_q <= pio_init_q + 1'b1;
    end else begin
      we_q <= 1'b0;
      unique case (st_q)
        ST_CQ: begin
          if (cq_one && cq_wr) begin
            we_q    <= 1'b1;
            waddr_q <= cq_idx;
            wdata_q <= m_axis_cq_tdata[159:128];
          end else if (cq_one && cq_rd) begin
            addr_q   <= {m_axis_cq_tdata[31:2], 2'b00};
            req_id_q <= m_axis_cq_tdata[111:96];
            tag_q    <= m_axis_cq_tdata[119:112];
            st_q     <= ST_RD;
          end
        end
        ST_RD: st_q <= ST_CC;
        ST_CC: begin
          if (s_axis_cc_tvalid && s_axis_cc_tready[0])
            st_q <= ST_CQ;
        end
        default: st_q <= ST_CQ;
      endcase
    end
  end

  wire unused_keep = |m_axis_cq_tkeep;
  wire unused_last = m_axis_cq_tlast;
  wire unused_user = |m_axis_cq_tuser;

endmodule : rivet_fpga_pio256
