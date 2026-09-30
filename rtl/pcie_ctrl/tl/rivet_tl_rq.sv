// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack PG213-style 64-bit AXI-ST Requester Request (RQ) into wire Mem32 TLP.

module rivet_tl_rq (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        bus_master_en_i,

  input  logic [63:0] s_axis_rq_tdata,
  input  logic [1:0]  s_axis_rq_tkeep,
  input  logic        s_axis_rq_tlast,
  input  logic        s_axis_rq_tvalid,
  output logic        s_axis_rq_tready,
  input  logic [84:0] s_axis_rq_tuser,

  output logic [63:0] tx_tdata_o,
  output logic [7:0]  tx_tkeep_o,
  output logic        tx_tlast_o,
  output logic        tx_tvalid_o,
  input  logic        tx_tready_i,

  output logic        tx_accept_o,
  output logic [7:0]  tx_hdr0_o,
  output logic [9:0]  tx_len_dw_o,

  // Companion: tag / sequence feedback (NP MemRd)
  output logic [5:0]  rq_seq_num_o,
  output logic        rq_seq_num_vld_o,
  output logic [9:0]  rq_tag_o,
  output logic        rq_tag_vld_o,
  output logic [3:0]  rq_tag_av_o,
  // Pulse from RC when a completion frees a tag slot
  input  logic        tag_free_i
);

  import rivet_pkg::*;

  typedef enum logic [2:0] {
    ST_D0  = 3'd0,
    ST_D1  = 3'd1,
    ST_DAT = 3'd2,
    ST_TX0 = 3'd3,
    ST_TX1 = 3'd4
  } st_e;

  st_e          st_q;
  logic [127:0] tx_q;
  logic         is_wr_q;
  logic [9:0]   len_q;
  logic [31:0]  addr_q;
  logic [7:0]   tag_q;
  logic [3:0]   fbe_q, lbe_q;
  logic [31:0]  data_q;
  logic [5:0]   seq_q;
  logic [3:0]   tag_av_q;

  assign s_axis_rq_tready = bus_master_en_i &&
                            ((st_q == ST_D0) || (st_q == ST_D1) || (st_q == ST_DAT));

  assign tx_tdata_o  = (st_q == ST_TX1) ? tx_q[127:64] : tx_q[63:0];
  assign tx_tkeep_o  = (st_q == ST_TX1) ? (is_wr_q ? 8'hFF : 8'h0F) : 8'hFF;
  assign tx_tlast_o  = (st_q == ST_TX1);
  assign tx_tvalid_o = (st_q == ST_TX0) || (st_q == ST_TX1);
  assign tx_hdr0_o   = tx_q[7:0];
  assign tx_len_dw_o = is_wr_q ? ((len_q == 10'd0) ? 10'd1 : len_q) : 10'd0;
  assign tx_accept_o = tx_tvalid_o && tx_tready_i && tx_tlast_o;

  assign rq_seq_num_o     = seq_q;
  assign rq_tag_o         = {2'b00, tag_q};
  assign rq_tag_av_o      = tag_av_q;
  assign rq_seq_num_vld_o = tx_accept_o;
  assign rq_tag_vld_o     = tx_accept_o && !is_wr_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q   <= ST_D0;
      tx_q   <= '0;
      is_wr_q <= 1'b0;
      len_q  <= '0;
      addr_q <= '0;
      tag_q  <= '0;
      fbe_q  <= '0;
      lbe_q  <= '0;
      data_q <= '0;
      seq_q  <= '0;
      tag_av_q <= 4'd8;
    end else begin
      if (tx_accept_o) begin
        seq_q <= seq_q + 6'd1;
        if (!is_wr_q && tag_av_q != 4'd0)
          tag_av_q <= tag_av_q - 4'd1;
      end else if (tag_free_i && tag_av_q < 4'd8) begin
        tag_av_q <= tag_av_q + 4'd1;
      end

      unique case (st_q)
        ST_D0: begin
          if (s_axis_rq_tvalid && s_axis_rq_tready) begin
            addr_q <= {s_axis_rq_tdata[31:2], 2'b00};
            fbe_q  <= s_axis_rq_tuser[3:0];
            lbe_q  <= s_axis_rq_tuser[7:4];
            st_q   <= ST_D1;
          end
        end
        ST_D1: begin
          if (s_axis_rq_tvalid && s_axis_rq_tready) begin
            len_q   <= s_axis_rq_tdata[9:0];
            is_wr_q <= (s_axis_rq_tdata[14:11] == RIVET_CQ_REQ_MEMWR);
            tag_q   <= s_axis_rq_tdata[55:48];
            if (s_axis_rq_tlast) begin
              // MemRd — build header only
              tx_q[7:0]   <= RIVET_TLP_B0_MEMRD32;
              tx_q[15:8]  <= 8'h00;
              tx_q[23:16] <= {6'h0, s_axis_rq_tdata[9:8]};
              tx_q[31:24] <= s_axis_rq_tdata[7:0];
              tx_q[39:32] <= 8'h00;                 // req id lo
              tx_q[47:40] <= 8'h01;                 // req id hi — EP bus=1
              tx_q[55:48] <= s_axis_rq_tdata[55:48]; // tag
              tx_q[59:56] <= fbe_q;
              tx_q[63:60] <= lbe_q;
              tx_q[71:64] <= addr_q[31:24];
              tx_q[79:72] <= addr_q[23:16];
              tx_q[87:80] <= addr_q[15:8];
              tx_q[95:88] <= addr_q[7:0];
              st_q <= ST_TX0;
            end else
              st_q <= ST_DAT;
          end
        end
        ST_DAT: begin
          if (s_axis_rq_tvalid && s_axis_rq_tready) begin
            data_q <= s_axis_rq_tdata[31:0];
            tx_q[7:0]   <= RIVET_TLP_B0_MEMWR32;
            tx_q[15:8]  <= 8'h00;
            tx_q[23:16] <= {6'h0, len_q[9:8]};
            tx_q[31:24] <= len_q[7:0];
            tx_q[39:32] <= 8'h00;
            tx_q[47:40] <= 8'h01;
            tx_q[55:48] <= tag_q;
            tx_q[59:56] <= fbe_q;
            tx_q[63:60] <= lbe_q;
            tx_q[71:64] <= addr_q[31:24];
            tx_q[79:72] <= addr_q[23:16];
            tx_q[87:80] <= addr_q[15:8];
            tx_q[95:88] <= addr_q[7:0];
            tx_q[103:96]  <= s_axis_rq_tdata[7:0];
            tx_q[111:104] <= s_axis_rq_tdata[15:8];
            tx_q[119:112] <= s_axis_rq_tdata[23:16];
            tx_q[127:120] <= s_axis_rq_tdata[31:24];
            st_q <= ST_TX0;
          end
        end
        ST_TX0: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        end
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_D0;
        end
        default: st_q <= ST_D0;
      endcase
    end
  end

  wire unused_keep = |s_axis_rq_tkeep;
  wire unused_data = |data_q;

endmodule : rivet_tl_rq
