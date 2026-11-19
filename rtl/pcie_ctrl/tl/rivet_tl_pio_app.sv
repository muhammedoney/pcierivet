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
  // Block RAM. A 256:1 flip-flop read does not close at Gen2 pclk.
  localparam int unsigned PIO_AW = (PIO_N <= 1) ? 1 : $clog2(PIO_N);
  (* ram_style = "block" *) logic [31:0] pio_q [0:PIO_N-1];
  logic [31:0]       pio_rd_q;
  logic [PIO_AW-1:0] pio_raddr;
  logic              pio_ready;
  logic [PIO_AW-1:0] pio_init_q;
  logic              pio_we_lo;
  logic              pio_we_hi;
  logic [PIO_AW-1:0] pio_addr_lo;
  logic [PIO_AW-1:0] pio_addr_hi;
  logic [31:0]       pio_data_lo;
  logic [31:0]       pio_data_hi;

  assign m_axis_cq_tready = pio_ready &&
      ((st_q == ST_CQ0) || (st_q == ST_CQ1) || (st_q == ST_CQD));
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
      ST_CCD: s_axis_cc_tdata = {32'h0, pio_rd_q};
      default: ;
    endcase
  end

  always_comb begin
    pio_raddr   = addr_q[2 +: PIO_AW];
    pio_we_lo   = 1'b0;
    pio_we_hi   = 1'b0;
    pio_addr_lo = addr_q[2 +: PIO_AW];
    pio_addr_hi = PIO_AW'(addr_q[2 +: PIO_AW] + 1'b1);
    pio_data_lo = m_axis_cq_tdata[31:0];
    pio_data_hi = m_axis_cq_tdata[63:32];
    if ((st_q == ST_CCD) && (rem_q > 10'd1))
      pio_raddr = PIO_AW'(addr_q[2 +: PIO_AW] + 1'b1);
    if (pio_ready && (st_q == ST_CQD) && m_axis_cq_tvalid && m_axis_cq_tready) begin
      if (rem_q != 10'd0)
        pio_we_lo = 1'b1;
      if ((rem_q > 10'd1) && m_axis_cq_tkeep[1])
        pio_we_hi = 1'b1;
    end
  end

  // Port A has no reset. An async reset on this process blocks block RAM.
  logic              pio_we_a;
  logic [PIO_AW-1:0] pio_waddr_a;
  logic [31:0]       pio_wdata_a;

  always_comb begin
    pio_we_a    = 1'b0;
    pio_waddr_a = pio_init_q;
    pio_wdata_a = '0;
    if (!pio_ready)
      pio_we_a = 1'b1;
    else if (pio_we_lo) begin
      pio_we_a    = 1'b1;
      pio_waddr_a = pio_addr_lo;
      pio_wdata_a = pio_data_lo;
    end
  end

  always_ff @(posedge clk_i) begin
    if (pio_we_a)
      pio_q[pio_waddr_a] <= pio_wdata_a;
    pio_rd_q <= pio_q[pio_raddr];
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni && pio_we_hi)
      pio_q[pio_addr_hi] <= pio_data_hi;
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
      fbe_q       <= '0;
      pio_ready   <= 1'b0;
      pio_init_q  <= '0;
    end else if (!pio_ready) begin
      if (pio_init_q == PIO_AW'(PIO_N - 1))
        pio_ready <= 1'b1;
      else
        pio_init_q <= pio_init_q + 1'b1;
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
              waddr = waddr + 32'd4;
              wrem  = wrem - 10'd1;
            end
            if (wrem != 10'd0 && m_axis_cq_tkeep[1]) begin
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
          if (s_axis_cc_tvalid && s_axis_cc_tready[0])
            st_q <= ST_CC1;
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
