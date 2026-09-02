// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// VC0 Flow Control: InitFC1 → InitFC2 → DL_Active with UpdateFC (D2).

module rivet_dll_fc #(
  parameter int unsigned INITFC_GAP_CYC   = 8,
  parameter int unsigned UPDATEFC_GAP_CYC = 32
) (
  input  logic pclk_i,
  input  logic rst_ni,

  input  rivet_pkg::rivet_mac_dll_sb_t   mac_sb_i,
  input  rivet_pkg::rivet_tl_dll_fc_sb_t tl_fc_i,

  output rivet_pkg::rivet_dllp_req_t     req_o,
  output logic                           req_valid_o,
  input  logic                           req_ready_i,

  input  rivet_pkg::rivet_dllp_dec_t     dec_i,
  input  logic                           dec_valid_i,
  output logic                           dec_ready_o,

  output rivet_pkg::rivet_dll_tl_fc_sb_t dll_tl_fc_o
);

  import rivet_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE   = 2'd0,
    ST_INIT1  = 2'd1,
    ST_INIT2  = 2'd2,
    ST_ACTIVE = 2'd3
  } fc_state_e;

  fc_state_e state_q, state_d;

  rivet_fc_credit_set_t cl_q, cl_d;
  logic got_i1_p_q, got_i1_np_q, got_i1_cpl_q;
  logic got_i1_p_d, got_i1_np_d, got_i1_cpl_d;
  logic got_i2_p_q, got_i2_np_q, got_i2_cpl_q;
  logic got_i2_p_d, got_i2_np_d, got_i2_cpl_d;
  logic sent_i2_set_q, sent_i2_set_d;

  logic pend_p_q, pend_np_q, pend_cpl_q;
  logic pend_p_d, pend_np_d, pend_cpl_d;

  logic [1:0] tx_rot_q, tx_rot_d;
  logic [15:0] gap_q, gap_d;

  logic fi1_rx, fi2_rx;
  assign fi1_rx = got_i1_p_q && got_i1_np_q && got_i1_cpl_q;
  assign fi2_rx = got_i2_p_q && got_i2_np_q && got_i2_cpl_q;

  function automatic rivet_dllp_fc_kind_e init1_kind(input logic [1:0] rot);
    unique case (rot)
      2'd0: return RIVET_DLLP_FC_INIT1_P;
      2'd1: return RIVET_DLLP_FC_INIT1_NP;
      default: return RIVET_DLLP_FC_INIT1_CPL;
    endcase
  endfunction

  function automatic rivet_dllp_fc_kind_e init2_kind(input logic [1:0] rot);
    unique case (rot)
      2'd0: return RIVET_DLLP_FC_INIT2_P;
      2'd1: return RIVET_DLLP_FC_INIT2_NP;
      default: return RIVET_DLLP_FC_INIT2_CPL;
    endcase
  endfunction

  function automatic rivet_dllp_fc_kind_e update_kind(input logic [1:0] rot);
    unique case (rot)
      2'd0: return RIVET_DLLP_FC_UPDATE_P;
      2'd1: return RIVET_DLLP_FC_UPDATE_NP;
      default: return RIVET_DLLP_FC_UPDATE_CPL;
    endcase
  endfunction

  // InitFC may set infinite; UpdateFC must not invent infinite from a wrapped 0.
  function automatic rivet_fc_credit_set_t apply_fc_to_cl(
      input rivet_dllp_fc_kind_e kind,
      input logic [7:0] hdr,
      input logic [11:0] data,
      input rivet_fc_credit_set_t cl_in);
    rivet_fc_credit_set_t cl;
    cl = cl_in;
    unique case (kind)
      RIVET_DLLP_FC_INIT1_P, RIVET_DLLP_FC_INIT2_P: begin
        cl.ph     = hdr;
        cl.pd     = data;
        cl.ph_inf = (hdr == 8'h00);
        cl.pd_inf = (data == 12'h000);
      end
      RIVET_DLLP_FC_INIT1_NP, RIVET_DLLP_FC_INIT2_NP: begin
        cl.nph     = hdr;
        cl.npd     = data;
        cl.nph_inf = (hdr == 8'h00);
        cl.npd_inf = (data == 12'h000);
      end
      RIVET_DLLP_FC_INIT1_CPL, RIVET_DLLP_FC_INIT2_CPL: begin
        cl.cplh     = hdr;
        cl.cpld     = data;
        cl.cplh_inf = (hdr == 8'h00);
        cl.cpld_inf = (data == 12'h000);
      end
      RIVET_DLLP_FC_UPDATE_P: begin
        if (!cl.ph_inf) cl.ph = hdr;
        if (!cl.pd_inf) cl.pd = data;
      end
      RIVET_DLLP_FC_UPDATE_NP: begin
        if (!cl.nph_inf) cl.nph = hdr;
        if (!cl.npd_inf) cl.npd = data;
      end
      RIVET_DLLP_FC_UPDATE_CPL: begin
        if (!cl.cplh_inf) cl.cplh = hdr;
        if (!cl.cpld_inf) cl.cpld = data;
      end
      default: ;
    endcase
    return cl;
  endfunction

  // Type selection for the current TX attempt
  logic [1:0] send_sel;
  always_comb begin
    send_sel = tx_rot_q;
    if (state_q == ST_ACTIVE) begin
      if (pend_p_q) send_sel = 2'd0;
      else if (pend_np_q) send_sel = 2'd1;
      else if (pend_cpl_q) send_sel = 2'd2;
    end
  end

  rivet_dllp_req_t req_comb;
  always_comb begin
    req_comb         = '0;
    req_comb.kind    = RIVET_DLLP_KIND_FC;
    req_comb.vc      = 3'd0;
    unique case (send_sel)
      2'd0: begin
        req_comb.hdr_fc  = tl_fc_i.ca.ph_inf  ? 8'h00  : tl_fc_i.ca.ph;
        req_comb.data_fc = tl_fc_i.ca.pd_inf  ? 12'h000 : tl_fc_i.ca.pd;
      end
      2'd1: begin
        req_comb.hdr_fc  = tl_fc_i.ca.nph_inf ? 8'h00  : tl_fc_i.ca.nph;
        req_comb.data_fc = tl_fc_i.ca.npd_inf ? 12'h000 : tl_fc_i.ca.npd;
      end
      default: begin
        req_comb.hdr_fc  = tl_fc_i.ca.cplh_inf ? 8'h00  : tl_fc_i.ca.cplh;
        req_comb.data_fc = tl_fc_i.ca.cpld_inf ? 12'h000 : tl_fc_i.ca.cpld;
      end
    endcase
    unique case (state_q)
      ST_INIT1:  req_comb.fc_kind = init1_kind(send_sel);
      ST_INIT2:  req_comb.fc_kind = init2_kind(send_sel);
      ST_ACTIVE: req_comb.fc_kind = update_kind(send_sel);
      default:   req_comb.fc_kind = RIVET_DLLP_FC_UPDATE_P;
    endcase
  end

  logic send_pulse;
  assign send_pulse =
      ((state_q == ST_INIT1) || (state_q == ST_INIT2) || (state_q == ST_ACTIVE)) &&
      (gap_q == '0) && mac_sb_i.accept_dll_tlp;

  assign req_o       = req_comb;
  assign req_valid_o = send_pulse;
  assign dec_ready_o = 1'b1;

  logic any_free;
  assign any_free = tl_fc_i.ph_freed | tl_fc_i.pd_freed | tl_fc_i.nph_freed |
                    tl_fc_i.npd_freed | tl_fc_i.cplh_freed | tl_fc_i.cpld_freed;

  always_comb begin
    state_d        = state_q;
    cl_d           = cl_q;
    got_i1_p_d     = got_i1_p_q;
    got_i1_np_d    = got_i1_np_q;
    got_i1_cpl_d   = got_i1_cpl_q;
    got_i2_p_d     = got_i2_p_q;
    got_i2_np_d    = got_i2_np_q;
    got_i2_cpl_d   = got_i2_cpl_q;
    sent_i2_set_d  = sent_i2_set_q;
    pend_p_d       = pend_p_q;
    pend_np_d      = pend_np_q;
    pend_cpl_d     = pend_cpl_q;
    tx_rot_d       = tx_rot_q;
    gap_d          = gap_q;

    if (!mac_sb_i.accept_dll_tlp) begin
      state_d       = ST_IDLE;
      got_i1_p_d    = 1'b0;
      got_i1_np_d   = 1'b0;
      got_i1_cpl_d  = 1'b0;
      got_i2_p_d    = 1'b0;
      got_i2_np_d   = 1'b0;
      got_i2_cpl_d  = 1'b0;
      sent_i2_set_d = 1'b0;
      pend_p_d      = 1'b0;
      pend_np_d     = 1'b0;
      pend_cpl_d    = 1'b0;
      tx_rot_d      = 2'd0;
      gap_d         = '0;
    end else begin
      if (dec_valid_i && dec_i.crc_ok && (dec_i.kind == RIVET_DLLP_KIND_FC) &&
          (dec_i.vc == 3'd0)) begin
        cl_d = apply_fc_to_cl(dec_i.fc_kind, dec_i.hdr_fc, dec_i.data_fc, cl_d);
        unique case (dec_i.fc_kind)
          RIVET_DLLP_FC_INIT1_P:   got_i1_p_d   = 1'b1;
          RIVET_DLLP_FC_INIT1_NP:  got_i1_np_d  = 1'b1;
          RIVET_DLLP_FC_INIT1_CPL: got_i1_cpl_d = 1'b1;
          RIVET_DLLP_FC_INIT2_P,
          RIVET_DLLP_FC_UPDATE_P:   got_i2_p_d   = 1'b1;
          RIVET_DLLP_FC_INIT2_NP,
          RIVET_DLLP_FC_UPDATE_NP:  got_i2_np_d  = 1'b1;
          RIVET_DLLP_FC_INIT2_CPL,
          RIVET_DLLP_FC_UPDATE_CPL: got_i2_cpl_d = 1'b1;
          default: ;
        endcase
      end

      // TL credit-return pulses schedule UpdateFC for that traffic class.
      if (tl_fc_i.ph_freed || tl_fc_i.pd_freed) pend_p_d = 1'b1;
      if (tl_fc_i.nph_freed || tl_fc_i.npd_freed) pend_np_d = 1'b1;
      if (tl_fc_i.cplh_freed || tl_fc_i.cpld_freed) pend_cpl_d = 1'b1;
      if ((state_q == ST_ACTIVE) && any_free) gap_d = '0;

      if (send_pulse && req_ready_i) begin
        if (state_q == ST_ACTIVE) gap_d = UPDATEFC_GAP_CYC[15:0];
        else gap_d = INITFC_GAP_CYC[15:0];

        if (state_q == ST_ACTIVE) begin
          unique case (send_sel)
            2'd0: if (!(tl_fc_i.ph_freed || tl_fc_i.pd_freed)) pend_p_d = 1'b0;
            2'd1: if (!(tl_fc_i.nph_freed || tl_fc_i.npd_freed)) pend_np_d = 1'b0;
            default: if (!(tl_fc_i.cplh_freed || tl_fc_i.cpld_freed)) pend_cpl_d = 1'b0;
          endcase
          // Advance periodic rotator only when not draining a free-triggered pending.
          if (!(pend_p_q || pend_np_q || pend_cpl_q)) begin
            if (tx_rot_q == 2'd2) tx_rot_d = 2'd0;
            else tx_rot_d = tx_rot_q + 2'd1;
          end
        end else begin
          if (tx_rot_q == 2'd2) begin
            tx_rot_d = 2'd0;
            if (state_q == ST_INIT2) sent_i2_set_d = 1'b1;
          end else begin
            tx_rot_d = tx_rot_q + 2'd1;
          end
        end
      end else if (gap_q != '0) begin
        // Freed may have forced gap_d to 0 above; do not re-decrement in that case.
        if (!((state_q == ST_ACTIVE) && any_free))
          gap_d = gap_q - 16'd1;
      end

      unique case (state_q)
        ST_IDLE: begin
          state_d  = ST_INIT1;
          gap_d    = '0;
          tx_rot_d = 2'd0;
        end
        ST_INIT1: begin
          if (fi1_rx) begin
            state_d       = ST_INIT2;
            gap_d         = '0;
            tx_rot_d      = 2'd0;
            sent_i2_set_d = 1'b0;
          end
        end
        ST_INIT2: begin
          if (fi2_rx && sent_i2_set_q) begin
            state_d  = ST_ACTIVE;
            gap_d    = '0;
            tx_rot_d = 2'd0;
          end
        end
        ST_ACTIVE: ;
        default: state_d = ST_IDLE;
      endcase
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q       <= ST_IDLE;
      cl_q          <= '0;
      got_i1_p_q    <= 1'b0;
      got_i1_np_q   <= 1'b0;
      got_i1_cpl_q  <= 1'b0;
      got_i2_p_q    <= 1'b0;
      got_i2_np_q   <= 1'b0;
      got_i2_cpl_q  <= 1'b0;
      sent_i2_set_q <= 1'b0;
      pend_p_q      <= 1'b0;
      pend_np_q     <= 1'b0;
      pend_cpl_q    <= 1'b0;
      tx_rot_q      <= 2'd0;
      gap_q         <= '0;
    end else begin
      state_q       <= state_d;
      cl_q          <= cl_d;
      got_i1_p_q    <= got_i1_p_d;
      got_i1_np_q   <= got_i1_np_d;
      got_i1_cpl_q  <= got_i1_cpl_d;
      got_i2_p_q    <= got_i2_p_d;
      got_i2_np_q   <= got_i2_np_d;
      got_i2_cpl_q  <= got_i2_cpl_d;
      sent_i2_set_q <= sent_i2_set_d;
      pend_p_q      <= pend_p_d;
      pend_np_q     <= pend_np_d;
      pend_cpl_q    <= pend_cpl_d;
      tx_rot_q      <= tx_rot_d;
      gap_q         <= gap_d;
    end
  end

  assign dll_tl_fc_o.cl           = cl_q;
  assign dll_tl_fc_o.fc_init_done = (state_q == ST_ACTIVE);
  assign dll_tl_fc_o.dl_active    = (state_q == ST_ACTIVE);

endmodule : rivet_dll_fc
