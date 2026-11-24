// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Demux DLL→TL RX to Cfg / Mem CQ / Completion RC.
// DATA_W 64 passes each beat through. DATA_W 128 keeps the completion
// beat intact and splits a 16-byte Cfg/CQ beat into two 8-byte beats.

module rivet_tl_rx_route #(
  parameter int unsigned DATA_W = 64
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [DATA_W-1:0]   s_tdata_i,
  input  logic [DATA_W/8-1:0] s_tkeep_i,
  input  logic                s_tlast_i,
  input  logic                s_tvalid_i,
  input  logic                s_abort_i,
  output logic                s_tready_o,

  output logic [63:0] cfg_tdata_o,
  output logic [7:0]  cfg_tkeep_o,
  output logic        cfg_tlast_o,
  output logic        cfg_tvalid_o,
  input  logic        cfg_tready_i,

  output logic [63:0] cq_tdata_o,
  output logic [7:0]  cq_tkeep_o,
  output logic        cq_tlast_o,
  output logic        cq_tvalid_o,
  input  logic        cq_tready_i,

  output logic [DATA_W-1:0]   rc_tdata_o,
  output logic [DATA_W/8-1:0] rc_tkeep_o,
  output logic                rc_tlast_o,
  output logic                rc_tvalid_o,
  input  logic                rc_tready_i
);

  import rivet_pkg::*;

  generate
    if (DATA_W == 64) begin : g_w64
      typedef enum logic [2:0] {
        ST_SOP  = 3'd0,
        ST_CFG  = 3'd1,
        ST_CQ   = 3'd2,
        ST_RC   = 3'd3,
        ST_DROP = 3'd4
      } st_e;

      st_e st_q;

      logic is_cfg, is_mem, is_cpl;
      assign is_cfg = (s_tdata_i[7:0] == RIVET_TLP_B0_CFGRD0) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_CFGWR0) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_CFGRD1) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_CFGWR1);
      assign is_mem = (s_tdata_i[7:0] == RIVET_TLP_B0_MEMRD32) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MEMWR32) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MEMRD64) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MEMWR64) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_IORD) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_IOWR) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MSG) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MSGD);
      assign is_cpl = (s_tdata_i[7:0] == RIVET_TLP_B0_CPL) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_CPLD);

      assign cfg_tdata_o  = s_tdata_i;
      assign cfg_tkeep_o  = s_tkeep_i;
      assign cfg_tlast_o  = s_tlast_i;
      assign cq_tdata_o   = s_tdata_i;
      assign cq_tkeep_o   = s_tkeep_i;
      assign cq_tlast_o   = s_tlast_i;
      assign rc_tdata_o   = s_tdata_i;
      assign rc_tkeep_o   = s_tkeep_i;
      assign rc_tlast_o   = s_tlast_i;

      always_comb begin
        cfg_tvalid_o = 1'b0;
        cq_tvalid_o  = 1'b0;
        rc_tvalid_o  = 1'b0;
        s_tready_o   = 1'b0;
        unique case (st_q)
          ST_SOP: begin
            if (s_tvalid_i) begin
              if (is_cfg) begin
                cfg_tvalid_o = 1'b1;
                s_tready_o   = cfg_tready_i;
              end else if (is_mem) begin
                cq_tvalid_o = 1'b1;
                s_tready_o  = cq_tready_i;
              end else if (is_cpl) begin
                rc_tvalid_o = 1'b1;
                s_tready_o  = rc_tready_i;
              end else begin
                s_tready_o = 1'b1;
              end
            end
          end
          ST_CFG: begin
            cfg_tvalid_o = s_tvalid_i;
            s_tready_o   = cfg_tready_i;
          end
          ST_CQ: begin
            cq_tvalid_o = s_tvalid_i;
            s_tready_o  = cq_tready_i;
          end
          ST_RC: begin
            rc_tvalid_o = s_tvalid_i;
            s_tready_o  = rc_tready_i;
          end
          ST_DROP: begin
            s_tready_o = 1'b1;
          end
          default: ;
        endcase
      end

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          st_q <= ST_SOP;
        end else if (s_abort_i) begin
          st_q <= ST_SOP;
        end else if (s_tvalid_i && s_tready_o) begin
          unique case (st_q)
            ST_SOP: begin
              if (is_cfg && !s_tlast_i)      st_q <= ST_CFG;
              else if (is_mem && !s_tlast_i) st_q <= ST_CQ;
              else if (is_cpl && !s_tlast_i) st_q <= ST_RC;
              else if (!is_cfg && !is_mem && !is_cpl && !s_tlast_i) st_q <= ST_DROP;
              else st_q <= ST_SOP;
            end
            ST_CFG, ST_CQ, ST_RC, ST_DROP: begin
              if (s_tlast_i) st_q <= ST_SOP;
            end
            default: st_q <= ST_SOP;
          endcase
        end
      end
    end else begin : g_w128
      typedef enum logic [2:0] {
        ST_SOP  = 3'd0,
        ST_CFG  = 3'd1,
        ST_CQ   = 3'd2,
        ST_RC   = 3'd3,
        ST_DROP = 3'd4,
        ST_HI   = 3'd5
      } st_e;

      st_e         st_q;
      logic [63:0] hi_d_q;
      logic [7:0]  hi_k_q;
      logic        hi_last_q;
      logic        hi_cfg_q;

      logic is_cfg, is_mem, is_cpl, has_hi;
      logic [63:0] lo_d;
      logic [7:0]  lo_k;
      logic        lo_last;

      assign is_cfg = (s_tdata_i[7:0] == RIVET_TLP_B0_CFGRD0) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_CFGWR0) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_CFGRD1) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_CFGWR1);
      assign is_mem = (s_tdata_i[7:0] == RIVET_TLP_B0_MEMRD32) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MEMWR32) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MEMRD64) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MEMWR64) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_IORD) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_IOWR) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MSG) ||
                      (s_tdata_i[7:0] == RIVET_TLP_B0_MSGD);
      assign is_cpl  = (s_tdata_i[7:0] == RIVET_TLP_B0_CPL) ||
                       (s_tdata_i[7:0] == RIVET_TLP_B0_CPLD);
      assign has_hi  = |s_tkeep_i[15:8];
      assign lo_d    = s_tdata_i[63:0];
      assign lo_k    = s_tkeep_i[7:0];
      assign lo_last = s_tlast_i && !has_hi;

      assign rc_tdata_o = s_tdata_i;
      assign rc_tkeep_o = s_tkeep_i;
      assign rc_tlast_o = s_tlast_i;

      always_comb begin
        cfg_tdata_o  = lo_d;
        cfg_tkeep_o  = lo_k;
        cfg_tlast_o  = lo_last;
        cq_tdata_o   = lo_d;
        cq_tkeep_o   = lo_k;
        cq_tlast_o   = lo_last;
        cfg_tvalid_o = 1'b0;
        cq_tvalid_o  = 1'b0;
        rc_tvalid_o  = 1'b0;
        s_tready_o   = 1'b0;
        if (st_q == ST_HI) begin
          if (hi_cfg_q) begin
            cfg_tdata_o  = hi_d_q;
            cfg_tkeep_o  = hi_k_q;
            cfg_tlast_o  = hi_last_q;
            cfg_tvalid_o = 1'b1;
          end else begin
            cq_tdata_o  = hi_d_q;
            cq_tkeep_o  = hi_k_q;
            cq_tlast_o  = hi_last_q;
            cq_tvalid_o = 1'b1;
          end
        end else if (st_q == ST_SOP) begin
          if (s_tvalid_i) begin
            if (is_cfg) begin
              cfg_tvalid_o = 1'b1;
              s_tready_o   = cfg_tready_i;
            end else if (is_mem) begin
              cq_tvalid_o = 1'b1;
              s_tready_o  = cq_tready_i;
            end else if (is_cpl) begin
              rc_tvalid_o = 1'b1;
              s_tready_o  = rc_tready_i;
            end else begin
              s_tready_o = 1'b1;
            end
          end
        end else if (st_q == ST_CFG) begin
          cfg_tvalid_o = s_tvalid_i;
          s_tready_o   = cfg_tready_i;
        end else if (st_q == ST_CQ) begin
          cq_tvalid_o = s_tvalid_i;
          s_tready_o  = cq_tready_i;
        end else if (st_q == ST_RC) begin
          rc_tvalid_o = s_tvalid_i;
          s_tready_o  = rc_tready_i;
        end else if (st_q == ST_DROP) begin
          s_tready_o = 1'b1;
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          st_q      <= ST_SOP;
          hi_d_q    <= '0;
          hi_k_q    <= '0;
          hi_last_q <= 1'b0;
          hi_cfg_q  <= 1'b0;
        end else if (s_abort_i) begin
          st_q <= ST_SOP;
        end else if (st_q == ST_HI) begin
          if ((hi_cfg_q && cfg_tready_i) || (!hi_cfg_q && cq_tready_i)) begin
            if (hi_last_q)
              st_q <= ST_SOP;
            else
              st_q <= hi_cfg_q ? ST_CFG : ST_CQ;
          end
        end else if (s_tvalid_i && s_tready_o) begin
          if (((st_q == ST_SOP) && (is_cfg || is_mem) && has_hi) ||
              ((st_q == ST_CFG || st_q == ST_CQ) && has_hi)) begin
            hi_d_q    <= s_tdata_i[127:64];
            hi_k_q    <= s_tkeep_i[15:8];
            hi_last_q <= s_tlast_i;
            hi_cfg_q  <= (st_q == ST_CFG) || ((st_q == ST_SOP) && is_cfg);
            st_q      <= ST_HI;
          end else begin
            unique case (st_q)
              ST_SOP: begin
                if (is_cfg && !s_tlast_i)      st_q <= ST_CFG;
                else if (is_mem && !s_tlast_i) st_q <= ST_CQ;
                else if (is_cpl && !s_tlast_i) st_q <= ST_RC;
                else if (!is_cfg && !is_mem && !is_cpl && !s_tlast_i)
                  st_q <= ST_DROP;
                else st_q <= ST_SOP;
              end
              ST_CFG, ST_CQ, ST_RC, ST_DROP: begin
                if (s_tlast_i) st_q <= ST_SOP;
              end
              default: st_q <= ST_SOP;
            endcase
          end
        end
      end
    end
  endgenerate

endmodule : rivet_tl_rx_route
