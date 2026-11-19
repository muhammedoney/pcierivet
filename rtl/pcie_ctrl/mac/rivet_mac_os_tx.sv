// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC ordered-set / TS transmitter (Gen2, 8b/10b symbol plane).
//
// Streams the ordered set the LTSSM asks for and, when L0 packet enable is high,
// may insert SKP OS (Gen1/Gen2 clock compensation), framed DLLP
// (SDP + 6 bytes + END), and framed TLP (STP + bytes + END) striped across
// the enabled lanes (1, 2, or 4). TLP beats are collected to EOP into a
// 32x64b distributed LUTRAM with a 16-byte shift buffer at the head so each
// 250 MHz pclk only shifts 16 bytes instead of a 160-byte register. Symbol
// outputs are registered on pclk.

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

  // DLL payload
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
  localparam int unsigned CNT_W       = 12;
  localparam int unsigned PTR_W       = 7;
  localparam int unsigned TLP_RAM_N   = 32;

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

  function automatic logic [7:0] keep_nbytes(input logic [7:0] k);
    return 8'(k[0]) + 8'(k[1]) + 8'(k[2]) + 8'(k[3]) +
           8'(k[4]) + 8'(k[5]) + 8'(k[6]) + 8'(k[7]);
  endfunction

  // Framed DLLP stream: [0]=SDP, [1..6]=bytes, [7]=END; else Logical Idle.
  function automatic logic [8:0] pkt_symbol(input logic [6:0] idx,
                                            input logic [63:0] dllp);
    logic [8:0] sym;
    if (idx == 7'd0)
      sym = {1'b1, RIVET_SYM_SDP};
    else if (idx == 7'(RIVET_DLLP_FRAMED_LEN - 1))
      sym = {1'b1, RIVET_SYM_END};
    else if (idx < 7'(RIVET_DLLP_FRAMED_LEN))
      sym = {1'b0, dllp[8*(idx-1) +: 8]};
    else
      sym = {1'b0, 8'h00};
    return sym;
  endfunction

  // Low 8 payload bytes only from the 16-byte head buffer.
  function automatic logic [7:0] head_byte(input logic [63:0] head,
                                           input logic [2:0]  sel);
    case (sel)
      3'd0: return head[ 7: 0];
      3'd1: return head[15: 8];
      3'd2: return head[23:16];
      3'd3: return head[31:24];
      3'd4: return head[39:32];
      3'd5: return head[47:40];
      3'd6: return head[55:48];
      default: return head[63:56];
    endcase
  endfunction

  typedef enum logic [1:0] {
    ST_OS      = 2'b00,
    ST_PKT     = 2'b01,
    ST_TLP_COL = 2'b10,
    ST_TLP_EM  = 2'b11
  } tx_mode_e;

  tx_mode_e           mode_q, mode_d;
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
  logic [2:0]             n_en;
  logic [4:0]             sym_step;
  logic                   dllp_ok;
  logic                   tlp_ok;
  logic                   want_pkt;
  logic                   want_tlp;
  logic                   take_tlp_start;
  logic                   take_tlp_col;
  logic                   want_skp;
  logic                   skp_due;
  logic                   skp_due_q;
  logic                   skp_finishing;
  logic                   in_pkt_emit;
  logic [PTR_W-1:0]       stream_idx;
  logic [SKP_CNT_W-1:0]   skp_sym_q;

  // 32x64b distributed LUTRAM + 16-byte head shift register for TLP emit
  (* ram_style = "distributed" *) logic [63:0] tlp_ram [0:TLP_RAM_N-1];
  logic                   tlp_ram_we;
  logic [4:0]             tlp_ram_waddr;
  logic [63:0]            tlp_ram_wdata;
  logic [63:0]            tlp_ram_rdata;

  logic [127:0]           emit_buf_q, emit_buf_d;
  logic [4:0]             emit_cnt_q, emit_cnt_d;
  logic [4:0]             tlp_wr_slot_q, tlp_wr_slot_d;
  logic [4:0]             tlp_rd_slot_q, tlp_rd_slot_d;
  logic [7:0]             tlp_len_q, tlp_len_d;
  logic [7:0]             tlp_pos_q, tlp_pos_d;
  logic                   tlp_em_done;

  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_d, sym_data_q;
  logic [2*LANES-1:0]               sym_datak_d, sym_datak_q;
  logic [2*LANES-1:0]               sym_os_d_d, sym_os_d_q;
  logic                             sym_valid_d, sym_valid_q;

`ifndef SYNTHESIS
  initial begin
    for (int unsigned ii = 0; ii < TLP_RAM_N; ii++) tlp_ram[ii] = '0;
  end
`endif

  assign tlp_ram_rdata = tlp_ram[tlp_rd_slot_q];

  always_ff @(posedge pclk_i) begin
    if (tlp_ram_we)
      tlp_ram[tlp_ram_waddr] <= tlp_ram_wdata;
  end

  assign at_boundary  = (ptr_q == 5'd0) && (mode_q == ST_OS);
  assign transmitting = os_req_valid_i && (os_req_i != RIVET_MAC_OS_NONE);
  // L0: SKP preempts Idle/DLLP/TLP at OS boundaries (never mid-packet / mid-OS).
  assign skp_due  = pkt_en_i && skp_due_q;
  assign want_skp = PKT_OK && skp_due && at_boundary;
  assign cur = at_boundary
      ? (want_skp ? RIVET_MAC_OS_SKP
                  : (transmitting ? os_req_i : RIVET_MAC_OS_NONE))
      : cur_q;
  assign len          = os_length(cur);
  assign set_done     = (ptr_q + 5'(SYMS)) >= len;
  assign ptr_next     = set_done ? 5'd0 : (ptr_q + 5'(SYMS));

  assign dllp_ok = dll_tx_valid_i &&
                   (dll_tx_beat_i.pkt_type == RIVET_MAC_PKT_DLLP) &&
                   dll_tx_beat_i.sop && dll_tx_beat_i.eop &&
                   (dll_tx_beat_i.keep == 8'hFF);
  assign tlp_ok = dll_tx_valid_i &&
                  (dll_tx_beat_i.pkt_type == RIVET_MAC_PKT_TLP) &&
                  (dll_tx_beat_i.keep != 8'h00);

  // Insert DLLP only between Idle OS boundaries while packet-enabled (SKP first).
  assign want_pkt = PKT_OK && pkt_en_i && at_boundary && !want_skp &&
                    (cur == RIVET_MAC_OS_IDLE) && dllp_ok;
  assign want_tlp = PKT_OK && pkt_en_i && at_boundary && !want_skp &&
                    (cur == RIVET_MAC_OS_IDLE) && tlp_ok && dll_tx_beat_i.sop &&
                    !dllp_ok;
  assign take_dllp      = want_pkt;
  assign take_tlp_start = want_tlp;
  assign take_tlp_col   = (mode_q == ST_TLP_COL) && tlp_ok;
  assign dll_tx_ready_o = take_dllp || take_tlp_start || take_tlp_col;

  always_comb begin
    n_en = '0;
    for (int unsigned li = 0; li < LANES; li++)
      if (lane_en_i[li]) n_en = n_en + 3'd1;
    if (n_en == 3'd0) n_en = 3'(LANES);
    sym_step = 5'(n_en) * 5'(SYMS);
  end

  assign pkt_done    = (pkt_ptr_q + PTR_W'(sym_step)) >= PTR_W'(RIVET_DLLP_FRAMED_LEN);
  assign tlp_em_done = (tlp_pos_q + 8'(sym_step)) >= (tlp_len_q + 8'd2);
  assign in_pkt_emit = take_dllp || (mode_q == ST_PKT) || (mode_q == ST_TLP_EM);
  assign skp_finishing =
      (mode_q == ST_OS) && !in_pkt_emit && set_done && (cur == RIVET_MAC_OS_SKP);

  always_comb begin
    logic [63:0]  masked_beat;
    logic [7:0]   beat_n;
    logic [3:0]   take_b;
    logic [127:0] shifted;
    logic [4:0]   rem_cnt;

    tlp_ram_we    = 1'b0;
    tlp_ram_waddr = tlp_wr_slot_q;
    masked_beat   = '0;
    for (int unsigned i = 0; i < 8; i++) begin
      if (dll_tx_beat_i.keep[i])
        masked_beat[8*i +: 8] = dll_tx_beat_i.data[8*i +: 8];
    end
    tlp_ram_wdata = masked_beat;

    emit_buf_d    = emit_buf_q;
    emit_cnt_d    = emit_cnt_q;
    tlp_wr_slot_d = tlp_wr_slot_q;
    tlp_rd_slot_d = tlp_rd_slot_q;
    tlp_len_d     = tlp_len_q;
    beat_n        = keep_nbytes(dll_tx_beat_i.keep);
    take_b        = '0;
    shifted       = emit_buf_q;
    rem_cnt       = emit_cnt_q;

    if (take_tlp_start) begin
      tlp_ram_we    = 1'b1;
      tlp_ram_waddr = 5'd0;
      emit_buf_d    = {64'd0, masked_beat};
      emit_cnt_d    = 5'd8;
      tlp_wr_slot_d = 5'd1;
      tlp_rd_slot_d = 5'd1;
      tlp_len_d     = beat_n;
    end else if (take_tlp_col) begin
      tlp_ram_we    = 1'b1;
      tlp_ram_waddr = tlp_wr_slot_q;
      tlp_wr_slot_d = tlp_wr_slot_q + 5'd1;
      tlp_len_d     = tlp_len_q + beat_n;
      if (tlp_wr_slot_q == 5'd1) begin
        emit_buf_d[127:64] = masked_beat;
      end
      if (dll_tx_beat_i.eop) begin
        emit_cnt_d    = 5'd16;
        tlp_rd_slot_d = 5'd2;
      end
    end else if ((mode_q == ST_TLP_EM) && !tlp_em_done) begin
      // Every non-final emit cycle consumes sym_step-1 bytes on the STP beat
      // and sym_step bytes thereafter ({1,2,3,4,7,8} only).
      take_b = (tlp_pos_q == 8'd0) ? (sym_step[3:0] - 4'd1) : sym_step[3:0];
      unique case (take_b)
        4'd1:    shifted = { 8'd0, emit_buf_q[127: 8]};
        4'd2:    shifted = {16'd0, emit_buf_q[127:16]};
        4'd3:    shifted = {24'd0, emit_buf_q[127:24]};
        4'd4:    shifted = {32'd0, emit_buf_q[127:32]};
        4'd7:    shifted = {56'd0, emit_buf_q[127:56]};
        default: shifted = {64'd0, emit_buf_q[127:64]};
      endcase
      rem_cnt = emit_cnt_q - {1'b0, take_b};
      if ((rem_cnt <= 5'd8) && (tlp_rd_slot_q < tlp_wr_slot_q)) begin
        unique case (rem_cnt[3:0])
          4'd0:    emit_buf_d = {64'd0, tlp_ram_rdata};
          4'd1:    emit_buf_d = {56'd0, tlp_ram_rdata, shifted[ 7:0]};
          4'd2:    emit_buf_d = {48'd0, tlp_ram_rdata, shifted[15:0]};
          4'd3:    emit_buf_d = {40'd0, tlp_ram_rdata, shifted[23:0]};
          4'd4:    emit_buf_d = {32'd0, tlp_ram_rdata, shifted[31:0]};
          4'd5:    emit_buf_d = {24'd0, tlp_ram_rdata, shifted[39:0]};
          4'd6:    emit_buf_d = {16'd0, tlp_ram_rdata, shifted[47:0]};
          4'd7:    emit_buf_d = { 8'd0, tlp_ram_rdata, shifted[55:0]};
          default: emit_buf_d = {       tlp_ram_rdata, shifted[63:0]};
        endcase
        emit_cnt_d    = rem_cnt + 5'd8;
        tlp_rd_slot_d = tlp_rd_slot_q + 5'd1;
      end else begin
        emit_buf_d = shifted;
        emit_cnt_d = rem_cnt;
      end
    end
  end

  always_comb begin
    mode_d    = mode_q;
    pkt_d     = pkt_q;
    pkt_ptr_d = pkt_ptr_q;
    tlp_pos_d = tlp_pos_q;
    unique case (mode_q)
      ST_OS: begin
        if (take_dllp) begin
          pkt_d = dll_tx_beat_i.data;
          // First cycle already emits symbols 0..sym_step-1.
          if (sym_step >= RIVET_DLLP_FRAMED_LEN) begin
            mode_d    = ST_OS;
            pkt_ptr_d = '0;
          end else begin
            mode_d    = ST_PKT;
            pkt_ptr_d = PTR_W'(sym_step);
          end
        end else if (take_tlp_start) begin
          // Buffer updates this cycle; STP goes out on the next pclk.
          tlp_pos_d = '0;
          pkt_ptr_d = '0;
          mode_d    = dll_tx_beat_i.eop ? ST_TLP_EM : ST_TLP_COL;
        end
      end
      ST_PKT: begin
        if (pkt_done) begin
          mode_d    = ST_OS;
          pkt_ptr_d = '0;
        end else begin
          pkt_ptr_d = pkt_ptr_q + PTR_W'(sym_step);
        end
      end
      ST_TLP_COL: begin
        if (take_tlp_col && dll_tx_beat_i.eop) begin
          mode_d    = ST_TLP_EM;
          tlp_pos_d = '0;
          pkt_ptr_d = '0;
        end
      end
      ST_TLP_EM: begin
        if (tlp_em_done) begin
          mode_d    = ST_OS;
          tlp_pos_d = '0;
          pkt_ptr_d = '0;
        end else begin
          tlp_pos_d = tlp_pos_q + 8'(sym_step);
        end
      end
      default: mode_d = ST_OS;
    endcase
  end

  always_comb begin
    sym_data_d  = '0;
    sym_datak_d = '0;
    sym_os_d_d  = '0;
    sym_tmp     = '0;
    stream_idx  = '0;
    if (take_dllp || (mode_q == ST_PKT)) begin
      // Stripe each symbol time across enabled lanes only (SDP on logical 0).
      for (int unsigned s = 0; s < SYMS; s++) begin
        automatic int unsigned ord = 0;
        for (int unsigned l = 0; l < LANES; l++) begin
          if (lane_en_i[l]) begin
            if (take_dllp)
              stream_idx = PTR_W'(s * int'(n_en) + ord);
            else
              stream_idx = pkt_ptr_q + PTR_W'(s * int'(n_en) + ord);
            if (take_dllp)
              sym_tmp = pkt_symbol(stream_idx[6:0], dll_tx_beat_i.data);
            else
              sym_tmp = pkt_symbol(stream_idx[6:0], pkt_q);
            sym_data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            sym_datak_d[SYMS*l + s]                  = sym_tmp[8];
            ord++;
          end
        end
      end
    end else if (mode_q == ST_TLP_EM) begin
      for (int unsigned s = 0; s < SYMS; s++) begin
        automatic int unsigned ord = 0;
        for (int unsigned l = 0; l < LANES; l++) begin
          if (lane_en_i[l]) begin
            automatic logic [7:0] idx;
            automatic logic [2:0] boff;
            automatic int unsigned sym_i;
            sym_i = s * int'(n_en) + ord;
            idx   = tlp_pos_q + 8'(sym_i);
            if (idx == 8'd0) begin
              sym_tmp = {1'b1, RIVET_SYM_STP};
            end else if (idx == (tlp_len_q + 8'd1)) begin
              sym_tmp = {1'b1, RIVET_SYM_END};
            end else if ((idx != 8'd0) && (idx <= tlp_len_q)) begin
              boff = (tlp_pos_q == 8'd0) ? (3'(sym_i) - 3'd1) : 3'(sym_i);
              sym_tmp = {1'b0, head_byte(emit_buf_q[63:0], boff)};
            end else begin
              sym_tmp = {1'b0, 8'h00};
            end
            sym_data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            sym_datak_d[SYMS*l + s]                  = sym_tmp[8];
            ord++;
          end
        end
      end
    end else begin
      for (int unsigned l = 0; l < LANES; l++) begin
        for (int unsigned s = 0; s < SYMS; s++) begin
          sym_tmp = os_symbol(cur, 4'(ptr_q + 5'(s)), tx_lane_num_i[8*l +: 8]);
          if (lane_en_i[l]) begin
            sym_data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            sym_datak_d[SYMS*l + s]                  = sym_tmp[8];
            if (!sym_tmp[8] &&
                ((cur == RIVET_MAC_OS_TS1) || (cur == RIVET_MAC_OS_TS2)))
              sym_os_d_d[SYMS*l + s] = 1'b1;
          end
        end
      end
    end
  end

  assign sym_valid_d = take_dllp ||
                       (mode_q == ST_PKT) || (mode_q == ST_TLP_EM) ||
                       (cur != RIVET_MAC_OS_NONE);

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cur_q         <= RIVET_MAC_OS_NONE;
      ptr_q         <= '0;
      sent_q        <= '0;
      mode_q        <= ST_OS;
      pkt_q         <= '0;
      pkt_ptr_q     <= '0;
      skp_sym_q     <= '0;
      skp_due_q     <= 1'b0;
      emit_buf_q    <= '0;
      emit_cnt_q    <= '0;
      tlp_wr_slot_q <= '0;
      tlp_rd_slot_q <= '0;
      tlp_len_q     <= '0;
      tlp_pos_q     <= '0;
      sym_data_q    <= '0;
      sym_datak_q   <= '0;
      sym_os_d_q    <= '0;
      sym_valid_q   <= 1'b0;
    end else begin
      mode_q        <= mode_d;
      pkt_q         <= pkt_d;
      pkt_ptr_q     <= pkt_ptr_d;
      emit_buf_q    <= emit_buf_d;
      emit_cnt_q    <= emit_cnt_d;
      tlp_wr_slot_q <= tlp_wr_slot_d;
      tlp_rd_slot_q <= tlp_rd_slot_d;
      tlp_len_q     <= tlp_len_d;
      tlp_pos_q     <= tlp_pos_d;
      sym_data_q    <= sym_data_d;
      sym_datak_q   <= sym_datak_d;
      sym_os_d_q    <= sym_os_d_d;
      sym_valid_q   <= sym_valid_d;

      if (in_pkt_emit) begin
        // Freeze OS pointer while framing a packet.
        cur_q <= RIVET_MAC_OS_IDLE;
        ptr_q <= '0;
      end else begin
        cur_q <= cur;
        ptr_q <= (cur == RIVET_MAC_OS_NONE) ? 5'd0 : ptr_next;
      end

      if (os_cnt_clr_i) begin
        sent_q <= '0;
      end else if ((mode_q == ST_OS) && !in_pkt_emit && (cur == RIVET_MAC_OS_IDLE)) begin
        if (sent_q < (CNT_MAX - SYMS_C)) sent_q <= sent_q + SYMS_C;
      end else if ((mode_q == ST_OS) && !in_pkt_emit && set_done &&
                   (cur != RIVET_MAC_OS_NONE)) begin
        if (sent_q != CNT_MAX) sent_q <= sent_q + 1'b1;
      end

      // L0 Symbol-Time counter for SKP scheduling. Reset outside L0 and after
      // each completed SKP OS so the next interval starts cleanly.
      if (!pkt_en_i || skp_finishing) begin
        skp_sym_q <= '0;
        skp_due_q <= 1'b0;
      end else if (skp_sym_q < SKP_CNT_W'(SKP_INTERVAL_SYM)) begin
        if (in_pkt_emit || (cur != RIVET_MAC_OS_NONE)) begin
          if (skp_sym_q <= (SKP_CNT_W'(SKP_INTERVAL_SYM) - SKP_CNT_W'(SYMS))) begin
            skp_sym_q <= skp_sym_q + SKP_CNT_W'(SYMS);
            skp_due_q <= ((skp_sym_q + SKP_CNT_W'(SYMS)) >= SKP_CNT_W'(SKP_INTERVAL_SYM));
          end else begin
            skp_sym_q <= SKP_CNT_W'(SKP_INTERVAL_SYM);
            skp_due_q <= 1'b1;
          end
        end
      end else begin
        skp_due_q <= 1'b1;
      end
    end
  end

  assign sym_data_o    = sym_data_q;
  assign sym_datak_o   = sym_datak_q;
  assign sym_os_d_o    = sym_os_d_q;
  assign sym_valid_o   = sym_valid_q;
  assign os_sent_cnt_o = sent_q;

endmodule : rivet_mac_os_tx
