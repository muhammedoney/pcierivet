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
  input  logic [2:0] rate_i = rivet_pkg::RIVET_PIPE_RATE_GEN2,

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
  // Gen3 TS bytes 6 and 7. Zero outside equalization.
  input  logic [7:0]                    tx_eq_ctrl_i = 8'h00,
  input  logic [7:0]                    tx_eq_data_i = 8'h00,

  // DLL payload
  input  rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_i,
  input  logic                              dll_tx_valid_i,
  output logic                              dll_tx_ready_o,

  // Symbol stream toward scrambler / pipe adapter (per-link packed)
  output logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_o,
  output logic [2*LANES-1:0]               sym_datak_o,
  output logic [2*LANES-1:0]               sym_os_d_o, // 1 = Ordered-Set D (scramble bypass)
  output logic                             sym_valid_o,
  output logic                             sym_blk_start_o,

  // Ordered sets completed (Idle counts symbols) since os_cnt_clr_i
  output logic [11:0]                      os_sent_cnt_o
);

  import rivet_pkg::*;

  localparam int unsigned SYMS        = PIPE_DATA_WIDTH / 8;
  localparam int unsigned CNT_W       = 12;
  localparam int unsigned PTR_W       = 7;
  // One framed TLP, 8 bytes per word. 516 covers a 4096-byte payload.
  localparam int unsigned TLP_RAM_N   = RIVET_TLP_SLOT_BYTES / 8;
  localparam int unsigned TLP_AW      = $clog2(TLP_RAM_N);

  localparam logic [CNT_W-1:0] SYMS_C  = CNT_W'(SYMS);
  localparam logic [CNT_W-1:0] CNT_MAX = {CNT_W{1'b1}};

  // Packet framing for Gen2 16-bit PIPE on legal widths.
  localparam bit PKT_OK = (PIPE_DATA_WIDTH == 16);
  localparam int unsigned SKP_CNT_W = 12;

`ifndef SYNTHESIS
  initial begin
    // 32 elaborates for Gen3. 64 elaborates for Gen4. The 64-bit block
    // pipe is a later slice.
    if (!(PIPE_DATA_WIDTH == 16 || PIPE_DATA_WIDTH == 32 ||
          PIPE_DATA_WIDTH == 64))
      $error("rivet_mac_os_tx: PIPE_DATA_WIDTH must be 16, 32, or 64 (got %0d)",
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
    if (rivet_pkg::rivet_pipe_block_rate(rate_i)) begin
      case (os_type)
        RIVET_MAC_OS_TS1, RIVET_MAC_OS_TS2: begin
          case (idx)
            4'd0:    sym = (os_type == RIVET_MAC_OS_TS1) ? {1'b0, RIVET_SYM_TS1_BLK}
                                                         : {1'b0, RIVET_SYM_TS2_BLK};
            4'd1:    sym = tx_link_pad_i ? {1'b0, RIVET_SYM_PAD} : {1'b0, tx_link_num_i};
            4'd2:    sym = tx_lane_pad_i ? {1'b0, RIVET_SYM_PAD} : {1'b0, lane_num};
            4'd3:    sym = {1'b0, tx_n_fts_i};
            4'd4:    sym = {1'b0, tx_rate_id_i};
            4'd5:    sym = {1'b0, tx_train_ctrl_i};
            4'd6:    sym = {1'b0, tx_eq_ctrl_i};
            4'd7:    sym = {1'b0, tx_eq_data_i};
            default: sym = {1'b0, 8'h00};
          endcase
        end
        RIVET_MAC_OS_SKP:  sym = {1'b1, RIVET_SYM_SKP_BLK};
        RIVET_MAC_OS_EIOS: sym = {1'b0, RIVET_SYM_EIOS_BLK};
        RIVET_MAC_OS_FTS:  sym = {1'b0, RIVET_SYM_FTS};
        default:           sym = {1'b0, 8'h00};
      endcase
      return sym;
    end
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
    if (rivet_pkg::rivet_pipe_block_rate(rate_i) &&
        ((os_type == RIVET_MAC_OS_TS1) || (os_type == RIVET_MAC_OS_TS2) ||
         (os_type == RIVET_MAC_OS_SKP) || (os_type == RIVET_MAC_OS_EIOS) ||
         (os_type == RIVET_MAC_OS_FTS)))
      return 5'd16;
    case (os_type)
      RIVET_MAC_OS_TS1,
      RIVET_MAC_OS_TS2:  return 5'(RIVET_TS_LEN);
      RIVET_MAC_OS_SKP,
      RIVET_MAC_OS_FTS,
      RIVET_MAC_OS_EIOS: return 5'(RIVET_SHORT_OS_LEN);
      default:           return 5'(SYMS);
    endcase
  endfunction

  function automatic logic [7:0] keep_nbytes(input logic [15:0] k);
    logic [7:0] n;
    n = '0;
    for (int unsigned i = 0; i < 16; i++)
      n += 8'(k[i]);
    return n;
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
  logic [1:0]             word_q;
  // Gen3 may start the next TLP in the middle of a data block. Waiting
  // for word 0 inserts idle tokens between posted writes.
  logic                   tlp_follow_q;

  // Block RAM: a 4 KB frame does not belong in the old 32-deep LUTRAM.
  (* ram_style = "block" *) logic [63:0] tlp_ram [0:TLP_RAM_N-1];
  logic                   tlp_ram_we, tlp_ram_we2;
  logic [TLP_AW-1:0]      tlp_ram_waddr, tlp_ram_waddr2;
  logic [63:0]            tlp_ram_wdata, tlp_ram_wdata2;
  logic [63:0]            tlp_ram_rdata;
  logic [63:0]            tlp_ram_rdata_b;

  // 32-byte window. Gen3 reads two 8-byte RAM words per cycle.
  logic [255:0]           emit_buf_q, emit_buf_d;
  logic [5:0]             emit_cnt_q, emit_cnt_d;
  logic [TLP_AW-1:0]      tlp_wr_slot_q, tlp_wr_slot_d;
  logic [TLP_AW-1:0]      tlp_rd_slot_q, tlp_rd_slot_d;
  logic [15:0]            tlp_len_q, tlp_len_d;
  // Gen3 STP length, known from the TLP header in the first DLL beat.
  logic [15:0]            frame_len_q, frame_len_d;
  logic [15:0]            tlp_pos_q, tlp_pos_d;
  logic                   tlp_em_done;
  // Flow: STP is already on the wire while later beats of this TLP are accepted.
  logic                   tlp_flow_q, tlp_flow_d;
  // Closed: the EOP beat has been accepted.
  // Gen2 END is at tlp_len+1. Gen3 has no END; the frame is STP + length + tlp_len.
  logic                   tlp_closed_q, tlp_closed_d;
  logic                   emit_fire;
  logic [4:0]             take_b_c;
  logic                   gen3_pkt;
  logic [4:0]             slot_b;
  logic [15:0]            pay_sent;
  logic [15:0]            pay_left;

  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_d, sym_data_q;
  logic [2*LANES-1:0]               sym_datak_d, sym_datak_q;
  logic [2*LANES-1:0]               sym_os_d_d, sym_os_d_q;
  logic                             sym_valid_d, sym_valid_q;
  logic                             sym_blk_start_d, sym_blk_start_q;

`ifndef SYNTHESIS
  initial begin
    for (int unsigned ii = 0; ii < TLP_RAM_N; ii++) tlp_ram[ii] = '0;
  end
`endif

  assign tlp_ram_rdata   = tlp_ram[tlp_rd_slot_q];
  assign tlp_ram_rdata_b = tlp_ram[tlp_rd_slot_q + TLP_AW'(1)];

  always_ff @(posedge pclk_i) begin
    if (tlp_ram_we)
      tlp_ram[tlp_ram_waddr] <= tlp_ram_wdata;
    if (tlp_ram_we2)
      tlp_ram[tlp_ram_waddr2] <= tlp_ram_wdata2;
  end

  assign at_boundary  = (ptr_q == 5'd0) && (mode_q == ST_OS);
  assign transmitting = os_req_valid_i && (os_req_i != RIVET_MAC_OS_NONE);
  // L0: SKP preempts Idle/DLLP/TLP at OS boundaries (never mid-packet / mid-OS).
  assign skp_due  = pkt_en_i && skp_due_q;
  // Gen3 SKP is one 16-byte block and starts only on a block boundary.
  assign want_skp = skp_due && at_boundary &&
                    (PKT_OK || ((gen3_pkt) && (word_q == 2'd0)));
  assign cur = at_boundary
      ? (want_skp ? RIVET_MAC_OS_SKP
                  : (transmitting ? os_req_i : RIVET_MAC_OS_NONE))
      : cur_q;
  // Gen1/Gen2 use the low 16 bits. Gen3 uses four symbols. Gen4 uses eight.
  wire [4:0] os_step;
  assign os_step = 5'(rivet_pkg::rivet_pipe_nsym(rate_i));
  assign len          = os_length(cur);
  assign set_done     = (ptr_q + os_step) >= len;
  assign ptr_next     = set_done ? 5'd0 : (ptr_q + os_step);

  // A DLLP is one 8-byte beat. A TLP may use the high half at Gen3.
  assign dllp_ok = dll_tx_valid_i &&
                   (dll_tx_beat_i.pkt_type == RIVET_MAC_PKT_DLLP) &&
                   dll_tx_beat_i.sop && dll_tx_beat_i.eop &&
                   (dll_tx_beat_i.keep[7:0] == 8'hFF) &&
                   (dll_tx_beat_i.keep[15:8] == 8'h00);
  assign tlp_ok = dll_tx_valid_i &&
                  (dll_tx_beat_i.pkt_type == RIVET_MAC_PKT_TLP) &&
                  (dll_tx_beat_i.keep != 8'h00);

  // Insert DLLP only between Idle OS boundaries while packet-enabled (SKP first).
  // Gen3 uses the same beat stream inside a 128b/130b data block. The token
  // byte is not a K-symbol; Gen2 STP/END stay on the K path.
  wire pkt_rate_ok = PKT_OK ||
                     ((gen3_pkt) && (word_q == 2'd0));
  wire tlp_rate_ok = pkt_rate_ok ||
                     ((gen3_pkt) && tlp_follow_q);
  assign want_pkt = pkt_rate_ok && pkt_en_i && at_boundary && !want_skp &&
                    (cur == RIVET_MAC_OS_IDLE) && dllp_ok;
  assign want_tlp = tlp_rate_ok && pkt_en_i && at_boundary && !want_skp &&
                    (cur == RIVET_MAC_OS_IDLE) && tlp_ok && dll_tx_beat_i.sop &&
                    !dllp_ok;
  assign take_dllp      = want_pkt;
  assign take_tlp_start = want_tlp;
  assign take_tlp_col   = (mode_q == ST_TLP_COL) && tlp_ok;
  assign dll_tx_ready_o = take_dllp || take_tlp_start || take_tlp_col;

  always_comb begin
    int unsigned step_i;
    n_en = '0;
    for (int unsigned li = 0; li < LANES; li++)
      if (lane_en_i[li]) n_en = n_en + 3'd1;
    if (n_en == 3'd0) n_en = 3'(LANES);
    // Gen3 on a 64-bit pipe is four symbols, so a x4 step stays 16.
    // A Gen4 x4 step is 32 and does not fit this 5-bit count; clamp so a
    // DLLP still completes instead of adding a zero stride forever.
    step_i   = int'(n_en) * rivet_pkg::rivet_pipe_nsym(rate_i);
    sym_step = (step_i > 31) ? 5'd31 : 5'(step_i);
  end

  assign pkt_done    = (pkt_ptr_q + PTR_W'(sym_step)) >= PTR_W'(RIVET_DLLP_FRAMED_LEN);
  // Gen3 and Gen4 share STP + 2 length bytes + DLL bytes. Gen2 is STP + END.
  assign gen3_pkt = rivet_pkg::rivet_pipe_block_rate(rate_i);
  assign slot_b   = (tlp_pos_q == 16'd0)
                  ? ((sym_step > 5'd3) ? (sym_step - 5'd3) : 5'd0)
                  : sym_step;
  assign pay_sent = (tlp_pos_q == 16'd0) ? 16'd0 : (tlp_pos_q - 16'd3);
  assign pay_left = (tlp_len_q > pay_sent) ? (tlp_len_q - pay_sent) : 16'd0;
  assign take_b_c = gen3_pkt
      ? ((tlp_closed_q && ({11'd0, slot_b} > pay_left)) ? pay_left[4:0] : slot_b)
      : ((tlp_pos_q == 16'd0) ? {1'b0, (sym_step[3:0] - 4'd1)}
                              : {1'b0, sym_step[3:0]});
  // END exists only after EOP. Until then the length is still growing.
  assign tlp_em_done = tlp_closed_q &&
                       ((tlp_pos_q + 16'(sym_step)) >=
                        (tlp_len_q + (gen3_pkt ? 16'd3 : 16'd2)));
  assign emit_fire   = (tlp_flow_q || (mode_q == ST_TLP_EM)) && !tlp_em_done &&
                       ({1'b0, take_b_c} <= emit_cnt_q);
  assign in_pkt_emit = take_dllp || (mode_q == ST_PKT) || (mode_q == ST_TLP_EM) ||
                       tlp_flow_q;
  assign skp_finishing =
      (mode_q == ST_OS) && !in_pkt_emit && set_done && (cur == RIVET_MAC_OS_SKP);

  always_comb begin
    logic [127:0] masked_beat;
    logic [63:0]  masked_lo;
    logic [7:0]   beat_n;
    logic [4:0]   take_b;
    logic [127:0] shifted;
    logic [255:0] wide;
    logic [5:0]   rem_cnt;
    logic         wide_beat;
    logic [7:0]   frm_b0;
    logic [9:0]   frm_ldw;
    logic [15:0]  frm_hbytes, frm_pbytes;
    logic [5:0]   base_c, n_c;
    logic [255:0] merged;

    tlp_ram_we     = 1'b0;
    tlp_ram_we2    = 1'b0;
    tlp_ram_waddr  = tlp_wr_slot_q;
    tlp_ram_waddr2 = tlp_wr_slot_q;
    tlp_ram_wdata2 = '0;
    masked_beat    = '0;
    for (int unsigned i = 0; i < 16; i++) begin
      if (dll_tx_beat_i.keep[i])
        masked_beat[8*i +: 8] = dll_tx_beat_i.data[8*i +: 8];
    end
    masked_lo     = masked_beat[63:0];
    tlp_ram_wdata = masked_lo;

    emit_buf_d    = emit_buf_q;
    emit_cnt_d    = emit_cnt_q;
    tlp_wr_slot_d = tlp_wr_slot_q;
    tlp_rd_slot_d = tlp_rd_slot_q;
    tlp_len_d     = tlp_len_q;
    frame_len_d   = frame_len_q;
    beat_n        = keep_nbytes(dll_tx_beat_i.keep);
    wide_beat     = beat_n > 8'd8;
    frm_b0        = '0;
    frm_ldw       = '0;
    frm_hbytes    = '0;
    frm_pbytes    = '0;
    base_c        = '0;
    n_c           = '0;
    merged        = '0;
    take_b        = '0;
    shifted       = emit_buf_q[127:0];
    wide          = emit_buf_q;
    rem_cnt       = emit_cnt_q;

    if (take_tlp_start) begin
      tlp_ram_we    = 1'b1;
      tlp_ram_waddr = '0;
      tlp_len_d     = beat_n;
      if (wide_beat) begin
        tlp_ram_we2    = 1'b1;
        tlp_ram_waddr2 = TLP_AW'(1);
        tlp_ram_wdata2 = masked_beat[127:64];
        emit_buf_d     = {128'd0, masked_beat};
        emit_cnt_d     = 6'(beat_n);
        tlp_wr_slot_d  = TLP_AW'(2);
        tlp_rd_slot_d  = TLP_AW'(2);
      end else begin
        emit_buf_d    = {192'd0, masked_lo};
        emit_cnt_d    = 6'd8;
        tlp_wr_slot_d = TLP_AW'(1);
        tlp_rd_slot_d = TLP_AW'(1);
      end
      // STP length is the DLL frame: seq + TLP + LCRC. The header is in
      // this first beat, after the two sequence bytes.
      if ((gen3_pkt) && (beat_n >= 8'd6)) begin
        frm_b0     = masked_beat[23:16];
        frm_ldw    = {masked_beat[33:32], masked_beat[47:40]};
        frm_hbytes = frm_b0[5] ? 16'd16 : 16'd12;
        frm_pbytes = frm_b0[6] ? (((frm_ldw == 10'd0) ? 16'd1024 : {6'd0, frm_ldw}) * 16'd4)
                               : 16'd0;
        frame_len_d = 16'd6 + frm_hbytes + frm_pbytes;
      end else begin
        frame_len_d = '0;
      end
    end else if (take_tlp_col) begin
      tlp_len_d = tlp_len_q + 16'(beat_n);
      if (wide_beat) begin
        tlp_ram_we     = 1'b1;
        tlp_ram_waddr  = tlp_wr_slot_q;
        tlp_ram_we2    = 1'b1;
        tlp_ram_waddr2 = tlp_wr_slot_q + TLP_AW'(1);
        tlp_ram_wdata2 = masked_beat[127:64];
        tlp_wr_slot_d  = tlp_wr_slot_q + TLP_AW'(2);
      end else begin
        tlp_ram_we    = 1'b1;
        tlp_ram_waddr = tlp_wr_slot_q;
        tlp_wr_slot_d = tlp_wr_slot_q + TLP_AW'(1);
        if (tlp_wr_slot_q == TLP_AW'(1))
          emit_buf_d[127:64] = masked_lo;
        if (dll_tx_beat_i.eop && !tlp_flow_q) begin
          emit_cnt_d    = 6'd16;
          tlp_rd_slot_d = TLP_AW'(2);
        end else if ((tlp_wr_slot_q == TLP_AW'(1)) && !dll_tx_beat_i.eop) begin
          // 16-byte head is full and more beats follow. Emit starts next cycle.
          emit_cnt_d    = 6'd16;
          tlp_rd_slot_d = TLP_AW'(2);
        end
      end
    end
    if (emit_fire && !take_tlp_start) begin
      // Gen2 consumes sym_step-1 bytes on the STP beat and sym_step thereafter.
      // Gen3 consumes sym_step-3 on the length beat, then sym_step.
      take_b = take_b_c;
      if (gen3_pkt) begin
        wide    = emit_buf_q >> (8 * int'(take_b));
        rem_cnt = emit_cnt_q - {1'b0, take_b};
        if ((rem_cnt + 6'd16 <= 6'd32) &&
            ((tlp_rd_slot_q + TLP_AW'(1)) < tlp_wr_slot_q)) begin
          emit_buf_d = wide;
          emit_buf_d[8*int'(rem_cnt) +: 64]      = tlp_ram_rdata;
          emit_buf_d[8*int'(rem_cnt + 6'd8) +: 64] = tlp_ram_rdata_b;
          emit_cnt_d    = rem_cnt + 6'd16;
          tlp_rd_slot_d = tlp_rd_slot_q + TLP_AW'(2);
        end else if ((rem_cnt + 6'd8 <= 6'd32) &&
                     (tlp_rd_slot_q < tlp_wr_slot_q)) begin
          emit_buf_d = wide;
          emit_buf_d[8*int'(rem_cnt) +: 64] = tlp_ram_rdata;
          emit_cnt_d    = rem_cnt + 6'd8;
          tlp_rd_slot_d = tlp_rd_slot_q + TLP_AW'(1);
        end else begin
          emit_buf_d = wide;
          emit_cnt_d = rem_cnt;
        end
      end else begin
      unique case (take_b)
        5'd1:    shifted = { 8'd0, emit_buf_q[127: 8]};
        5'd2:    shifted = {16'd0, emit_buf_q[127:16]};
        5'd3:    shifted = {24'd0, emit_buf_q[127:24]};
        5'd4:    shifted = {32'd0, emit_buf_q[127:32]};
        5'd7:    shifted = {56'd0, emit_buf_q[127:56]};
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
        tlp_rd_slot_d = tlp_rd_slot_q + TLP_AW'(1);
      end else begin
        emit_buf_d = shifted;
        emit_cnt_d = rem_cnt;
      end
      end
    end
    // The beat accepted this cycle is not visible in the RAM read yet.
    // Append it after any consume so the next symbol-time is not short.
    if (gen3_pkt && take_tlp_col && (tlp_rd_slot_q == tlp_wr_slot_q) &&
        (beat_n != 8'd0)) begin
      n_c    = 6'(beat_n);
      base_c = emit_cnt_d;
      merged = emit_buf_d;
      if (({1'b0, base_c} + {1'b0, n_c}) <= 7'd32) begin
        for (int unsigned i = 0; i < 16; i++) begin
          if (6'(i) < n_c)
            merged[8*(int'(base_c) + i) +: 8] = masked_beat[8*i +: 8];
        end
        emit_buf_d    = merged;
        emit_cnt_d    = base_c + n_c;
        tlp_rd_slot_d = tlp_wr_slot_d;
      end
    end
  end

  always_comb begin
    mode_d       = mode_q;
    pkt_d        = pkt_q;
    pkt_ptr_d    = pkt_ptr_q;
    tlp_pos_d    = tlp_pos_q;
    tlp_flow_d   = tlp_flow_q;
    tlp_closed_d = tlp_closed_q;
    unique case (mode_q)
      ST_OS: begin
        tlp_flow_d   = 1'b0;
        tlp_closed_d = 1'b0;
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
          // Gen3 already knows the frame length, so emit overlaps collect.
          tlp_pos_d    = '0;
          pkt_ptr_d    = '0;
          tlp_closed_d = dll_tx_beat_i.eop;
          mode_d       = dll_tx_beat_i.eop ? ST_TLP_EM : ST_TLP_COL;
          if ((gen3_pkt) && !dll_tx_beat_i.eop)
            tlp_flow_d = 1'b1;
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
        // Gen3 waits for EOP so the dump never inserts idle inside the length.
        if (take_tlp_col && (tlp_wr_slot_q == TLP_AW'(1)) && !dll_tx_beat_i.eop &&
            !gen3_pkt)
          tlp_flow_d = 1'b1;
        if (take_tlp_col && dll_tx_beat_i.eop) begin
          mode_d       = ST_TLP_EM;
          tlp_closed_d = 1'b1;
          if (!tlp_flow_q) begin
            tlp_pos_d = '0;
            pkt_ptr_d = '0;
          end
        end
        if (emit_fire)
          tlp_pos_d = tlp_pos_q + 16'(sym_step);
      end
      ST_TLP_EM: begin
        if (tlp_em_done) begin
          mode_d       = ST_OS;
          tlp_pos_d    = '0;
          pkt_ptr_d    = '0;
          tlp_flow_d   = 1'b0;
          tlp_closed_d = 1'b0;
        end else if (emit_fire) begin
          tlp_pos_d = tlp_pos_q + 16'(sym_step);
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
            // Gen3 frame token is a data byte. datak is 2 bits per lane.
            if (gen3_pkt)
              sym_tmp[8] = 1'b0;
            if (s < 2)
              sym_datak_d[2*l + s] = sym_tmp[8];
            ord++;
          end
        end
      end
    end else if ((mode_q == ST_TLP_EM) || tlp_flow_q) begin
      for (int unsigned s = 0; s < SYMS; s++) begin
        automatic int unsigned ord = 0;
        for (int unsigned l = 0; l < LANES; l++) begin
          if (lane_en_i[l]) begin
            automatic logic [15:0] idx;
            automatic logic [2:0] boff;
            automatic int unsigned sym_i;
            sym_i = s * int'(n_en) + ord;
            idx   = tlp_pos_q + 16'(sym_i);
            if (gen3_pkt) begin
              if (idx == 16'd0) begin
                sym_tmp = {1'b0, RIVET_SYM_STP};
              end else if (idx == 16'd1) begin
                sym_tmp = {1'b0, ((frame_len_q != 16'd0) ? frame_len_q[7:0]
                                                        : tlp_len_q[7:0])};
              end else if (idx == 16'd2) begin
                sym_tmp = {1'b0, ((frame_len_q != 16'd0) ? frame_len_q[15:8]
                                                        : tlp_len_q[15:8])};
              end else if (idx < (tlp_len_q + 16'd3)) begin
                automatic logic [15:0] poff;
                poff = (tlp_pos_q == 16'd0) ? (idx - 16'd3) : (idx - tlp_pos_q);
                sym_tmp = {1'b0, emit_buf_q[8*int'(poff[4:0]) +: 8]};
              end else begin
                sym_tmp = {1'b0, 8'h00};
              end
            end else if (idx == 16'd0) begin
              sym_tmp = {1'b1, RIVET_SYM_STP};
            end else if (tlp_closed_q && (idx == (tlp_len_q + 16'd1))) begin
              sym_tmp = {1'b1, RIVET_SYM_END};
            end else if ((idx != 16'd0) && (!tlp_closed_q || (idx <= tlp_len_q))) begin
              boff = (tlp_pos_q == 16'd0) ? (3'(sym_i) - 3'd1) : 3'(sym_i);
              sym_tmp = {1'b0, head_byte(emit_buf_q[63:0], boff)};
            end else begin
              sym_tmp = {1'b0, 8'h00};
            end
            sym_data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            if (gen3_pkt)
              sym_tmp[8] = 1'b0;
            if (s < 2)
              sym_datak_d[2*l + s] = sym_tmp[8];
            ord++;
          end
        end
      end
    end else begin
      for (int unsigned l = 0; l < LANES; l++) begin
        for (int unsigned s = 0; s < SYMS; s++) begin
          if (s >= int'(os_step))
            continue;
          sym_tmp = os_symbol(cur, 4'(ptr_q + 5'(s)), tx_lane_num_i[8*l +: 8]);
          if (lane_en_i[l]) begin
            sym_data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            if (s < 2) begin
              sym_datak_d[2*l + s] = sym_tmp[8];
              if ((!sym_tmp[8] &&
                   ((cur == RIVET_MAC_OS_TS1) || (cur == RIVET_MAC_OS_TS2))) ||
                  (rivet_pkg::rivet_pipe_block_rate(rate_i) &&
                   (cur != RIVET_MAC_OS_NONE) && (cur != RIVET_MAC_OS_IDLE)))
                sym_os_d_d[2*l + s] = 1'b1;
            end
          end
        end
      end
    end
  end

  assign sym_valid_d = take_dllp ||
                       (mode_q == ST_PKT) || (mode_q == ST_TLP_EM) || tlp_flow_q ||
                       (cur != RIVET_MAC_OS_NONE);
  assign sym_blk_start_d = rivet_pkg::rivet_pipe_block_rate(rate_i) && sym_valid_d &&
                           (word_q == 2'd0);

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
      word_q        <= '0;
      tlp_follow_q  <= 1'b0;
      emit_buf_q    <= '0;
      emit_cnt_q    <= '0;
      tlp_wr_slot_q <= '0;
      tlp_rd_slot_q <= '0;
      tlp_len_q     <= '0;
      frame_len_q   <= '0;
      tlp_pos_q     <= '0;
      tlp_flow_q    <= 1'b0;
      tlp_closed_q  <= 1'b0;
      sym_data_q    <= '0;
      sym_datak_q   <= '0;
      sym_os_d_q      <= '0;
      sym_valid_q     <= 1'b0;
      sym_blk_start_q <= 1'b0;
    end else begin
      mode_q          <= mode_d;
      pkt_q           <= pkt_d;
      pkt_ptr_q       <= pkt_ptr_d;
      emit_buf_q      <= emit_buf_d;
      emit_cnt_q      <= emit_cnt_d;
      tlp_wr_slot_q   <= tlp_wr_slot_d;
      tlp_rd_slot_q   <= tlp_rd_slot_d;
      tlp_len_q       <= tlp_len_d;
      frame_len_q     <= frame_len_d;
      tlp_pos_q       <= tlp_pos_d;
      tlp_flow_q      <= tlp_flow_d;
      tlp_closed_q    <= tlp_closed_d;
      sym_data_q      <= sym_data_d;
      sym_datak_q     <= sym_datak_d;
      sym_os_d_q      <= sym_os_d_d;
      sym_valid_q     <= sym_valid_d;
      sym_blk_start_q <= sym_blk_start_d;

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
        if (sent_q < (CNT_MAX - CNT_W'(os_step))) sent_q <= sent_q + CNT_W'(os_step);
      end else if ((mode_q == ST_OS) && !in_pkt_emit && set_done &&
                   (cur != RIVET_MAC_OS_NONE)) begin
        if (sent_q != CNT_MAX) sent_q <= sent_q + 1'b1;
      end

      // Block-word counter. Reset outside 128b/130b so word 0 aligns with the
      // first block after a rate change. Gen3 is four words. Gen4 is two.
      if (!rivet_pkg::rivet_pipe_block_rate(rate_i) || !sym_valid_d)
        word_q <= 2'd0;
      else if ((rate_i == RIVET_PIPE_RATE_GEN4) && (word_q == 2'd1))
        word_q <= 2'd0;
      else
        word_q <= word_q + 2'd1;

      // Keep the data block open for one idle cycle after a Gen3 TLP so
      // the next frame can start before the following block boundary.
      if (tlp_em_done && (gen3_pkt))
        tlp_follow_q <= 1'b1;
      else if ((mode_q == ST_OS) && (word_q == 2'd0) && !take_tlp_start)
        tlp_follow_q <= 1'b0;

      if (!pkt_en_i || skp_finishing) begin
        skp_sym_q <= '0;
        skp_due_q <= 1'b0;
      end else if (skp_sym_q < SKP_CNT_W'(SKP_INTERVAL_SYM)) begin
        if (in_pkt_emit || (cur != RIVET_MAC_OS_NONE)) begin
          if (skp_sym_q <= (SKP_CNT_W'(SKP_INTERVAL_SYM) - SKP_CNT_W'(os_step))) begin
            skp_sym_q <= skp_sym_q + SKP_CNT_W'(os_step);
            skp_due_q <= ((skp_sym_q + SKP_CNT_W'(os_step)) >= SKP_CNT_W'(SKP_INTERVAL_SYM));
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

  assign sym_data_o      = sym_data_q;
  assign sym_datak_o     = sym_datak_q;
  assign sym_os_d_o      = sym_os_d_q;
  assign sym_valid_o     = sym_valid_q;
  assign sym_blk_start_o = sym_blk_start_q;
  assign os_sent_cnt_o   = sent_q;

endmodule : rivet_mac_os_tx
