// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC ordered-set / TS transmitter (Gen2, 8b/10b symbol plane).
//
// Streams the ordered set the LTSSM asks for and, when L0 packet enable is high,
// may insert SKP OS (Gen1/Gen2 clock compensation) and framed DLLP
// (SDP + 6 bytes + END) striped across LANES∈{1,2,4}.

module rivet_mac_os_tx #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16,
  // Symbol Times between SKP OS in L0 (must stay in [1180, 1538]).
  parameter int unsigned SKP_INTERVAL_SYM = rivet_pkg::RIVET_SKP_INTERVAL_SYM
) (
  input  logic pclk_i,
  input  logic rst_ni,

  input  rivet_pkg::rivet_mac_os_type_e os_req_i,
  input  logic                          os_req_valid_i,
  input  logic                          os_cnt_clr_i,
  input  logic [LANES-1:0]              lane_en_i,
  input  logic                          pkt_en_i, // typically accept_dll_tlp (L0)

  // TS payload fields (Base 2.1 Tables 4-2/4-3)
  input  logic [7:0]                    tx_link_num_i,
  input  logic [8*LANES-1:0]            tx_lane_num_i,
  input  logic                          tx_link_pad_i,
  input  logic                          tx_lane_pad_i,
  input  logic [7:0]                    tx_n_fts_i,
  input  logic [7:0]                    tx_rate_id_i,
  input  logic [7:0]                    tx_train_ctrl_i,

  // DLL payload (DLLP single-beat for this slice)
  input  rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_i,
  input  logic                              dll_tx_valid_i,
  output logic                              dll_tx_ready_o,

  // Symbol stream toward scrambler / pipe adapter (per-link packed)
  output logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_o,
  output logic [2*LANES-1:0]               sym_datak_o,
  output logic [2*LANES-1:0]               sym_os_d_o, // 1 = Ordered-Set D (scramble bypass)
  output logic                             sym_valid_o,

  // Ordered sets completed (Idle counts symbols) since os_cnt_clr_i
  output logic [11:0]                      os_sent_cnt_o
);

  import rivet_pkg::*;

  localparam int unsigned SYMS        = PIPE_DATA_WIDTH / 8;
  localparam int unsigned SYM_PER_CLK = LANES * SYMS;
  localparam int unsigned CNT_W       = 12;
  // Must hold pkt_ptr + SYM_PER_CLK without wrap (x4: 8+8=16).
  localparam int unsigned PTR_W       = 5;

  localparam logic [CNT_W-1:0] SYMS_C  = CNT_W'(SYMS);
  localparam logic [CNT_W-1:0] CNT_MAX = {CNT_W{1'b1}};

  // Packet framing for Gen2 16-bit PIPE on legal widths.
  localparam bit PKT_OK = (PIPE_DATA_WIDTH == 16);
  localparam int unsigned SKP_CNT_W = 12;

`ifndef SYNTHESIS
  initial begin
    if (PIPE_DATA_WIDTH != 16)
      $error("rivet_mac_os_tx: only PIPE_DATA_WIDTH=16 is implemented (got %0d)",
             PIPE_DATA_WIDTH);
    if (!rivet_lanes_legal(LANES))
      $error("rivet_mac_os_tx LANES must be 1, 2, or 4");
    if ((SKP_INTERVAL_SYM < RIVET_SKP_MIN_SYM_TIMES) ||
        (SKP_INTERVAL_SYM > RIVET_SKP_MAX_SYM_TIMES))
      $error("rivet_mac_os_tx SKP_INTERVAL_SYM=%0d outside [%0d,%0d]",
             SKP_INTERVAL_SYM, RIVET_SKP_MIN_SYM_TIMES, RIVET_SKP_MAX_SYM_TIMES);
  end
`endif

  function automatic logic [8:0] os_symbol(input rivet_mac_os_type_e os_type,
                                           input logic [3:0]         idx,
                                           input logic [7:0]         lane_num);
    logic [8:0] sym;
    sym = {1'b0, 8'h00};
    case (os_type)
      RIVET_MAC_OS_TS1, RIVET_MAC_OS_TS2: begin
        case (idx)
          4'd0:    sym = {1'b1, RIVET_SYM_COM};
          4'd1:    sym = tx_link_pad_i ? {1'b1, RIVET_SYM_PAD} : {1'b0, tx_link_num_i};
          4'd2:    sym = tx_lane_pad_i ? {1'b1, RIVET_SYM_PAD} : {1'b0, lane_num};
          4'd3:    sym = {1'b0, tx_n_fts_i};
          4'd4:    sym = {1'b0, tx_rate_id_i};
          4'd5:    sym = {1'b0, tx_train_ctrl_i};
          default: sym = (os_type == RIVET_MAC_OS_TS1) ? {1'b0, RIVET_SYM_TS1_ID}
                                                       : {1'b0, RIVET_SYM_TS2_ID};
        endcase
      end
      RIVET_MAC_OS_SKP:  sym = (idx == 4'd0) ? {1'b1, RIVET_SYM_COM} : {1'b1, RIVET_SYM_SKP};
      RIVET_MAC_OS_FTS:  sym = (idx == 4'd0) ? {1'b1, RIVET_SYM_COM} : {1'b1, RIVET_SYM_FTS};
      RIVET_MAC_OS_EIOS: sym = (idx == 4'd0) ? {1'b1, RIVET_SYM_COM} : {1'b1, RIVET_SYM_IDL};
      default:           sym = {1'b0, 8'h00};
    endcase
    return sym;
  endfunction

  function automatic logic [4:0] os_length(input rivet_mac_os_type_e os_type);
    case (os_type)
      RIVET_MAC_OS_TS1,
      RIVET_MAC_OS_TS2:  return 5'(RIVET_TS_LEN);
      RIVET_MAC_OS_SKP,
      RIVET_MAC_OS_FTS,
      RIVET_MAC_OS_EIOS: return 5'(RIVET_SHORT_OS_LEN);
      default:           return 5'(SYMS);
    endcase
  endfunction

  // Framed DLLP stream: [0]=SDP, [1..6]=bytes, [7]=END; else Logical Idle.
  function automatic logic [8:0] pkt_symbol(input logic [3:0] idx,
                                            input logic [63:0] dllp);
    logic [8:0] sym;
    if (idx == 4'd0)
      sym = {1'b1, RIVET_SYM_SDP};
    else if (idx == 4'(RIVET_DLLP_FRAMED_LEN - 1))
      sym = {1'b1, RIVET_SYM_END};
    else if (idx < 4'(RIVET_DLLP_FRAMED_LEN))
      sym = {1'b0, dllp[8*(idx-1) +: 8]};
    else
      sym = {1'b0, 8'h00};
    return sym;
  endfunction

  typedef enum logic [1:0] {
    ST_OS  = 2'b00,
    ST_PKT = 2'b01
  } tx_mode_e;

  tx_mode_e         mode_q, mode_d;
  rivet_mac_os_type_e cur;
  rivet_mac_os_type_e cur_q;
  logic [4:0]         ptr_q;
  logic [4:0]         len;
  logic [4:0]         ptr_next;
  logic               at_boundary;
  logic               transmitting;
  logic               set_done;
  logic [CNT_W-1:0]   sent_q;
  logic [8:0]         sym_tmp;

  logic [63:0]            pkt_q, pkt_d;
  logic [PTR_W-1:0]       pkt_ptr_q, pkt_ptr_d;
  logic                   pkt_done;
  logic                   take_dllp;
  logic                   dllp_ok;
  logic                   want_pkt;
  logic                   want_skp;
  logic                   skp_due;
  logic                   skp_finishing;
  logic [PTR_W-1:0]       stream_idx;
  logic [SKP_CNT_W-1:0]   skp_sym_q;

  assign at_boundary  = (ptr_q == 5'd0) && (mode_q == ST_OS);
  assign transmitting = os_req_valid_i && (os_req_i != RIVET_MAC_OS_NONE);
  // L0: SKP preempts Idle/DLLP at OS boundaries (never mid-packet / mid-OS).
  assign skp_due  = pkt_en_i && (skp_sym_q >= SKP_CNT_W'(SKP_INTERVAL_SYM));
  assign want_skp = PKT_OK && skp_due && at_boundary;
  assign cur = at_boundary
      ? (want_skp ? RIVET_MAC_OS_SKP
                  : (transmitting ? os_req_i : RIVET_MAC_OS_NONE))
      : cur_q;
  assign len          = os_length(cur);
  assign set_done     = (ptr_q + 5'(SYMS)) >= len;
  assign ptr_next     = set_done ? 5'd0 : (ptr_q + 5'(SYMS));
  assign skp_finishing =
      (mode_q == ST_OS) && !take_dllp && set_done && (cur == RIVET_MAC_OS_SKP);

  assign dllp_ok = dll_tx_valid_i &&
                   (dll_tx_beat_i.pkt_type == RIVET_MAC_PKT_DLLP) &&
                   dll_tx_beat_i.sop && dll_tx_beat_i.eop &&
                   (dll_tx_beat_i.keep == 8'hFF);

  // Insert DLLP only between Idle OS boundaries while packet-enabled (SKP first).
  assign want_pkt = PKT_OK && pkt_en_i && at_boundary && !want_skp &&
                    (cur == RIVET_MAC_OS_IDLE) && dllp_ok;
  assign take_dllp = want_pkt;
  assign dll_tx_ready_o = take_dllp;

  assign pkt_done = (pkt_ptr_q + PTR_W'(SYM_PER_CLK)) >= PTR_W'(RIVET_DLLP_FRAMED_LEN);

  always_comb begin
    mode_d    = mode_q;
    pkt_d     = pkt_q;
    pkt_ptr_d = pkt_ptr_q;
    unique case (mode_q)
      ST_OS: begin
        if (take_dllp) begin
          pkt_d = dll_tx_beat_i.data;
          // First cycle already emits symbols 0..SYM_PER_CLK-1.
          if (SYM_PER_CLK >= RIVET_DLLP_FRAMED_LEN) begin
            mode_d    = ST_OS;
            pkt_ptr_d = '0;
          end else begin
            mode_d    = ST_PKT;
            pkt_ptr_d = PTR_W'(SYM_PER_CLK);
          end
        end
      end
      ST_PKT: begin
        if (pkt_done) begin
          mode_d    = ST_OS;
          pkt_ptr_d = '0;
        end else begin
          pkt_ptr_d = pkt_ptr_q + PTR_W'(SYM_PER_CLK);
        end
      end
      default: mode_d = ST_OS;
    endcase
  end

  always_comb begin
    sym_data_o  = '0;
    sym_datak_o = '0;
    sym_os_d_o  = '0;
    sym_tmp     = '0;
    stream_idx  = '0;
    if (take_dllp || (mode_q == ST_PKT)) begin
      // Stripe: symbol time s, then lanes 0..LANES-1 (SDP starts on Lane 0).
      for (int unsigned s = 0; s < SYMS; s++) begin
        for (int unsigned l = 0; l < LANES; l++) begin
          if (take_dllp)
            stream_idx = PTR_W'(s * LANES + l);
          else
            stream_idx = pkt_ptr_q + PTR_W'(s * LANES + l);
          if (take_dllp)
            sym_tmp = pkt_symbol(stream_idx[3:0], dll_tx_beat_i.data);
          else
            sym_tmp = pkt_symbol(stream_idx[3:0], pkt_q);
          if (lane_en_i[l]) begin
            sym_data_o[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            sym_datak_o[SYMS*l + s]                  = sym_tmp[8];
          end
        end
      end
    end else begin
      for (int unsigned l = 0; l < LANES; l++) begin
        for (int unsigned s = 0; s < SYMS; s++) begin
          sym_tmp = os_symbol(cur, 4'(ptr_q + 5'(s)), tx_lane_num_i[8*l +: 8]);
          if (lane_en_i[l]) begin
            sym_data_o[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            sym_datak_o[SYMS*l + s]                  = sym_tmp[8];
            if (!sym_tmp[8] &&
                ((cur == RIVET_MAC_OS_TS1) || (cur == RIVET_MAC_OS_TS2)))
              sym_os_d_o[SYMS*l + s] = 1'b1;
          end
        end
      end
    end
  end

  assign sym_valid_o = take_dllp || (mode_q == ST_PKT) || (cur != RIVET_MAC_OS_NONE);

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cur_q     <= RIVET_MAC_OS_NONE;
      ptr_q     <= '0;
      sent_q    <= '0;
      mode_q    <= ST_OS;
      pkt_q     <= '0;
      pkt_ptr_q <= '0;
      skp_sym_q <= '0;
    end else begin
      mode_q    <= mode_d;
      pkt_q     <= pkt_d;
      pkt_ptr_q <= pkt_ptr_d;

      if (mode_q == ST_PKT || take_dllp) begin
        // Freeze OS pointer while framing a packet.
        cur_q <= RIVET_MAC_OS_IDLE;
        ptr_q <= '0;
      end else begin
        cur_q <= cur;
        ptr_q <= (cur == RIVET_MAC_OS_NONE) ? 5'd0 : ptr_next;
      end

      if (os_cnt_clr_i) begin
        sent_q <= '0;
      end else if ((mode_q == ST_OS) && !take_dllp && (cur == RIVET_MAC_OS_IDLE)) begin
        if (sent_q < (CNT_MAX - SYMS_C)) sent_q <= sent_q + SYMS_C;
      end else if ((mode_q == ST_OS) && !take_dllp && set_done &&
                   (cur != RIVET_MAC_OS_NONE)) begin
        if (sent_q != CNT_MAX) sent_q <= sent_q + 1'b1;
      end

      // L0 Symbol-Time counter for SKP scheduling. Reset outside L0 and after
      // each completed SKP OS so the next interval starts cleanly.
      if (!pkt_en_i) begin
        skp_sym_q <= '0;
      end else if (skp_finishing) begin
        skp_sym_q <= '0;
      end else if (skp_sym_q < SKP_CNT_W'(SKP_INTERVAL_SYM)) begin
        // Count Symbol Times while TX is live (Idle, SKP body, or DLLP).
        if (take_dllp || (mode_q == ST_PKT) || (cur != RIVET_MAC_OS_NONE)) begin
          if (skp_sym_q <= (SKP_CNT_W'(SKP_INTERVAL_SYM) - SKP_CNT_W'(SYMS)))
            skp_sym_q <= skp_sym_q + SKP_CNT_W'(SYMS);
          else
            skp_sym_q <= SKP_CNT_W'(SKP_INTERVAL_SYM);
        end
      end
    end
  end

  assign os_sent_cnt_o = sent_q;

endmodule : rivet_mac_os_tx
