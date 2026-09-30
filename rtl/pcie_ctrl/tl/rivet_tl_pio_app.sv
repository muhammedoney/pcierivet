// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// BAR0 Mem32 PIO on CQ/CC. Supports multi-DW MemWr/MemRd (Class B).

module rivet_tl_pio_app #(
  parameter int unsigned PIO_N = 256
) (
  input  logic        clk_i,
  input  logic        rst_ni,

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
  output logic [32:0] s_axis_cc_tuser
);

  import rivet_pkg::*;

  typedef enum logic [2:0] {
    ST_CQ0  = 3'd0,
    ST_CQ1  = 3'd1,
    ST_CQD  = 3'd2,
    ST_CC0  = 3'd3,
    ST_CC1  = 3'd4,
    ST_CCD  = 3'd5
  } st_e;

  st_e          st_q;
  logic [31:0]  addr_q;
  logic [15:0]  req_id_q;
  logic [7:0]   tag_q;
  logic [9:0]   len_q;
  logic [9:0]   rem_q;
  logic         is_wr_q;
  logic [3:0]   fbe_q;
  logic [31:0]  data_q;
  logic [31:0]  pio_q [0:PIO_N-1];

  assign m_axis_cq_tready = (st_q == ST_CQ0) || (st_q == ST_CQ1) || (st_q == ST_CQD);
  assign s_axis_cc_tuser  = rivet_cc_tuser_pack(1'b0);
  assign s_axis_cc_tkeep  = 2'b11;
  assign s_axis_cc_tvalid = (st_q == ST_CC0) || (st_q == ST_CC1) || (st_q == ST_CCD);
  assign s_axis_cc_tlast  = (st_q == ST_CC1 && !is_wr_q && rem_q == 10'd0) ||
                            (st_q == ST_CCD && rem_q <= 10'd1);

  always_comb begin
    s_axis_cc_tdata = '0;
    unique case (st_q)
      ST_CC0: begin
        s_axis_cc_tdata[6:0]   = addr_q[6:0];
        s_axis_cc_tdata[27:16] = {len_q, 2'b00}; // byte count = 4*DW
        s_axis_cc_tdata[41:32] = len_q;
        s_axis_cc_tdata[45:43] = 3'b000; // SC
      end
      ST_CC1: begin
        s_axis_cc_tdata[7:0]   = tag_q;
        s_axis_cc_tdata[31:16] = req_id_q;
        s_axis_cc_tdata[63:48] = 16'h0100; // completer ID
      end
      ST_CCD: s_axis_cc_tdata = {32'h0, data_q};
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q     <= ST_CQ0;
      addr_q   <= '0;
      req_id_q <= '0;
      tag_q    <= '0;
      len_q    <= '0;
      rem_q    <= '0;
      is_wr_q  <= 1'b0;
      fbe_q    <= '0;
      data_q   <= '0;
      for (int unsigned i = 0; i < PIO_N; i++) pio_q[i] <= '0;
    end else begin
      unique case (st_q)
        ST_CQ0: begin
          if (m_axis_cq_tvalid && m_axis_cq_tready) begin
            addr_q <= {m_axis_cq_tdata[31:2], 2'b00};
            fbe_q  <= rivet_cq_tuser_first_be(m_axis_cq_tuser);
            st_q   <= ST_CQ1;
          end
        end
        ST_CQ1: begin
          if (m_axis_cq_tvalid && m_axis_cq_tready) begin
            len_q    <= m_axis_cq_tdata[9:0];
            rem_q    <= m_axis_cq_tdata[9:0];
            is_wr_q  <= (m_axis_cq_tdata[14:11] == RIVET_CQ_REQ_MEMWR);
            req_id_q <= m_axis_cq_tdata[47:32];
            tag_q    <= m_axis_cq_tdata[55:48];
            if (m_axis_cq_tlast) begin
              // MemRd — no data beat
              st_q <= ST_CC0;
            end else
              st_q <= ST_CQD;
          end
        end
        ST_CQD: begin
          if (m_axis_cq_tvalid && m_axis_cq_tready) begin
            automatic logic [31:0] waddr = addr_q;
            automatic logic [9:0]  wrem  = rem_q;
            // 64-bit CQ: up to two DW per beat
            if (wrem != 10'd0) begin
              pio_q[waddr[9:2]] <= m_axis_cq_tdata[31:0];
              waddr = waddr + 32'd4;
              wrem  = wrem - 10'd1;
            end
            if (wrem != 10'd0 && m_axis_cq_tkeep[1]) begin
              pio_q[waddr[9:2]] <= m_axis_cq_tdata[63:32];
              waddr = waddr + 32'd4;
              wrem  = wrem - 10'd1;
            end
            addr_q <= waddr;
            rem_q  <= wrem;
            if (m_axis_cq_tlast || wrem == 10'd0)
              st_q <= ST_CQ0; // Posted write — no completion
            else
              st_q <= ST_CQD;
          end
        end
        ST_CC0: begin
          if (s_axis_cc_tvalid && s_axis_cc_tready[0]) begin
            data_q <= pio_q[addr_q[9:2]];
            st_q   <= ST_CC1;
          end
        end
        ST_CC1: begin
          if (s_axis_cc_tvalid && s_axis_cc_tready[0]) begin
            if (rem_q == 10'd0)
              st_q <= ST_CQ0; // zero-length (should not happen)
            else
              st_q <= ST_CCD;
          end
        end
        ST_CCD: begin
          if (s_axis_cc_tvalid && s_axis_cc_tready[0]) begin
            if (rem_q <= 10'd1) begin
              rem_q <= 10'd0;
              st_q  <= ST_CQ0;
            end else begin
              automatic logic [31:0] naddr = addr_q + 32'd4;
              addr_q <= naddr;
              rem_q  <= rem_q - 10'd1;
              data_q <= pio_q[naddr[9:2]];
              st_q   <= ST_CCD;
            end
          end
        end
        default: st_q <= ST_CQ0;
      endcase
    end
  end

  wire unused_keep = |m_axis_cq_tkeep;
  wire unused_fbe  = |fbe_q;

endmodule : rivet_tl_pio_app
