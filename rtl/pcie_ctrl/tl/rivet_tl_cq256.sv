// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack BAR0 Mem TLPs into one 256-bit CQ beat.
// Field order matches rivet_tl_cq: DESC0, DESC1, then {32'h0, data}.

module rivet_tl_cq256 (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [63:0] rx_tdata_i,
  input  logic [7:0]  rx_tkeep_i,
  input  logic        rx_tlast_i,
  input  logic        rx_tvalid_i,
  output logic        rx_tready_o,

  input  logic [31:0] bar0_base_i,
  input  logic [31:0] bar0_mask_i,
  input  logic        bar0_mem_en_i,

  input  logic [1:0]  cq_np_req_i,
  output logic [5:0]  cq_np_req_count_o,

  output logic [255:0] m_axis_cq_tdata,
  output logic [7:0]   m_axis_cq_tkeep,
  output logic         m_axis_cq_tlast,
  output logic         m_axis_cq_tvalid,
  input  logic         m_axis_cq_tready,
  output logic [87:0]  m_axis_cq_tuser,

  output logic        rx_accept_o,
  output logic [7:0]  rx_hdr0_o,
  output logic [9:0]  rx_len_dw_o
);

  import rivet_pkg::*;

  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_HDR1 = 3'd1,
    ST_HDR2 = 3'd2,
    ST_BEAT = 3'd3,
    ST_DROP = 3'd4
  } st_e;

  st_e          st_q;
  logic [7:0]   hdr0_q;
  logic [9:0]   len_q;
  logic [31:0]  addr_lo_q;
  logic [31:0]  addr_hi_q;
  logic [15:0]  req_id_q;
  logic [7:0]   tag_q;
  logic [3:0]   fbe_q, lbe_q;
  logic         is_wr_q;
  logic         is_64_q;
  logic [3:0]   req_type_q;
  logic [31:0]  data_q;
  logic         have_data_q;
  logic [5:0]   np_cnt_q;

  function automatic logic [31:0] le32(input logic [31:0] w);
    return {w[7:0], w[15:8], w[23:16], w[31:24]};
  endfunction

  function automatic logic bar0_hit32(input logic [31:0] a);
    return bar0_mem_en_i && ((a & bar0_mask_i) == (bar0_base_i & bar0_mask_i));
  endfunction

  assign cq_np_req_count_o = np_cnt_q;

  logic np_ok;
  assign np_ok = is_wr_q || (np_cnt_q != 6'd0);

  assign rx_tready_o = (st_q == ST_IDLE) || (st_q == ST_HDR1) ||
                       (st_q == ST_HDR2) || (st_q == ST_DROP);

  assign m_axis_cq_tvalid = (st_q == ST_BEAT) && np_ok;
  assign m_axis_cq_tlast  = 1'b1;
  assign m_axis_cq_tkeep  = (is_wr_q && have_data_q) ? 8'h3F : 8'h0F;
  assign m_axis_cq_tuser  = rivet_cq_tuser_pack(
      fbe_q, lbe_q, is_wr_q ? 32'h0000_000F : 32'h0, 1'b1, 1'b0);
  assign m_axis_cq_tdata  = {64'h0,
                             (is_wr_q && have_data_q) ? {32'h0, data_q} : 64'h0,
                             {8'h00, tag_q, req_id_q, 17'h0, req_type_q, 1'b0, len_q},
                             {addr_hi_q, addr_lo_q[31:2], 2'b00}};

  assign rx_hdr0_o   = hdr0_q;
  assign rx_len_dw_o = (hdr0_q == RIVET_TLP_B0_MEMWR32 ||
                        hdr0_q == RIVET_TLP_B0_MEMWR64 ||
                        hdr0_q == RIVET_TLP_B0_IOWR ||
                        hdr0_q == RIVET_TLP_B0_MSGD) ?
                       ((len_q == 10'd0) ? 10'd1 : len_q) : 10'd0;
  assign rx_accept_o = (st_q == ST_BEAT) && m_axis_cq_tvalid && m_axis_cq_tready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q        <= ST_IDLE;
      hdr0_q      <= '0;
      len_q       <= '0;
      addr_lo_q   <= '0;
      addr_hi_q   <= '0;
      req_id_q    <= '0;
      tag_q       <= '0;
      fbe_q       <= '0;
      lbe_q       <= '0;
      is_wr_q     <= 1'b0;
      is_64_q     <= 1'b0;
      req_type_q  <= RIVET_CQ_REQ_MEMRD;
      data_q      <= '0;
      have_data_q <= 1'b0;
      np_cnt_q    <= 6'd8;
    end else begin
      if (cq_np_req_i != 2'b00 && np_cnt_q != 6'h3F)
        np_cnt_q <= np_cnt_q + 6'(cq_np_req_i);
      if (!is_wr_q && (st_q == ST_BEAT) && m_axis_cq_tvalid && m_axis_cq_tready &&
          (np_cnt_q != 6'd0))
        np_cnt_q <= np_cnt_q - 6'd1;

      unique case (st_q)
        ST_IDLE: begin
          if (rx_tvalid_i && rx_tready_o) begin
            automatic logic [7:0] b0 = rx_tdata_i[7:0];
            hdr0_q   <= b0;
            len_q    <= rivet_tlp_len_dw(rx_tdata_i[23:16], rx_tdata_i[31:24]);
            req_id_q <= {rx_tdata_i[47:40], rx_tdata_i[39:32]};
            tag_q    <= rx_tdata_i[55:48];
            fbe_q    <= rx_tdata_i[59:56];
            lbe_q    <= rx_tdata_i[63:60];
            is_64_q  <= (b0 == RIVET_TLP_B0_MEMRD64) || (b0 == RIVET_TLP_B0_MEMWR64);
            is_wr_q  <= (b0 == RIVET_TLP_B0_MEMWR32) || (b0 == RIVET_TLP_B0_MEMWR64) ||
                        (b0 == RIVET_TLP_B0_IOWR) || (b0 == RIVET_TLP_B0_MSGD);
            unique case (b0)
              RIVET_TLP_B0_MEMWR32, RIVET_TLP_B0_MEMWR64: req_type_q <= RIVET_CQ_REQ_MEMWR;
              RIVET_TLP_B0_IORD:                          req_type_q <= RIVET_CQ_REQ_IORD;
              RIVET_TLP_B0_IOWR:                          req_type_q <= RIVET_CQ_REQ_IOWR;
              RIVET_TLP_B0_MSG, RIVET_TLP_B0_MSGD:        req_type_q <= RIVET_CQ_REQ_MSG;
              default:                                    req_type_q <= RIVET_CQ_REQ_MEMRD;
            endcase
            if ((b0 == RIVET_TLP_B0_MEMRD32) || (b0 == RIVET_TLP_B0_MEMWR32) ||
                (b0 == RIVET_TLP_B0_MEMRD64) || (b0 == RIVET_TLP_B0_MEMWR64) ||
                (b0 == RIVET_TLP_B0_IORD) || (b0 == RIVET_TLP_B0_IOWR) ||
                (b0 == RIVET_TLP_B0_MSG) || (b0 == RIVET_TLP_B0_MSGD))
              st_q <= ST_HDR1;
            else if (!rx_tlast_i)
              st_q <= ST_DROP;
          end
        end
        ST_HDR1: begin
          if (rx_tvalid_i && rx_tready_o) begin
            if (is_64_q) begin
              addr_hi_q <= le32(rx_tdata_i[31:0]);
              addr_lo_q <= le32(rx_tdata_i[63:32]);
              if (is_wr_q && !rx_tlast_i)
                st_q <= ST_HDR2;
              else begin
                have_data_q <= 1'b0;
                if ((le32(rx_tdata_i[31:0]) == 32'h0) &&
                    bar0_hit32(le32(rx_tdata_i[63:32])))
                  st_q <= ST_BEAT;
                else if (!rx_tlast_i)
                  st_q <= ST_DROP;
                else
                  st_q <= ST_IDLE;
              end
            end else begin
              addr_hi_q <= 32'h0;
              addr_lo_q <= le32(rx_tdata_i[31:0]);
              if (is_wr_q) begin
                data_q      <= rx_tdata_i[63:32];
                have_data_q <= 1'b1;
              end else
                have_data_q <= 1'b0;
              if ((hdr0_q == RIVET_TLP_B0_MSG) || (hdr0_q == RIVET_TLP_B0_MSGD) ||
                  (hdr0_q == RIVET_TLP_B0_IORD) || (hdr0_q == RIVET_TLP_B0_IOWR) ||
                  bar0_hit32(le32(rx_tdata_i[31:0])))
                st_q <= ST_BEAT;
              else if (!rx_tlast_i)
                st_q <= ST_DROP;
              else
                st_q <= ST_IDLE;
            end
          end
        end
        ST_HDR2: begin
          if (rx_tvalid_i && rx_tready_o) begin
            data_q      <= rx_tdata_i[31:0];
            have_data_q <= 1'b1;
            if ((addr_hi_q == 32'h0) && bar0_hit32(addr_lo_q))
              st_q <= ST_BEAT;
            else if (!rx_tlast_i)
              st_q <= ST_DROP;
            else
              st_q <= ST_IDLE;
          end
        end
        ST_BEAT: begin
          if (m_axis_cq_tvalid && m_axis_cq_tready) begin
            have_data_q <= 1'b0;
            st_q <= ST_IDLE;
          end
        end
        ST_DROP: begin
          if (rx_tvalid_i && rx_tready_o && rx_tlast_i)
            st_q <= ST_IDLE;
        end
        default: st_q <= ST_IDLE;
      endcase
    end
  end

  wire unused_keep = |rx_tkeep_i;

endmodule : rivet_tl_cq256
