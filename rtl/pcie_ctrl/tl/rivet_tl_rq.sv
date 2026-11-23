// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack PG213-style 64-bit AXI-ST Requester Request (RQ) into a wire Mem32 TLP.
// A 1DW write is still two TX beats. Longer writes keep that 16-byte head
// (header + DW0) and then stream the rest, 8 bytes per beat. A descriptor
// length of 0 is 1024 DW (4096-byte Max Payload).

module rivet_tl_rq #(
  parameter int unsigned MODE = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        bus_master_en_i,
  // Requester ID bus byte for config TLPs. Memory TLPs keep the EP encoding.
  input  logic [7:0]  primary_bus_i = 8'h00,

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
    ST_D0   = 3'd0,
    ST_D1   = 3'd1,
    ST_DAT  = 3'd2,
    ST_TX0  = 3'd3,
    ST_TX1  = 3'd4,
    ST_MORE = 3'd5
  } st_e;

  st_e          st_q;
  logic [127:0] tx_q;
  logic         is_wr_q;
  logic         is_cfg_q;
  logic [7:0]   cfg_b0_q;
  logic [15:0]  cfg_cpl_q;
  logic [9:0]   len_q;
  // PCIe length 0 means 1024 DW. dw_left never holds that full count:
  // the head beat consumes the first one or two DWs first.
  logic [10:0]  dw_n;
  logic [31:0]  addr_q;
  logic [31:0]  addr_hi_q;
  // Nonzero upper address selects the 4DW Mem64 header. Zero keeps Mem32.
  logic         is64_q;
  // Mem64 payload is parked in sh_q before the header beats, so TX1 must
  // not clear it the way a Mem32 packet with no stashed DW does.
  logic         sh_primed_q;
  logic [7:0]   tag_q;
  logic [3:0]   fbe_q, lbe_q;
  logic [31:0]  data_q;
  logic [5:0]   seq_q;
  logic [3:0]   tag_av_q;
  // Bytes still to send after the 16-byte head. sh_q[7:0] is the oldest byte.
  logic [95:0]  sh_q;
  logic [3:0]   sh_n_q;
  logic [9:0]   dw_left_q;
  logic         more_q;
  logic         stash_v_q;
  logic [31:0]  stash_q;

  logic         more_beat;
  logic [3:0]   more_take;
  logic [7:0]   more_keep;
  logic         more_last;
  // Room in the shifter after this cycle consumes a beat. Pull AXI only then,
  // so a stalled TX beat is not overwritten and a ready beat can be replaced
  // in the same cycle.
  logic         more_fire;
  logic [3:0]   more_room;
  logic         cfg_stall;

  function automatic logic is_rq_cfg(input logic [3:0] req);
    return (req == RIVET_RQ_REQ_CFGRD0) || (req == RIVET_RQ_REQ_CFGRD1) ||
           (req == RIVET_RQ_REQ_CFGWR0) || (req == RIVET_RQ_REQ_CFGWR1);
  endfunction

  function automatic logic [7:0] cfg_b0(input logic [3:0] req);
    unique case (req)
      RIVET_RQ_REQ_CFGRD0: return RIVET_TLP_B0_CFGRD0;
      RIVET_RQ_REQ_CFGRD1: return RIVET_TLP_B0_CFGRD1;
      RIVET_RQ_REQ_CFGWR0: return RIVET_TLP_B0_CFGWR0;
      default:             return RIVET_TLP_B0_CFGWR1;
    endcase
  endfunction

  // A non-root port must not accept a config descriptor. The type sits on beat 1.
  assign cfg_stall = (MODE != RIVET_MODE_RC) && (st_q == ST_D1) &&
                     s_axis_rq_tvalid && is_rq_cfg(s_axis_rq_tdata[14:11]);

  assign more_beat = (sh_n_q >= 4'd8) || ((dw_left_q == 10'd0) && (sh_n_q != 4'd0));
  assign more_take = (sh_n_q >= 4'd8) ? 4'd8 : sh_n_q;
  assign more_last = (dw_left_q == 10'd0) && (sh_n_q <= 4'd8);
  always_comb begin
    more_keep = '0;
    for (int unsigned i = 0; i < 8; i++)
      if (i < more_take)
        more_keep[i] = 1'b1;
  end

  assign tx_tvalid_o = (st_q == ST_TX0) || (st_q == ST_TX1) ||
                       ((st_q == ST_MORE) && more_beat);
  assign more_fire = (st_q == ST_MORE) && more_beat && tx_tready_i;
  assign more_room = more_fire ? (sh_n_q - more_take) : sh_n_q;

  assign s_axis_rq_tready = bus_master_en_i && !cfg_stall &&
                            ((st_q == ST_D0) || (st_q == ST_D1) || (st_q == ST_DAT) ||
                             ((st_q == ST_MORE) && (dw_left_q != 10'd0) &&
                              (more_room <= 4'd4)));

  assign tx_tdata_o  = (st_q == ST_TX1) ? tx_q[127:64] :
                       (st_q == ST_MORE) ? sh_q[63:0] : tx_q[63:0];
  assign tx_tkeep_o  = (st_q == ST_MORE) ? more_keep :
                       (st_q == ST_TX1) ? ((is64_q || is_wr_q) ? 8'hFF : 8'h0F) : 8'hFF;
  assign tx_tlast_o  = ((st_q == ST_TX1) && !more_q) ||
                       ((st_q == ST_MORE) && more_beat && more_last);
  assign tx_hdr0_o   = tx_q[7:0];
  assign dw_n = (len_q == 10'd0) ? 11'd1024 : {1'b0, len_q};
  // Length 0 is the 1024 DW encoding. rivet_tlp_data_credits maps 0 to 256.
  assign tx_len_dw_o = is_wr_q ? len_q : 10'd0;
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
      is_cfg_q <= 1'b0;
      cfg_b0_q <= '0;
      cfg_cpl_q <= '0;
      len_q  <= '0;
      addr_q <= '0;
      addr_hi_q <= '0;
      is64_q <= 1'b0;
      sh_primed_q <= 1'b0;
      tag_q  <= '0;
      fbe_q  <= '0;
      lbe_q  <= '0;
      data_q <= '0;
      seq_q  <= '0;
      tag_av_q <= 4'd8;
      sh_q     <= '0;
      sh_n_q   <= '0;
      dw_left_q <= '0;
      more_q   <= 1'b0;
      stash_v_q <= 1'b0;
      stash_q  <= '0;
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
            addr_q    <= {s_axis_rq_tdata[31:2], 2'b00};
            addr_hi_q <= s_axis_rq_tdata[63:32];
            fbe_q  <= s_axis_rq_tuser[3:0];
            lbe_q  <= s_axis_rq_tuser[7:4];
            st_q   <= ST_D1;
          end
        end
        ST_D1: begin
          if (s_axis_rq_tvalid && s_axis_rq_tready) begin
            if ((MODE == RIVET_MODE_RC) && is_rq_cfg(s_axis_rq_tdata[14:11])) begin
              logic [3:0] req;
              req = s_axis_rq_tdata[14:11];
              is_cfg_q  <= 1'b1;
              is64_q    <= 1'b0;
              is_wr_q   <= (req == RIVET_RQ_REQ_CFGWR0) || (req == RIVET_RQ_REQ_CFGWR1);
              len_q     <= 10'd1;
              tag_q     <= s_axis_rq_tdata[39:32];
              cfg_b0_q  <= cfg_b0(req);
              cfg_cpl_q <= s_axis_rq_tdata[55:40];
              if (s_axis_rq_tlast) begin
                more_q      <= 1'b0;
                sh_primed_q <= 1'b0;
                tx_q[7:0]   <= cfg_b0(req);
                tx_q[15:8]  <= 8'h00;
                tx_q[23:16] <= 8'h00;
                tx_q[31:24] <= 8'h01;
                tx_q[39:32] <= 8'h00;
                tx_q[47:40] <= primary_bus_i;
                tx_q[55:48] <= s_axis_rq_tdata[39:32];
                tx_q[59:56] <= fbe_q;
                tx_q[63:60] <= 4'h0;
                tx_q[71:64] <= s_axis_rq_tdata[55:48];
                tx_q[79:72] <= s_axis_rq_tdata[47:40];
                tx_q[87:80] <= {4'h0, addr_q[11:8]};
                tx_q[95:88] <= {addr_q[7:2], 2'b00};
                st_q <= ST_TX0;
              end else
                st_q <= ST_DAT;
            end else begin
            len_q   <= s_axis_rq_tdata[9:0];
            is_cfg_q <= 1'b0;
            is_wr_q <= (s_axis_rq_tdata[14:11] == RIVET_CQ_REQ_MEMWR);
            is64_q  <= (addr_hi_q != 32'h0);
            // DW3[7:0] is the tag. beat1 = {DW3, DW2}, so the tag is [39:32].
            tag_q   <= s_axis_rq_tdata[39:32];
            if (s_axis_rq_tlast) begin
              // MemRd — header only. Upper address selects the 4DW format.
              more_q      <= 1'b0;
              sh_primed_q <= 1'b0;
              tx_q[15:8]  <= 8'h00;
              tx_q[23:16] <= {6'h0, s_axis_rq_tdata[9:8]};
              tx_q[31:24] <= s_axis_rq_tdata[7:0];
              tx_q[39:32] <= 8'h00;                 // req id lo
              tx_q[47:40] <= 8'h01;                 // req id hi — EP bus=1
              tx_q[55:48] <= s_axis_rq_tdata[39:32]; // tag, DW3[7:0]
              tx_q[59:56] <= fbe_q;
              tx_q[63:60] <= lbe_q;
              if (addr_hi_q != 32'h0) begin
                tx_q[7:0]     <= RIVET_TLP_B0_MEMRD64;
                tx_q[71:64]   <= addr_hi_q[31:24];
                tx_q[79:72]   <= addr_hi_q[23:16];
                tx_q[87:80]   <= addr_hi_q[15:8];
                tx_q[95:88]   <= addr_hi_q[7:0];
                tx_q[103:96]  <= addr_q[31:24];
                tx_q[111:104] <= addr_q[23:16];
                tx_q[119:112] <= addr_q[15:8];
                tx_q[127:120] <= addr_q[7:0];
              end else begin
                tx_q[7:0]   <= RIVET_TLP_B0_MEMRD32;
                tx_q[71:64] <= addr_q[31:24];
                tx_q[79:72] <= addr_q[23:16];
                tx_q[87:80] <= addr_q[15:8];
                tx_q[95:88] <= addr_q[7:0];
              end
              st_q <= ST_TX0;
            end else
              st_q <= ST_DAT;
            end
          end
        end
        ST_DAT: begin
          if (s_axis_rq_tvalid && s_axis_rq_tready && is_cfg_q) begin
            more_q      <= 1'b0;
            sh_primed_q <= 1'b0;
            data_q      <= s_axis_rq_tdata[31:0];
            tx_q[7:0]   <= cfg_b0_q;
            tx_q[15:8]  <= 8'h00;
            tx_q[23:16] <= 8'h00;
            tx_q[31:24] <= 8'h01;
            tx_q[39:32] <= 8'h00;
            tx_q[47:40] <= primary_bus_i;
            tx_q[55:48] <= tag_q;
            tx_q[59:56] <= fbe_q;
            tx_q[63:60] <= 4'h0;
            tx_q[71:64] <= cfg_cpl_q[15:8];
            tx_q[79:72] <= cfg_cpl_q[7:0];
            tx_q[87:80] <= {4'h0, addr_q[11:8]};
            tx_q[95:88] <= {addr_q[7:2], 2'b00};
            tx_q[103:96]  <= s_axis_rq_tdata[7:0];
            tx_q[111:104] <= s_axis_rq_tdata[15:8];
            tx_q[119:112] <= s_axis_rq_tdata[23:16];
            tx_q[127:120] <= s_axis_rq_tdata[31:24];
            st_q <= ST_TX0;
          end else if (s_axis_rq_tvalid && s_axis_rq_tready) begin
            logic [10:0] left;
            logic [10:0] full;
            data_q <= s_axis_rq_tdata[31:0];
            tx_q[15:8]  <= 8'h00;
            tx_q[23:16] <= {6'h0, len_q[9:8]};
            tx_q[31:24] <= len_q[7:0];
            tx_q[39:32] <= 8'h00;
            tx_q[47:40] <= 8'h01;
            tx_q[55:48] <= tag_q;
            tx_q[59:56] <= fbe_q;
            tx_q[63:60] <= lbe_q;
            // full==0 is not used; a captured length of 0 is 1024 DW.
            full = dw_n;
            if (addr_hi_q != 32'h0) begin
              // 16-byte MemWr64 header. Every payload DW follows it.
              logic [3:0] nb;
              logic [3:0] step;
              tx_q[7:0]     <= RIVET_TLP_B0_MEMWR64;
              tx_q[71:64]   <= addr_hi_q[31:24];
              tx_q[79:72]   <= addr_hi_q[23:16];
              tx_q[87:80]   <= addr_hi_q[15:8];
              tx_q[95:88]   <= addr_hi_q[7:0];
              tx_q[103:96]  <= addr_q[31:24];
              tx_q[111:104] <= addr_q[23:16];
              tx_q[119:112] <= addr_q[15:8];
              tx_q[127:120] <= addr_q[7:0];
              nb   = s_axis_rq_tkeep[1] ? 4'd8 : 4'd4;
              step = s_axis_rq_tkeep[1] ? 4'd2 : 4'd1;
              sh_q <= s_axis_rq_tkeep[1] ? {32'h0, s_axis_rq_tdata}
                                        : {64'h0, s_axis_rq_tdata[31:0]};
              sh_n_q      <= nb;
              sh_primed_q <= 1'b1;
              stash_v_q   <= 1'b0;
              left = (full > {7'd0, step}) ? (full - {7'd0, step}) : 11'd0;
              more_q <= 1'b1;
            end else begin
              // DW0 rides in the 16-byte head. A second DW in this beat is stashed.
              tx_q[7:0]   <= RIVET_TLP_B0_MEMWR32;
              tx_q[71:64] <= addr_q[31:24];
              tx_q[79:72] <= addr_q[23:16];
              tx_q[87:80] <= addr_q[15:8];
              tx_q[95:88] <= addr_q[7:0];
              tx_q[103:96]  <= s_axis_rq_tdata[7:0];
              tx_q[111:104] <= s_axis_rq_tdata[15:8];
              tx_q[119:112] <= s_axis_rq_tdata[23:16];
              tx_q[127:120] <= s_axis_rq_tdata[31:24];
              sh_primed_q <= 1'b0;
              left = (full > 11'd1) ? (full - 11'd1) : 11'd0;
              if ((full > 11'd1) && s_axis_rq_tkeep[1]) begin
                stash_q   <= s_axis_rq_tdata[63:32];
                stash_v_q <= 1'b1;
                left      = left - 11'd1;
              end else begin
                stash_v_q <= 1'b0;
              end
              more_q <= (full > 11'd1);
            end
            dw_left_q <= left[9:0];
            st_q <= ST_TX0;
          end
        end
        ST_TX0: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        end
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) begin
            if (more_q) begin
              if (stash_v_q) begin
                sh_q   <= {64'd0, stash_q};
                sh_n_q <= 4'd4;
              end else if (!sh_primed_q) begin
                sh_q   <= '0;
                sh_n_q <= '0;
              end
              sh_primed_q <= 1'b0;
              st_q <= ST_MORE;
            end else begin
              more_q <= 1'b0;
              st_q   <= ST_D0;
            end
          end
        end
        ST_MORE: begin
          logic [95:0] cat;
          logic [3:0]  cn;
          logic [9:0]  dl;
          cat = sh_q;
          cn  = sh_n_q;
          dl  = dw_left_q;
          if (more_fire) begin
            for (int unsigned b = 0; b < 12; b++) begin
              if ((b + 32'(more_take)) < 12)
                cat[8*b +: 8] = sh_q[8*(b + 32'(more_take)) +: 8];
              else
                cat[8*b +: 8] = 8'h00;
            end
            cn = sh_n_q - more_take;
          end
          if (s_axis_rq_tvalid && s_axis_rq_tready && (dw_left_q != 10'd0)) begin
            logic [3:0] nb;
            logic [3:0] step;
            nb   = s_axis_rq_tkeep[1] ? 4'd8 : 4'd4;
            step = s_axis_rq_tkeep[1] ? 4'd2 : 4'd1;
            for (int unsigned b = 0; b < 8; b++) begin
              if (b < nb)
                cat[8*(32'(cn) + b) +: 8] = s_axis_rq_tdata[8*b +: 8];
            end
            cn = cn + nb;
            dl = (dl >= {6'd0, step}) ? (dl - {6'd0, step}) : 10'd0;
          end
          sh_q      <= cat;
          sh_n_q    <= cn;
          dw_left_q <= dl;
          if ((cn == 4'd0) && (dl == 10'd0)) begin
            more_q <= 1'b0;
            st_q   <= ST_D0;
          end
        end
        default: st_q <= ST_D0;
      endcase
    end
  end

  wire unused_keep = |s_axis_rq_tkeep;
  wire unused_data = |data_q;

endmodule : rivet_tl_rq
