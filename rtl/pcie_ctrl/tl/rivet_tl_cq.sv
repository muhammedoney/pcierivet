// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack BAR0 Mem32/Mem64 (and IO/Msg) TLPs into PG213-style 64-bit AXI-ST CQ.
// Mem64 BAR hit: addr_hi==0 and low 32 matches BAR0 (32-bit BAR aperture).

module rivet_tl_cq (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Internal DLL→TL byte stream (Cfg already filtered)
  input  logic [63:0] rx_tdata_i,
  input  logic [7:0]  rx_tkeep_i,
  input  logic        rx_tlast_i,
  input  logic        rx_tvalid_i,
  output logic        rx_tready_o,

  // BAR0 decode
  input  logic [31:0] bar0_base_i,
  input  logic [31:0] bar0_mask_i,
  input  logic        bar0_mem_en_i,

  // CQ NP credit (PG213)
  input  logic [1:0]  cq_np_req_i,
  output logic [5:0]  cq_np_req_count_o,

  // AXI-ST CQ (64-bit, dword keep)
  output logic [63:0] m_axis_cq_tdata,
  output logic [1:0]  m_axis_cq_tkeep,
  output logic        m_axis_cq_tlast,
  output logic        m_axis_cq_tvalid,
  input  logic        m_axis_cq_tready,
  output logic [87:0] m_axis_cq_tuser,

  // Credit pulse for TL
  output logic        rx_accept_o,
  output logic [7:0]  rx_hdr0_o,
  output logic [9:0]  rx_len_dw_o
);

  import rivet_pkg::*;

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_HDR1  = 3'd1,
    ST_HDR2  = 3'd2, // Mem64 second address beat
    ST_DESC0 = 3'd3,
    ST_DESC1 = 3'd4,
    ST_DATA  = 3'd5,
    ST_DROP  = 3'd6
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

  assign rx_tready_o = (st_q == ST_IDLE) || (st_q == ST_HDR1) || (st_q == ST_HDR2) ||
                       (st_q == ST_DROP) ||
                       ((st_q == ST_DATA) && !have_data_q);

  assign m_axis_cq_tvalid = ((st_q == ST_DESC0) || (st_q == ST_DESC1) ||
                             (st_q == ST_DATA && have_data_q)) && np_ok;
  assign m_axis_cq_tkeep  = 2'b11;
  assign m_axis_cq_tlast  = (st_q == ST_DESC1 && !is_wr_q) ||
                            (st_q == ST_DATA && have_data_q);
  assign m_axis_cq_tuser  = rivet_cq_tuser_pack(
      fbe_q, lbe_q,
      is_wr_q ? 32'h0000_000F : 32'h0,
      (st_q == ST_DESC0),
      1'b0);

  always_comb begin
    m_axis_cq_tdata = '0;
    unique case (st_q)
      ST_DESC0: begin
        m_axis_cq_tdata = {addr_hi_q, addr_lo_q[31:2], 2'b00};
      end
      ST_DESC1: begin
        m_axis_cq_tdata[10:0]  = {1'b0, len_q};
        m_axis_cq_tdata[14:11] = req_type_q;
        m_axis_cq_tdata[31:15] = '0;
        m_axis_cq_tdata[47:32] = req_id_q;
        m_axis_cq_tdata[55:48] = tag_q;
        m_axis_cq_tdata[63:56] = 8'h00;
      end
      ST_DATA: m_axis_cq_tdata = {32'h0, data_q};
      default: m_axis_cq_tdata = '0;
    endcase
  end

  assign rx_hdr0_o   = hdr0_q;
  assign rx_len_dw_o = (hdr0_q == RIVET_TLP_B0_MEMWR32 ||
                        hdr0_q == RIVET_TLP_B0_MEMWR64 ||
                        hdr0_q == RIVET_TLP_B0_IOWR ||
                        hdr0_q == RIVET_TLP_B0_MSGD) ?
                       ((len_q == 10'd0) ? 10'd1 : len_q) : 10'd0;
  assign rx_accept_o = (st_q == ST_DESC0) && m_axis_cq_tvalid && m_axis_cq_tready;

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
      if (!is_wr_q && (st_q == ST_DESC0) && m_axis_cq_tvalid && m_axis_cq_tready &&
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
              // Mem64: beat1 = {DW3=addr_lo, DW2=addr_hi}
              addr_hi_q <= le32(rx_tdata_i[31:0]);
              addr_lo_q <= le32(rx_tdata_i[63:32]);
              if (is_wr_q && !rx_tlast_i)
                st_q <= ST_HDR2; // data on following beat
              else begin
                have_data_q <= 1'b0;
                if ((le32(rx_tdata_i[31:0]) == 32'h0) &&
                    bar0_hit32(le32(rx_tdata_i[63:32])))
                  st_q <= ST_DESC0;
                else if (!rx_tlast_i)
                  st_q <= ST_DROP;
                else
                  st_q <= ST_IDLE;
              end
            end else begin
              // Mem32 / IO / Msg: beat1 low DW = address
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
                st_q <= ST_DESC0;
              else if (!rx_tlast_i)
                st_q <= ST_DROP;
              else
                st_q <= ST_IDLE;
            end
          end
        end
        ST_HDR2: begin
          // Mem64 write data beat (1 DW smoke)
          if (rx_tvalid_i && rx_tready_o) begin
            data_q      <= rx_tdata_i[31:0];
            have_data_q <= 1'b1;
            if ((addr_hi_q == 32'h0) && bar0_hit32(addr_lo_q))
              st_q <= ST_DESC0;
            else if (!rx_tlast_i)
              st_q <= ST_DROP;
            else
              st_q <= ST_IDLE;
          end
        end
        ST_DESC0: begin
          if (m_axis_cq_tvalid && m_axis_cq_tready)
            st_q <= ST_DESC1;
        end
        ST_DESC1: begin
          if (m_axis_cq_tvalid && m_axis_cq_tready) begin
            if (is_wr_q && have_data_q)
              st_q <= ST_DATA;
            else
              st_q <= ST_IDLE;
          end
        end
        ST_DATA: begin
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

endmodule : rivet_tl_cq
