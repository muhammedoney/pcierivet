// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Mux TL→DLL TX from fabric Cfg, CC, and RQ (priority Cfg > CC > RQ).

module rivet_tl_tx_mux (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [63:0] cfg_tdata_i,
  input  logic [7:0]  cfg_tkeep_i,
  input  logic        cfg_tlast_i,
  input  logic        cfg_tvalid_i,
  output logic        cfg_tready_o,

  input  logic [63:0] cc_tdata_i,
  input  logic [7:0]  cc_tkeep_i,
  input  logic        cc_tlast_i,
  input  logic        cc_tvalid_i,
  output logic        cc_tready_o,

  input  logic [63:0] rq_tdata_i,
  input  logic [7:0]  rq_tkeep_i,
  input  logic        rq_tlast_i,
  input  logic        rq_tvalid_i,
  output logic        rq_tready_o,

  output logic [63:0] m_tdata_o,
  output logic [7:0]  m_tkeep_o,
  output logic        m_tlast_o,
  output logic        m_tvalid_o,
  input  logic        m_tready_i
);

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_CFG  = 2'd1,
    ST_CC   = 2'd2,
    ST_RQ   = 2'd3
  } st_e;

  st_e st_q;

  always_comb begin
    m_tdata_o    = '0;
    m_tkeep_o    = '0;
    m_tlast_o    = 1'b0;
    m_tvalid_o   = 1'b0;
    cfg_tready_o = 1'b0;
    cc_tready_o  = 1'b0;
    rq_tready_o  = 1'b0;
    unique case (st_q)
      ST_IDLE: begin
        if (cfg_tvalid_i) begin
          m_tdata_o    = cfg_tdata_i;
          m_tkeep_o    = cfg_tkeep_i;
          m_tlast_o    = cfg_tlast_i;
          m_tvalid_o   = 1'b1;
          cfg_tready_o = m_tready_i;
        end else if (cc_tvalid_i) begin
          m_tdata_o   = cc_tdata_i;
          m_tkeep_o   = cc_tkeep_i;
          m_tlast_o   = cc_tlast_i;
          m_tvalid_o  = 1'b1;
          cc_tready_o = m_tready_i;
        end else if (rq_tvalid_i) begin
          m_tdata_o   = rq_tdata_i;
          m_tkeep_o   = rq_tkeep_i;
          m_tlast_o   = rq_tlast_i;
          m_tvalid_o  = 1'b1;
          rq_tready_o = m_tready_i;
        end
      end
      ST_CFG: begin
        m_tdata_o    = cfg_tdata_i;
        m_tkeep_o    = cfg_tkeep_i;
        m_tlast_o    = cfg_tlast_i;
        m_tvalid_o   = cfg_tvalid_i;
        cfg_tready_o = m_tready_i;
      end
      ST_CC: begin
        m_tdata_o   = cc_tdata_i;
        m_tkeep_o   = cc_tkeep_i;
        m_tlast_o   = cc_tlast_i;
        m_tvalid_o  = cc_tvalid_i;
        cc_tready_o = m_tready_i;
      end
      ST_RQ: begin
        m_tdata_o   = rq_tdata_i;
        m_tkeep_o   = rq_tkeep_i;
        m_tlast_o   = rq_tlast_i;
        m_tvalid_o  = rq_tvalid_i;
        rq_tready_o = m_tready_i;
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q <= ST_IDLE;
    end else if (m_tvalid_o && m_tready_i) begin
      unique case (st_q)
        ST_IDLE: begin
          if (cfg_tvalid_i && !cfg_tlast_i) st_q <= ST_CFG;
          else if (!cfg_tvalid_i && cc_tvalid_i && !cc_tlast_i) st_q <= ST_CC;
          else if (!cfg_tvalid_i && !cc_tvalid_i && rq_tvalid_i && !rq_tlast_i)
            st_q <= ST_RQ;
        end
        ST_CFG: if (cfg_tlast_i) st_q <= ST_IDLE;
        ST_CC:  if (cc_tlast_i)  st_q <= ST_IDLE;
        ST_RQ:  if (rq_tlast_i)  st_q <= ST_IDLE;
        default: st_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_tl_tx_mux
