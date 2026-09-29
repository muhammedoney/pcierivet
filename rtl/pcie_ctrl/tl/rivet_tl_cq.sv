// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack BAR0 Mem32 TLPs into PG213-style 64-bit AXI-ST Completer Request (CQ).

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
    ST_DESC0 = 3'd2,
    ST_DESC1 = 3'd3,
    ST_DATA  = 3'd4,
    ST_DROP  = 3'd5
  } st_e;

  st_e          st_q;
  logic [127:0] hdr_q;
  logic [7:0]   hdr0_q;
  logic [9:0]   len_q;
  logic [31:0]  addr_q;
  logic [15:0]  req_id_q;
  logic [7:0]   tag_q;
  logic [3:0]   fbe_q, lbe_q;
  logic         is_wr_q;
  logic [31:0]  data_q;
  logic         have_data_q;
  logic [5:0]   np_cnt_q;

  logic bar_hit;
  assign bar_hit = bar0_mem_en_i &&
                   ((addr_q & bar0_mask_i) == (bar0_base_i & bar0_mask_i));

  assign cq_np_req_count_o = np_cnt_q;

  logic np_ok;
  assign np_ok = is_wr_q || (np_cnt_q != 6'd0);

  assign rx_tready_o = (st_q == ST_IDLE) || (st_q == ST_HDR1) || (st_q == ST_DROP) ||
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
        // DW0: {addr[31:2], AT=00}; DW1: addr[63:32]=0
        m_axis_cq_tdata = {32'h0, addr_q[31:2], 2'b00};
      end
      ST_DESC1: begin
        // DW2: dword_count[10:0], req_type[14:11], attr/tc...
        // DW3: requester_id, tag, target_fn=0, bar_id=0, bar_aperture
        m_axis_cq_tdata[10:0]  = {1'b0, len_q};
        m_axis_cq_tdata[14:11] = is_wr_q ? RIVET_CQ_REQ_MEMWR : RIVET_CQ_REQ_MEMRD;
        m_axis_cq_tdata[31:15] = '0;
        m_axis_cq_tdata[47:32] = req_id_q;
        m_axis_cq_tdata[55:48] = tag_q;
        m_axis_cq_tdata[63:56] = 8'h00; // target function / BAR id low
        // BAR aperture: log2(size)-1 → 64KiB → 15; encode in [69:64] of 128b = tdata high nibble side — keep 0 for smoke
      end
      ST_DATA: m_axis_cq_tdata = {32'h0, data_q};
      default: m_axis_cq_tdata = '0;
    endcase
  end

  assign rx_hdr0_o   = hdr0_q;
  assign rx_len_dw_o = (hdr0_q == RIVET_TLP_B0_MEMWR32) ?
                       ((len_q == 10'd0) ? 10'd1 : len_q) : 10'd0;
  assign rx_accept_o = (st_q == ST_DESC0) && m_axis_cq_tvalid && m_axis_cq_tready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q        <= ST_IDLE;
      hdr_q       <= '0;
      hdr0_q      <= '0;
      len_q       <= '0;
      addr_q      <= '0;
      req_id_q    <= '0;
      tag_q       <= '0;
      fbe_q       <= '0;
      lbe_q       <= '0;
      is_wr_q     <= 1'b0;
      data_q      <= '0;
      have_data_q <= 1'b0;
      np_cnt_q    <= 6'd8;
    end else begin
      // NP credit: app grants via cq_np_req; consume on MemRd sop accept
      if (cq_np_req_i != 2'b00 && np_cnt_q != 6'h3F)
        np_cnt_q <= np_cnt_q + 6'(cq_np_req_i);
      if (!is_wr_q && (st_q == ST_DESC0) && m_axis_cq_tvalid && m_axis_cq_tready &&
          (np_cnt_q != 6'd0))
        np_cnt_q <= np_cnt_q - 6'd1;

      unique case (st_q)
        ST_IDLE: begin
          if (rx_tvalid_i && rx_tready_o) begin
            hdr_q[63:0] <= rx_tdata_i;
            hdr0_q      <= rx_tdata_i[7:0];
            len_q       <= rivet_tlp_len_dw(rx_tdata_i[23:16], rx_tdata_i[31:24]);
            req_id_q    <= {rx_tdata_i[47:40], rx_tdata_i[39:32]};
            tag_q       <= rx_tdata_i[55:48];
            fbe_q       <= rx_tdata_i[59:56];
            lbe_q       <= rx_tdata_i[63:60];
            is_wr_q     <= (rx_tdata_i[7:0] == RIVET_TLP_B0_MEMWR32);
            if ((rx_tdata_i[7:0] == RIVET_TLP_B0_MEMRD32) ||
                (rx_tdata_i[7:0] == RIVET_TLP_B0_MEMWR32))
              st_q <= ST_HDR1;
            else if (!rx_tlast_i)
              st_q <= ST_DROP;
            // else ignore single-beat non-mem
          end
        end
        ST_HDR1: begin
          if (rx_tvalid_i && rx_tready_o) begin
            addr_q <= {rx_tdata_i[7:0], rx_tdata_i[15:8],
                       rx_tdata_i[23:16], rx_tdata_i[31:24]};
            if (is_wr_q) begin
              data_q      <= rx_tdata_i[63:32];
              have_data_q <= 1'b1;
            end else
              have_data_q <= 1'b0;
            // Evaluate BAR hit with address about to be registered — use comb from bus
            if (bar0_mem_en_i &&
                (({rx_tdata_i[7:0], rx_tdata_i[15:8],
                   rx_tdata_i[23:16], rx_tdata_i[31:24]} & bar0_mask_i) ==
                 (bar0_base_i & bar0_mask_i)))
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
  wire unused_hit  = bar_hit;

endmodule : rivet_tl_cq
