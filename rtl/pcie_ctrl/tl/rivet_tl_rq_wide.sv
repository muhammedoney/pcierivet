// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack a PG213-style 128-bit AXI-ST Requester Request into DLL beats.
// One descriptor beat carries both 64-bit halves. MemWr64 then streams
// 16 payload bytes per accepted user beat. MemWr32 still puts DW0 in the
// 16-byte head. MemRd is the header beat with tlast. Gen2 does not use
// this module.

module rivet_tl_rq_wide #(
  parameter int unsigned MODE = 0
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic         bus_master_en_i,
  input  logic [7:0]   primary_bus_i = 8'h00,

  input  logic [127:0] s_axis_rq_tdata,
  input  logic [3:0]   s_axis_rq_tkeep,
  input  logic         s_axis_rq_tlast,
  input  logic         s_axis_rq_tvalid,
  output logic         s_axis_rq_tready,
  input  logic [84:0]  s_axis_rq_tuser,

  output logic [127:0] tx_tdata_o,
  output logic [15:0]  tx_tkeep_o,
  output logic         tx_tlast_o,
  output logic         tx_tvalid_o,
  input  logic         tx_tready_i,

  output logic         tx_accept_o,
  output logic [7:0]   tx_hdr0_o,
  output logic [9:0]   tx_len_dw_o,

  output logic [5:0]   rq_seq_num_o,
  output logic         rq_seq_num_vld_o,
  output logic [9:0]   rq_tag_o,
  output logic         rq_tag_vld_o,
  output logic [3:0]   rq_tag_av_o,
  input  logic         tag_free_i
);

  import rivet_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_DW0  = 2'd1,
    ST_PAY  = 2'd2,
    ST_TAIL = 2'd3
  } st_e;

  st_e          st_q;
  logic [127:0] tx_d_q;
  logic [15:0]  tx_k_q;
  logic         tx_l_q, tx_v_q;
  logic         is_wr_q, is64_q;
  logic [9:0]   len_q;
  logic [7:0]   tag_q, hdr0_q;
  logic [5:0]   seq_q;
  logic [3:0]   tag_av_q;
  logic [127:0] res_q;
  logic [4:0]   res_n_q;

  logic         slot_free;
  logic         accept;

  assign tx_tvalid_o      = tx_v_q;
  assign tx_tdata_o       = tx_d_q;
  assign tx_tkeep_o       = tx_k_q;
  assign tx_tlast_o       = tx_l_q;
  assign tx_accept_o      = tx_v_q && tx_tready_i && tx_l_q;
  assign tx_hdr0_o        = hdr0_q;
  assign tx_len_dw_o      = is_wr_q ? len_q : 10'd0;
  assign rq_seq_num_o     = seq_q;
  assign rq_seq_num_vld_o = tx_accept_o;
  assign rq_tag_o         = {2'b00, tag_q};
  assign rq_tag_vld_o     = tx_accept_o && !is_wr_q;
  assign rq_tag_av_o      = tag_av_q;

  assign slot_free = !tx_v_q || tx_tready_i;
  assign s_axis_rq_tready = bus_master_en_i && slot_free &&
                            ((st_q == ST_IDLE) || (st_q == ST_DW0) ||
                             ((st_q == ST_PAY) && (res_n_q < 5'd16)));
  assign accept = s_axis_rq_tvalid && s_axis_rq_tready;

  function automatic logic [15:0] keep16(input logic [4:0] n);
    logic [15:0] k;
    k = '0;
    for (int unsigned i = 0; i < 16; i++)
      if (5'(i) < n)
        k[i] = 1'b1;
    return k;
  endfunction

  function automatic logic [4:0] keep_nbytes4(input logic [3:0] k);
    logic [4:0] n;
    n = '0;
    for (int unsigned i = 0; i < 4; i++)
      if (k[i])
        n = n + 5'd4;
    return n;
  endfunction

  // 12-byte or 16-byte header in the same byte order as rivet_tl_rq.
  function automatic logic [127:0] build_hdr(
      input logic [7:0]  b0,
      input logic [9:0]  len,
      input logic [7:0]  tag,
      input logic [3:0]  fbe,
      input logic [3:0]  lbe,
      input logic [31:0] addr,
      input logic [31:0] addr_hi,
      input logic        is64);
    logic [127:0] h;
    h          = '0;
    h[7:0]     = b0;
    h[23:16]   = {6'h0, len[9:8]};
    h[31:24]   = len[7:0];
    h[39:32]   = 8'h00;
    h[47:40]   = 8'h01;
    h[55:48]   = tag;
    h[59:56]   = fbe;
    h[63:60]   = lbe;
    if (is64) begin
      h[71:64]   = addr_hi[31:24];
      h[79:72]   = addr_hi[23:16];
      h[87:80]   = addr_hi[15:8];
      h[95:88]   = addr_hi[7:0];
      h[103:96]  = addr[31:24];
      h[111:104] = addr[23:16];
      h[119:112] = addr[15:8];
      h[127:120] = addr[7:0];
    end else begin
      h[71:64] = addr[31:24];
      h[79:72] = addr[23:16];
      h[87:80] = addr[15:8];
      h[95:88] = addr[7:0];
    end
    return h;
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q     <= ST_IDLE;
      tx_d_q   <= '0;
      tx_k_q   <= '0;
      tx_l_q   <= 1'b0;
      tx_v_q   <= 1'b0;
      is_wr_q  <= 1'b0;
      is64_q   <= 1'b0;
      len_q    <= '0;
      tag_q    <= '0;
      hdr0_q   <= '0;
      seq_q    <= '0;
      tag_av_q <= 4'd8;
      res_q    <= '0;
      res_n_q  <= '0;
    end else begin
      if (tx_v_q && tx_tready_i)
        tx_v_q <= 1'b0;

      if (tx_accept_o) begin
        seq_q <= seq_q + 6'd1;
        if (!is_wr_q && (tag_av_q != 4'd0))
          tag_av_q <= tag_av_q - 4'd1;
      end else if (tag_free_i && (tag_av_q < 4'd8)) begin
        tag_av_q <= tag_av_q + 4'd1;
      end

      unique case (st_q)
        ST_IDLE: begin
          if (accept) begin
            logic [63:0] b0, b1;
            logic [31:0] addr, addr_hi;
            logic [9:0]  len;
            logic [7:0]  tag;
            logic [3:0]  req, fbe, lbe;
            logic        is64, is_wr;
            logic [7:0]  b0t;
            b0      = s_axis_rq_tdata[63:0];
            b1      = s_axis_rq_tdata[127:64];
            addr    = {b0[31:2], 2'b00};
            addr_hi = b0[63:32];
            len     = b1[9:0];
            req     = b1[14:11];
            tag     = b1[39:32];
            fbe     = s_axis_rq_tuser[3:0];
            lbe     = s_axis_rq_tuser[7:4];
            is64    = (addr_hi != 32'h0);
            is_wr   = (req == RIVET_CQ_REQ_MEMWR);
            b0t     = is_wr ? (is64 ? RIVET_TLP_B0_MEMWR64 : RIVET_TLP_B0_MEMWR32)
                            : (is64 ? RIVET_TLP_B0_MEMRD64 : RIVET_TLP_B0_MEMRD32);
            is_wr_q <= is_wr;
            is64_q  <= is64;
            len_q   <= len;
            tag_q   <= tag;
            hdr0_q  <= b0t;
            res_q   <= '0;
            res_n_q <= '0;
            if (!is_wr || s_axis_rq_tlast) begin
              tx_d_q <= build_hdr(b0t, len, tag, fbe, lbe, addr, addr_hi, is64);
              tx_k_q <= is64 ? 16'hFFFF : 16'h0FFF;
              tx_l_q <= 1'b1;
              tx_v_q <= 1'b1;
              st_q   <= ST_IDLE;
            end else if (is64) begin
              tx_d_q <= build_hdr(b0t, len, tag, fbe, lbe, addr, addr_hi, 1'b1);
              tx_k_q <= 16'hFFFF;
              tx_l_q <= 1'b0;
              tx_v_q <= 1'b1;
              st_q   <= ST_PAY;
            end else begin
              // MemWr32: DW0 of the next beat completes the 16-byte head.
              tx_d_q <= build_hdr(b0t, len, tag, fbe, lbe, addr, addr_hi, 1'b0);
              st_q   <= ST_DW0;
            end
          end
        end
        ST_DW0: begin
          if (accept) begin
            logic [4:0] nb;
            logic [4:0] extra;
            nb    = keep_nbytes4(s_axis_rq_tkeep);
            extra = (nb > 5'd4) ? (nb - 5'd4) : 5'd0;
            tx_d_q[127:96] <= s_axis_rq_tdata[31:0];
            tx_k_q         <= 16'hFFFF;
            tx_v_q         <= 1'b1;
            if (extra == 5'd0) begin
              tx_l_q  <= s_axis_rq_tlast;
              res_n_q <= '0;
              st_q    <= s_axis_rq_tlast ? ST_IDLE : ST_PAY;
            end else begin
              tx_l_q <= 1'b0;
              for (int unsigned i = 0; i < 12; i++)
                res_q[8*i +: 8] <= s_axis_rq_tdata[8*(i + 4) +: 8];
              res_n_q <= extra;
              st_q    <= s_axis_rq_tlast ? ST_TAIL : ST_PAY;
            end
          end
        end
        ST_PAY: begin
          if (is64_q) begin
            if (accept) begin
              logic [4:0] nb;
              nb     = keep_nbytes4(s_axis_rq_tkeep);
              tx_d_q <= s_axis_rq_tdata;
              tx_k_q <= keep16(nb);
              tx_l_q <= s_axis_rq_tlast;
              tx_v_q <= 1'b1;
              if (s_axis_rq_tlast)
                st_q <= ST_IDLE;
            end
          end else if (accept) begin
            logic [4:0]   nb;
            logic [5:0]   sum;
            logic [255:0] wide;
            nb   = keep_nbytes4(s_axis_rq_tkeep);
            wide = {128'h0, res_q};
            for (int unsigned i = 0; i < 16; i++) begin
              if (5'(i) < nb)
                wide[8*(32'(res_n_q) + i) +: 8] = s_axis_rq_tdata[8*i +: 8];
            end
            sum = {1'b0, res_n_q} + {1'b0, nb};
            if (sum >= 6'd16) begin
              tx_d_q  <= wide[127:0];
              tx_k_q  <= 16'hFFFF;
              tx_v_q  <= 1'b1;
              res_q   <= wide[255:128];
              res_n_q <= 5'(sum - 6'd16);
              if (s_axis_rq_tlast && (sum == 6'd16)) begin
                tx_l_q <= 1'b1;
                st_q   <= ST_IDLE;
              end else begin
                tx_l_q <= 1'b0;
                if (s_axis_rq_tlast)
                  st_q <= ST_TAIL;
              end
            end else if (s_axis_rq_tlast) begin
              res_q   <= wide[127:0];
              res_n_q <= sum[4:0];
              st_q    <= ST_TAIL;
            end else begin
              res_q   <= wide[127:0];
              res_n_q <= sum[4:0];
            end
          end
        end
        ST_TAIL: begin
          if (slot_free && (res_n_q != 5'd0)) begin
            tx_d_q  <= res_q[127:0];
            tx_k_q  <= keep16(res_n_q);
            tx_l_q  <= 1'b1;
            tx_v_q  <= 1'b1;
            res_q   <= '0;
            res_n_q <= '0;
            st_q    <= ST_IDLE;
          end else if (res_n_q == 5'd0) begin
            st_q <= ST_IDLE;
          end
        end
        default: st_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_tl_rq_wide
