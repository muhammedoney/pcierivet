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
                                           input logic [7:0]         lane_num,
                                           input logic               is_block_rate);
    logic [8:0] sym;
    sym = {1'b0, 8'h00};
    if (is_block_rate) begin
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

  function automatic logic [4:0] os_length(input rivet_mac_os_type_e os_type,
                                           input logic               is_block_rate);
    if (is_block_rate &&
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

  function automatic logic [7:0] keep_nbytes(input logic [31:0] k);
    logic [2:0] s4 [8];
    logic [3:0] s8 [4];
    logic [4:0] s16 [2];
    for (int unsigned i = 0; i < 8; i++)
      s4[i] = {2'b0, k[4*i]} + {2'b0, k[4*i+1]} + {2'b0, k[4*i+2]} + {2'b0, k[4*i+3]};
    for (int unsigned i = 0; i < 4; i++)
      s8[i] = {1'b0, s4[2*i]} + {1'b0, s4[2*i+1]};
    s16[0] = {1'b0, s8[0]} + {1'b0, s8[1]};
    s16[1] = {1'b0, s8[2]} + {1'b0, s8[3]};
    return {2'b0, ({1'b0, s16[0]} + {1'b0, s16[1]})};
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
  // Gen4 x4 moves 32 symbols in one cycle. A 5-bit stride wraps that to 0.
  logic [5:0]             sym_step;
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

  // Four write ports and a same-cycle read. One array becomes registers
  // and misses 250 MHz, so the words sit in four distributed banks.
  localparam int unsigned TLP_RAM_DEPTH = 1024;
  // 516 slot words, padded so each bank is a power of two.
  if ((TLP_RAM_N > TLP_RAM_DEPTH) || (TLP_AW != $clog2(TLP_RAM_DEPTH))) begin : g_tlp_ram_depth
    initial $error("TLP RAM banks do not cover the slot");
  end
  logic                   tlp_ram_we, tlp_ram_we2, tlp_ram_we3, tlp_ram_we4;
  logic [TLP_AW-1:0]      tlp_ram_waddr, tlp_ram_waddr2, tlp_ram_waddr3, tlp_ram_waddr4;
  logic [63:0]            tlp_ram_wdata, tlp_ram_wdata2, tlp_ram_wdata3, tlp_ram_wdata4;
  logic [TLP_AW-1:0]      tlp_waddr_a [4];
  logic [63:0]            tlp_wdata_a [4];
  (* max_fanout = 16 *) logic [TLP_AW-3:0] tlp_ridx_q [4];
  logic [63:0]            tlp_rdata_a [4];
  logic [63:0]            tlp_ram_rdata;
  logic [63:0]            tlp_ram_rdata_b;
  logic [63:0]            tlp_ram_rdata_c;
  logic [63:0]            tlp_ram_rdata_d;

  // 2-entry decoded input skid stage: pre-computes keep popcount, masked data,
  // wide/quad flags, and Gen3 frame length so dll_tx_beat_i never feeds
  // emit_buf_q, tlp_em_done_q, or the distributed TLP RAM directly.
  logic [1:0]             in_v_q;
  logic [1:0]             in_dllp_ok_q;
  logic [1:0]             in_tlp_ok_q;
  logic [1:0]             in_sop_q;
  logic [1:0]             in_eop_q;
  logic [1:0]             in_quad_q;
  logic [1:0]             in_wide_q;
  logic [7:0]             in_nbytes_q [2];
  logic [15:0]            in_frm_len_q [2];
  logic [255:0]           in_data_q [2];
  logic                   in_push;
  logic                   in_pop;

  // 64-byte window. Gen3 reads two RAM words. Gen4 reads four so a
  // 32-byte stride can refill in the same cycle it is consumed.
  // 7-bit count covers 0..64 without wrapping at 64.
  logic [511:0]           emit_buf_q, emit_buf_d;
  logic [6:0]             emit_cnt_q, emit_cnt_d;
  logic [TLP_AW-1:0]      tlp_wr_slot_q, tlp_wr_slot_d;
  (* max_fanout = 32 *) logic [TLP_AW-1:0] tlp_rd_slot_q;
  logic [TLP_AW-1:0]      tlp_rd_slot_d;
  logic [15:0]            tlp_len_q, tlp_len_d;
  // Gen3 STP length, known from the TLP header in the first DLL beat.
  logic [15:0]            frame_len_q, frame_len_d;
  logic [15:0]            tlp_pos_q, tlp_pos_d;
  // Remaining framed symbols = (tlp_len + (gen3 ? 3 : 2)) - tlp_pos, sat at 0.
  logic [15:0]            tlp_rem_q, tlp_rem_d;
  logic [TLP_AW-1:0]      tlp_ram_occ_q;
  logic                   pos_z_q;
  logic [5:0]             slot_b_q;
  logic [6:0]             emit_cnt_sub_q;
  logic                   emit_ge_slot_q;
  logic                   last_beat_g3_q;
  logic                   tlp_em_done_q;
  logic                   tlp_em_done;
  // Flow: STP is already on the wire while later beats of this TLP are accepted.
  logic                   tlp_flow_q, tlp_flow_d;
  // Closed: the EOP beat has been accepted.
  // Gen2 END is at tlp_len+1. Gen3 has no END; the frame is STP + length + tlp_len.
  logic                   tlp_closed_q, tlp_closed_d;
  logic                   emit_fire;
  logic                   last_beat_g3;
  logic                   have_bytes_g3;
  logic [3:0]             take_b_g2;
  logic                   gen3_pkt;
  logic [5:0]             slot_b;
  // Local registered copies of slowly-changing LTSSM rate/lane/L0 controls break
  // the cross-chip fanout from u_ltssm into u_os_tx's 512-bit window & TLP RAM.
  (* equivalent_register_removal = "no" *) logic [2:0]       rate_loc_q;
  (* equivalent_register_removal = "no" *) logic [LANES-1:0] lane_en_loc_q;
  (* equivalent_register_removal = "no" *) logic             gen3_pkt_q;
  (* equivalent_register_removal = "no" *) logic [2:0]       n_en_q;
  (* equivalent_register_removal = "no" *) logic [4:0]       os_step_q;
  (* equivalent_register_removal = "no" *) logic [5:0]       sym_step_q;
  (* equivalent_register_removal = "no" *) logic             sym_step_gt16_q;
  (* equivalent_register_removal = "no" *) logic             pkt_en_loc_q;
  (* equivalent_register_removal = "no" *) logic             l0_idle_ok_q;
  logic [2:0]             n_en_next;
  logic [5:0]             sym_step_next;
  logic [7:0]             beat_n_c;

  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_d, sym_data_q;
  logic [2*LANES-1:0]               sym_datak_d, sym_datak_q;
  logic [2*LANES-1:0]               sym_os_d_d, sym_os_d_q;
  logic                             sym_valid_d, sym_valid_q;
  logic                             sym_blk_start_d, sym_blk_start_q;

  assign tlp_waddr_a = '{tlp_ram_waddr, tlp_ram_waddr2, tlp_ram_waddr3, tlp_ram_waddr4};
  assign tlp_wdata_a = '{tlp_ram_wdata, tlp_ram_wdata2, tlp_ram_wdata3, tlp_ram_wdata4};
  assign tlp_ram_rdata   = tlp_rdata_a[0];
  assign tlp_ram_rdata_b = tlp_rdata_a[1];
  assign tlp_ram_rdata_c = tlp_rdata_a[2];
  assign tlp_ram_rdata_d = tlp_rdata_a[3];

  rivet_ram_lane4_comb #(
    .DEPTH(TLP_RAM_DEPTH)
  ) u_tlp_ram (
    .clk_i    (pclk_i),
    .we_i     ({tlp_ram_we4, tlp_ram_we3, tlp_ram_we2, tlp_ram_we}),
    .waddr_i  (tlp_waddr_a),
    .wdata_i  (tlp_wdata_a),
    .ridx_i   (tlp_ridx_q),
    .rbank0_i (tlp_rd_slot_q[1:0]),
    .rdata_o  (tlp_rdata_a)
  );

  assign at_boundary  = (ptr_q == 5'd0) && (mode_q == ST_OS);
  assign transmitting = os_req_valid_i && (os_req_i != RIVET_MAC_OS_NONE);
  // L0: SKP preempts Idle/DLLP/TLP at OS boundaries (never mid-packet / mid-OS).
  assign skp_due  = pkt_en_loc_q && skp_due_q;
  // Gen3 SKP is one 16-byte block and starts only on a block boundary.
  assign want_skp = skp_due && at_boundary &&
                    (PKT_OK || ((gen3_pkt) && (word_q == 2'd0)));
  assign cur = at_boundary
      ? (want_skp ? RIVET_MAC_OS_SKP
                  : (transmitting ? os_req_i : RIVET_MAC_OS_NONE))
      : cur_q;
  // Gen1/Gen2 use the low 16 bits. Gen3 uses four symbols. Gen4 uses eight.
  wire [4:0] os_step;
  assign os_step      = os_step_q;
  assign len          = os_length(cur, gen3_pkt);
  assign set_done     = (ptr_q + os_step) >= len;
  assign ptr_next     = set_done ? 5'd0 : (ptr_q + os_step);

  // A DLLP is one 8-byte beat. A TLP may use the high half at Gen3.
  // Decoded from the registered head of the 2-entry input skid buffer.
  assign dllp_ok = in_v_q[0] && in_dllp_ok_q[0];
  assign tlp_ok  = in_v_q[0] && in_tlp_ok_q[0];

  // Insert DLLP only between Idle OS boundaries while packet-enabled (SKP first).
  // Gen3 uses the same beat stream inside a 128b/130b data block. The token
  // byte is not a K-symbol; Gen2 STP/END stay on the K path.
  wire pkt_rate_ok = PKT_OK ||
                     ((gen3_pkt) && (word_q == 2'd0));
  wire tlp_rate_ok = pkt_rate_ok ||
                     ((gen3_pkt) && tlp_follow_q);
  assign want_pkt = pkt_rate_ok && l0_idle_ok_q && at_boundary && !want_skp && dllp_ok;
  assign want_tlp = tlp_rate_ok && l0_idle_ok_q && at_boundary && !want_skp &&
                    tlp_ok && in_sop_q[0] && !dllp_ok;
  assign take_dllp      = want_pkt;
  assign take_tlp_start = want_tlp;
  assign take_tlp_col   = (mode_q == ST_TLP_COL) && tlp_ok;
  assign in_pop         = take_dllp || take_tlp_start || take_tlp_col;
  assign dll_tx_ready_o = !in_v_q[1];
  assign in_push        = dll_tx_valid_i && !in_v_q[1];

  always_comb begin
    int unsigned step_i;
    n_en_next = '0;
    for (int unsigned li = 0; li < LANES; li++)
      if (lane_en_i[li]) n_en_next = n_en_next + 3'd1;
    if (n_en_next == 3'd0) n_en_next = 3'(LANES);
    // Gen3 on a 64-bit pipe is four symbols, so a x4 step stays 16.
    // Gen4 x4 is 32 symbols. The stride is six bits so that step stays 32.
    step_i        = int'(n_en_next) * rivet_pkg::rivet_pipe_nsym(rate_i);
    sym_step_next = (step_i > 63) ? 6'd63 : 6'(step_i);
  end

  assign n_en          = n_en_q;
  assign sym_step      = sym_step_q;
  assign pkt_done      = (pkt_ptr_q + PTR_W'(sym_step)) >= PTR_W'(RIVET_DLLP_FRAMED_LEN);
  // Gen3 and Gen4 share STP + 2 length bytes + DLL bytes. Gen2 is STP + END.
  assign gen3_pkt      = gen3_pkt_q;
  assign slot_b        = slot_b_q;
  assign last_beat_g3  = last_beat_g3_q;
  assign have_bytes_g3 = last_beat_g3_q ? (tlp_ram_occ_q == '0) : emit_ge_slot_q;
  assign take_b_g2     = pos_z_q ? (sym_step[3:0] - 4'd1) : sym_step[3:0];
  assign tlp_em_done   = tlp_em_done_q;
  assign emit_fire     = (tlp_flow_q || (mode_q == ST_TLP_EM)) && !tlp_em_done_q &&
                         (gen3_pkt ? have_bytes_g3
                                   : ({3'd0, take_b_g2} <= emit_cnt_q));
  assign in_pkt_emit   = take_dllp || (mode_q == ST_PKT) || (mode_q == ST_TLP_EM) ||
                         tlp_flow_q;
  assign skp_finishing =
      (mode_q == ST_OS) && !in_pkt_emit && set_done && (cur == RIVET_MAC_OS_SKP);
  assign beat_n_c      = in_nbytes_q[0];

  always_comb begin
    logic [255:0] masked_beat;
    logic [63:0]  masked_lo;
    logic [7:0]   beat_n;
    logic [127:0] shifted;
    logic [511:0] base_buf;
    logic [6:0]   base_cnt;
    logic         add_en;
    logic [5:0]   add_n;
    logic [255:0] add_data;
    logic         wide_beat;
    logic         quad_beat;

    tlp_ram_we     = 1'b0;
    tlp_ram_we2    = 1'b0;
    tlp_ram_we3    = 1'b0;
    tlp_ram_we4    = 1'b0;
    tlp_ram_waddr  = tlp_wr_slot_q;
    tlp_ram_waddr2 = tlp_wr_slot_q;
    tlp_ram_waddr3 = tlp_wr_slot_q;
    tlp_ram_waddr4 = tlp_wr_slot_q;
    tlp_ram_wdata2 = '0;
    tlp_ram_wdata3 = '0;
    tlp_ram_wdata4 = '0;
    masked_beat    = in_data_q[0];
    masked_lo      = masked_beat[63:0];
    tlp_ram_wdata  = masked_lo;

    emit_buf_d    = emit_buf_q;
    emit_cnt_d    = emit_cnt_q;
    tlp_wr_slot_d = tlp_wr_slot_q;
    tlp_rd_slot_d = tlp_rd_slot_q;
    tlp_len_d     = tlp_len_q;
    frame_len_d   = frame_len_q;
    beat_n        = in_nbytes_q[0];
    quad_beat     = in_quad_q[0];
    wide_beat     = in_wide_q[0];
    shifted       = emit_buf_q[127:0];
    base_buf      = emit_buf_q;
    base_cnt      = emit_cnt_q;
    add_en        = 1'b0;
    add_n         = 6'd0;
    add_data      = '0;

    if (take_tlp_start) begin
      tlp_ram_we    = 1'b1;
      tlp_ram_waddr = '0;
      tlp_len_d     = {8'd0, beat_n};
      if (quad_beat) begin
        tlp_ram_we2    = 1'b1;
        tlp_ram_we3    = 1'b1;
        tlp_ram_we4    = 1'b1;
        tlp_ram_waddr2 = TLP_AW'(1);
        tlp_ram_waddr3 = TLP_AW'(2);
        tlp_ram_waddr4 = TLP_AW'(3);
        tlp_ram_wdata2 = masked_beat[127:64];
        tlp_ram_wdata3 = masked_beat[191:128];
        tlp_ram_wdata4 = masked_beat[255:192];
        emit_buf_d     = {256'd0, masked_beat};
        emit_cnt_d     = 7'(beat_n);
        tlp_wr_slot_d  = TLP_AW'(4);
        tlp_rd_slot_d  = TLP_AW'(4);
      end else if (wide_beat) begin
        tlp_ram_we2    = 1'b1;
        tlp_ram_waddr2 = TLP_AW'(1);
        tlp_ram_wdata2 = masked_beat[127:64];
        emit_buf_d     = {384'd0, masked_beat[127:0]};
        emit_cnt_d     = 7'(beat_n);
        tlp_wr_slot_d  = TLP_AW'(2);
        tlp_rd_slot_d  = TLP_AW'(2);
      end else begin
        emit_buf_d    = {448'd0, masked_lo};
        emit_cnt_d    = 7'd8;
        tlp_wr_slot_d = TLP_AW'(1);
        tlp_rd_slot_d = TLP_AW'(1);
      end
      // STP length is pre-decoded on input skid push.
      frame_len_d = gen3_pkt ? in_frm_len_q[0] : 16'd0;
    end else if (take_tlp_col) begin
      tlp_len_d = tlp_len_q + 16'(beat_n);
      if (quad_beat) begin
        tlp_ram_we     = 1'b1;
        tlp_ram_we2    = 1'b1;
        tlp_ram_we3    = 1'b1;
        tlp_ram_we4    = 1'b1;
        tlp_ram_waddr  = tlp_wr_slot_q;
        tlp_ram_waddr2 = tlp_wr_slot_q + TLP_AW'(1);
        tlp_ram_waddr3 = tlp_wr_slot_q + TLP_AW'(2);
        tlp_ram_waddr4 = tlp_wr_slot_q + TLP_AW'(3);
        tlp_ram_wdata2 = masked_beat[127:64];
        tlp_ram_wdata3 = masked_beat[191:128];
        tlp_ram_wdata4 = masked_beat[255:192];
        tlp_wr_slot_d  = tlp_wr_slot_q + TLP_AW'(4);
      end else if (wide_beat) begin
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
        if (!gen3_pkt) begin
          if (tlp_wr_slot_q == TLP_AW'(1))
            emit_buf_d[127:64] = masked_lo;
          if (in_eop_q[0] && !tlp_flow_q) begin
            emit_cnt_d    = 7'd16;
            tlp_rd_slot_d = TLP_AW'(2);
          end else if ((tlp_wr_slot_q == TLP_AW'(1)) && !in_eop_q[0]) begin
            // 16-byte head is full and more beats follow. Emit starts next cycle.
            emit_cnt_d    = 7'd16;
            tlp_rd_slot_d = TLP_AW'(2);
          end
        end
      end
    end

    // Step 1: Consume from emit_buf_q using constant-shift cases (no dynamic
    // 512-bit barrel shifter). Step 2: Single mutually exclusive refill or
    // bypass merge into the 64-byte window.
    if (!take_tlp_start && gen3_pkt) begin
      if (emit_fire) begin
        if (last_beat_g3) begin
          base_buf = 512'h0;
          base_cnt = 7'd0;
        end else begin
          unique case (slot_b)
            6'd1:    base_buf = {  8'd0, emit_buf_q[511:  8]};
            6'd4:    base_buf = { 32'd0, emit_buf_q[511: 32]};
            6'd5:    base_buf = { 40'd0, emit_buf_q[511: 40]};
            6'd8:    base_buf = { 64'd0, emit_buf_q[511: 64]};
            6'd9:    base_buf = { 72'd0, emit_buf_q[511: 72]};
            6'd12:   base_buf = { 96'd0, emit_buf_q[511: 96]};
            6'd13:   base_buf = {104'd0, emit_buf_q[511:104]};
            6'd16:   base_buf = {128'd0, emit_buf_q[511:128]};
            6'd21:   base_buf = {168'd0, emit_buf_q[511:168]};
            6'd24:   base_buf = {192'd0, emit_buf_q[511:192]};
            6'd29:   base_buf = {232'd0, emit_buf_q[511:232]};
            default: base_buf = {256'd0, emit_buf_q[511:256]};
          endcase
          base_cnt = emit_cnt_sub_q;
        end
      end

      emit_buf_d = base_buf;
      emit_cnt_d = base_cnt;

      if (!(emit_fire && last_beat_g3) &&
          ((mode_q == ST_TLP_COL) || (mode_q == ST_TLP_EM))) begin
        if ((base_cnt <= 7'd32) && (|tlp_ram_occ_q[TLP_AW-1:2])) begin
          add_en        = 1'b1;
          add_n         = 6'd32;
          add_data      = {tlp_ram_rdata_d, tlp_ram_rdata_c, tlp_ram_rdata_b, tlp_ram_rdata};
          tlp_rd_slot_d = tlp_rd_slot_q + TLP_AW'(4);
        end else if ((base_cnt <= 7'd48) && (|tlp_ram_occ_q[TLP_AW-1:1])) begin
          add_en        = 1'b1;
          add_n         = 6'd16;
          add_data      = {128'd0, tlp_ram_rdata_b, tlp_ram_rdata};
          tlp_rd_slot_d = tlp_rd_slot_q + TLP_AW'(2);
        end else if ((base_cnt <= 7'd56) && (|tlp_ram_occ_q)) begin
          add_en        = 1'b1;
          add_n         = 6'd8;
          add_data      = {192'd0, tlp_ram_rdata};
          tlp_rd_slot_d = tlp_rd_slot_q + TLP_AW'(1);
        end else if (take_tlp_col && (tlp_ram_occ_q == '0) &&
                     (beat_n != 8'd0) && ((base_cnt + 7'(beat_n)) <= 7'd64)) begin
          add_en        = 1'b1;
          add_n         = beat_n[5:0];
          add_data      = masked_beat;
          tlp_rd_slot_d = tlp_wr_slot_d;
        end
      end

      if (add_en) begin
        automatic logic [7:0] ab [32];
        for (int unsigned i = 0; i < 32; i++)
          ab[5'(i)] = add_data[8*5'(i) +: 8];
        for (int unsigned k = 0; k < 64; k++) begin
          automatic logic [6:0] diff = 7'(k) - base_cnt;
          if ((7'(k) >= base_cnt) && (diff < {1'b0, add_n}))
            emit_buf_d[8*6'(k) +: 8] = ab[diff[4:0]];
        end
        emit_cnt_d = base_cnt + {1'b0, add_n};
      end
    end else if (!take_tlp_start && emit_fire) begin
      unique case (take_b_g2)
        4'd1:    shifted = { 8'd0, emit_buf_q[127: 8]};
        4'd2:    shifted = {16'd0, emit_buf_q[127:16]};
        4'd3:    shifted = {24'd0, emit_buf_q[127:24]};
        4'd4:    shifted = {32'd0, emit_buf_q[127:32]};
        4'd7:    shifted = {56'd0, emit_buf_q[127:56]};
        default: shifted = {64'd0, emit_buf_q[127:64]};
      endcase
      base_cnt = emit_cnt_q - {3'd0, take_b_g2};
      if ((base_cnt <= 7'd8) && (|tlp_ram_occ_q)) begin
        unique case (base_cnt[3:0])
          4'd0:    emit_buf_d = {384'd0, 64'd0, tlp_ram_rdata};
          4'd1:    emit_buf_d = {384'd0, 56'd0, tlp_ram_rdata, shifted[ 7:0]};
          4'd2:    emit_buf_d = {384'd0, 48'd0, tlp_ram_rdata, shifted[15:0]};
          4'd3:    emit_buf_d = {384'd0, 40'd0, tlp_ram_rdata, shifted[23:0]};
          4'd4:    emit_buf_d = {384'd0, 32'd0, tlp_ram_rdata, shifted[31:0]};
          4'd5:    emit_buf_d = {384'd0, 24'd0, tlp_ram_rdata, shifted[39:0]};
          4'd6:    emit_buf_d = {384'd0, 16'd0, tlp_ram_rdata, shifted[47:0]};
          4'd7:    emit_buf_d = {384'd0,  8'd0, tlp_ram_rdata, shifted[55:0]};
          default: emit_buf_d = {384'd0,        tlp_ram_rdata, shifted[63:0]};
        endcase
        emit_cnt_d    = base_cnt + 7'd8;
        tlp_rd_slot_d = tlp_rd_slot_q + TLP_AW'(1);
      end else begin
        emit_buf_d = {384'd0, shifted};
        emit_cnt_d = base_cnt;
      end
    end
  end

  always_comb begin
    logic [15:0] rem_pre;
    mode_d       = mode_q;
    pkt_d        = pkt_q;
    pkt_ptr_d    = pkt_ptr_q;
    tlp_pos_d    = tlp_pos_q;
    tlp_rem_d    = tlp_rem_q;
    tlp_flow_d   = tlp_flow_q;
    tlp_closed_d = tlp_closed_q;
    rem_pre      = tlp_rem_q;
    unique case (mode_q)
      ST_OS: begin
        tlp_flow_d   = 1'b0;
        tlp_closed_d = 1'b0;
        tlp_rem_d    = 16'd0;
        if (take_dllp) begin
          pkt_d = in_data_q[0][63:0];
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
          tlp_rem_d    = {8'd0, beat_n_c} + (gen3_pkt ? 16'd3 : 16'd2);
          pkt_ptr_d    = '0;
          tlp_closed_d = in_eop_q[0];
          mode_d       = in_eop_q[0] ? ST_TLP_EM : ST_TLP_COL;
          if ((gen3_pkt) && !in_eop_q[0])
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
        if (take_tlp_col && (tlp_wr_slot_q == TLP_AW'(1)) && !in_eop_q[0] &&
            !gen3_pkt)
          tlp_flow_d = 1'b1;
        if (take_tlp_col && in_eop_q[0]) begin
          mode_d       = ST_TLP_EM;
          tlp_closed_d = 1'b1;
          if (!tlp_flow_q) begin
            tlp_pos_d = '0;
            pkt_ptr_d = '0;
          end
        end
        rem_pre = tlp_rem_q + (take_tlp_col ? {8'd0, beat_n_c} : 16'd0);
        if (emit_fire) begin
          tlp_pos_d = tlp_pos_q + 16'(sym_step);
          tlp_rem_d = (rem_pre > {10'd0, sym_step}) ? (rem_pre - {10'd0, sym_step}) : 16'd0;
        end else begin
          tlp_rem_d = rem_pre;
        end
      end
      ST_TLP_EM: begin
        if (tlp_em_done) begin
          mode_d       = ST_OS;
          tlp_pos_d    = '0;
          tlp_rem_d    = 16'd0;
          pkt_ptr_d    = '0;
          tlp_flow_d   = 1'b0;
          tlp_closed_d = 1'b0;
        end else if (emit_fire) begin
          tlp_pos_d = tlp_pos_q + 16'(sym_step);
          tlp_rem_d = (tlp_rem_q > {10'd0, sym_step}) ? (tlp_rem_q - {10'd0, sym_step}) : 16'd0;
        end
      end
      default: mode_d = ST_OS;
    endcase
  end

  always_comb begin
    logic [8:0]  tlp_sym [0:31];
    logic [15:0] rem_sym_g3;
    logic [15:0] rem_sym_g2;
    logic        pos_z;
    logic [7:0]  len_lo, len_hi;
    logic [63:0] dllp_src;
    logic [6:0]  pkt_base;

    sym_data_d  = '0;
    sym_datak_d = '0;
    sym_os_d_d  = '0;
    sym_tmp     = '0;
    stream_idx  = '0;

    // Pre-build dense TLP symbol vector indexed by constant k = 0..31 so each
    // lane/symbol only selects across enabled-lane mapping, not a 32:1 mux.
    pos_z      = pos_z_q;
    len_lo     = (frame_len_q != 16'd0) ? frame_len_q[7:0]  : tlp_len_q[7:0];
    len_hi     = (frame_len_q != 16'd0) ? frame_len_q[15:8] : tlp_len_q[15:8];
    rem_sym_g3 = tlp_rem_q;
    rem_sym_g2 = (tlp_rem_q != 16'd0) ? (tlp_rem_q - 16'd1) : 16'd0;
    for (int unsigned k = 0; k < 32; k++) begin
      if (gen3_pkt) begin
        automatic logic in_rng = (rem_sym_g3[15:5] != 11'd0) || (rem_sym_g3[4:0] > 5'(k));
        if (!emit_fire || !in_rng) begin
          tlp_sym[k] = {1'b0, 8'h00};
        end else if (pos_z && (k == 0)) begin
          tlp_sym[k] = {1'b0, RIVET_SYM_STP};
        end else if (pos_z && (k == 1)) begin
          tlp_sym[k] = {1'b0, len_lo};
        end else if (pos_z && (k == 2)) begin
          tlp_sym[k] = {1'b0, len_hi};
        end else if (pos_z && (k >= 3)) begin
          tlp_sym[k] = {1'b0, emit_buf_q[8*((k >= 3) ? (k - 3) : 0) +: 8]};
        end else begin
          tlp_sym[k] = {1'b0, emit_buf_q[8*k +: 8]};
        end
      end else if (k < 8) begin
        if (pos_z && (k == 0)) begin
          tlp_sym[k] = {1'b1, RIVET_SYM_STP};
        end else if (tlp_closed_q && (tlp_rem_q != 16'd0) &&
                     (rem_sym_g2 == 16'(k))) begin
          tlp_sym[k] = {1'b1, RIVET_SYM_END};
        end else if (!tlp_closed_q || (tlp_rem_q >= (16'(k) + 16'd2))) begin
          if (pos_z && (k >= 1))
            tlp_sym[k] = {1'b0, emit_buf_q[8*((k >= 1) ? (k - 1) : 0) +: 8]};
          else
            tlp_sym[k] = {1'b0, emit_buf_q[8*k +: 8]};
        end else begin
          tlp_sym[k] = {1'b0, 8'h00};
        end
      end else begin
        tlp_sym[k] = {1'b0, 8'h00};
      end
    end

    dllp_src = take_dllp ? in_data_q[0][63:0] : pkt_q;
    pkt_base = take_dllp ? 7'd0 : pkt_ptr_q[6:0];

    if (take_dllp || (mode_q == ST_PKT)) begin
      // Stripe each symbol time across enabled lanes only (SDP on logical 0).
      for (int unsigned s = 0; s < SYMS; s++) begin
        automatic int unsigned ord = 0;
        for (int unsigned l = 0; l < LANES; l++) begin
          if (lane_en_loc_q[l]) begin
            stream_idx = PTR_W'(pkt_base + 7'(s * int'(n_en) + ord));
            sym_tmp    = pkt_symbol(stream_idx[6:0], dllp_src);
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
          if (lane_en_loc_q[l]) begin
            automatic int unsigned sym_i = s * int'(n_en) + ord;
            sym_tmp = tlp_sym[sym_i[4:0]];
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
          sym_tmp = os_symbol(cur, 4'(ptr_q + 5'(s)), tx_lane_num_i[8*l +: 8], gen3_pkt);
          if (lane_en_loc_q[l]) begin
            sym_data_d[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
            if (s < 2) begin
              sym_datak_d[2*l + s] = sym_tmp[8];
              if ((!sym_tmp[8] &&
                   ((cur == RIVET_MAC_OS_TS1) || (cur == RIVET_MAC_OS_TS2))) ||
                  (gen3_pkt &&
                   (cur != RIVET_MAC_OS_NONE) && (cur != RIVET_MAC_OS_IDLE)))
                sym_os_d_d[2*l + s] = 1'b1;
            end
          end
        end
      end
    end
  end

  // Gen4 x4 steps 32 bytes. Emitting a data word while the buffer is
  // short inserts 00 inside the TLP and the peer's length count ends early.
  // Drop valid instead: the scrambler and the peer both freeze, and the
  // next word is a block start that does not reseed an armed LFSR.
  wire tlp_underrun;
  assign tlp_underrun = ((mode_q == ST_TLP_EM) || tlp_flow_q) &&
                        sym_step_gt16_q && !emit_fire;
  assign sym_valid_d = !tlp_underrun &&
                       (take_dllp ||
                       (mode_q == ST_PKT) || (mode_q == ST_TLP_EM) || tlp_flow_q ||
                       (cur != RIVET_MAC_OS_NONE));
  assign sym_blk_start_d = gen3_pkt && sym_valid_d &&
                           (word_q == 2'd0);

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rate_loc_q      <= RIVET_PIPE_RATE_GEN1;
      lane_en_loc_q   <= '0;
      gen3_pkt_q      <= 1'b0;
      pkt_en_loc_q    <= 1'b0;
      l0_idle_ok_q    <= 1'b0;
      n_en_q          <= 3'(LANES);
      os_step_q       <= 5'd2;
      sym_step_q      <= 6'(2 * LANES);
      sym_step_gt16_q <= 1'b0;
      cur_q           <= RIVET_MAC_OS_NONE;
      ptr_q           <= '0;
      sent_q          <= '0;
      mode_q          <= ST_OS;
      pkt_q           <= '0;
      pkt_ptr_q       <= '0;
      skp_sym_q       <= '0;
      skp_due_q       <= 1'b0;
      word_q          <= '0;
      tlp_follow_q    <= 1'b0;
      emit_buf_q      <= '0;
      emit_cnt_q      <= '0;
      tlp_wr_slot_q   <= '0;
      tlp_rd_slot_q   <= '0;
      for (int unsigned b = 0; b < 4; b++)
        tlp_ridx_q[b] <= '0;
      in_v_q          <= 2'b00;
      in_dllp_ok_q    <= 2'b00;
      in_tlp_ok_q     <= 2'b00;
      in_sop_q        <= 2'b00;
      in_eop_q        <= 2'b00;
      in_quad_q       <= 2'b00;
      in_wide_q       <= 2'b00;
      in_nbytes_q[0]  <= '0;
      in_nbytes_q[1]  <= '0;
      in_frm_len_q[0] <= '0;
      in_frm_len_q[1] <= '0;
      in_data_q[0]    <= '0;
      in_data_q[1]    <= '0;
      tlp_ram_occ_q   <= '0;
      tlp_len_q       <= '0;
      frame_len_q     <= '0;
      tlp_pos_q       <= '0;
      tlp_rem_q       <= '0;
      pos_z_q         <= 1'b1;
      slot_b_q        <= 6'd0;
      emit_cnt_sub_q  <= 7'd0;
      emit_ge_slot_q  <= 1'b1;
      last_beat_g3_q  <= 1'b0;
      tlp_em_done_q   <= 1'b0;
      tlp_flow_q      <= 1'b0;
      tlp_closed_q    <= 1'b0;
      sym_data_q      <= '0;
      sym_datak_q     <= '0;
      sym_os_d_q      <= '0;
      sym_valid_q     <= 1'b0;
      sym_blk_start_q <= 1'b0;
    end else begin
      automatic logic [5:0] slot_b_next =
          (tlp_pos_d == 16'd0)
              ? ((sym_step_next > 6'd3) ? (sym_step_next - 6'd3) : 6'd0)
              : sym_step_next;
      rate_loc_q      <= rate_i;
      lane_en_loc_q   <= lane_en_i;
      gen3_pkt_q      <= rivet_pkg::rivet_pipe_block_rate(rate_i);
      pkt_en_loc_q    <= pkt_en_i;
      l0_idle_ok_q    <= pkt_en_i && os_req_valid_i && (os_req_i == RIVET_MAC_OS_IDLE);
      n_en_q          <= n_en_next;
      os_step_q       <= 5'(rivet_pkg::rivet_pipe_nsym(rate_i));
      sym_step_q      <= sym_step_next;
      sym_step_gt16_q <= (sym_step_next > 6'd16);
      mode_q          <= mode_d;
      pkt_q           <= pkt_d;
      pkt_ptr_q       <= pkt_ptr_d;
      emit_buf_q      <= emit_buf_d;
      emit_cnt_q      <= emit_cnt_d;
      tlp_wr_slot_q   <= tlp_wr_slot_d;
      tlp_rd_slot_q   <= tlp_rd_slot_d;
      for (int unsigned b = 0; b < 4; b++) begin
        tlp_ridx_q[b] <= tlp_rd_slot_d[TLP_AW-1:2] +
                         ((2'(b) < tlp_rd_slot_d[1:0]) ? (TLP_AW-2)'(1) : (TLP_AW-2)'(0));
      end
      tlp_ram_occ_q   <= tlp_wr_slot_d - tlp_rd_slot_d;

      // 2-entry decoded input skid update.
      begin
        automatic logic [7:0]   p_nb = keep_nbytes(dll_tx_beat_i.keep);
        automatic logic         p_dllp_ok = (dll_tx_beat_i.pkt_type == RIVET_MAC_PKT_DLLP) &&
                                            dll_tx_beat_i.sop && dll_tx_beat_i.eop &&
                                            (dll_tx_beat_i.keep[7:0] == 8'hFF) &&
                                            (dll_tx_beat_i.keep[31:8] == 24'h0);
        automatic logic         p_tlp_ok  = (dll_tx_beat_i.pkt_type == RIVET_MAC_PKT_TLP) &&
                                            (dll_tx_beat_i.keep != 32'h0);
        automatic logic         p_quad = (p_nb > 8'd16);
        automatic logic         p_wide = (p_nb > 8'd8) && !p_quad;
        automatic logic [255:0] p_data = '0;
        automatic logic [7:0]   p_b0;
        automatic logic [9:0]   p_ldw;
        automatic logic [15:0]  p_hbytes, p_pbytes, p_frm_len;
        for (int unsigned i = 0; i < 32; i++) begin
          if (dll_tx_beat_i.keep[i])
            p_data[8*i +: 8] = dll_tx_beat_i.data[8*i +: 8];
        end
        p_b0      = p_data[23:16];
        p_ldw     = {p_data[33:32], p_data[47:40]};
        p_hbytes  = p_b0[5] ? 16'd16 : 16'd12;
        p_pbytes  = p_b0[6] ? (((p_ldw == 10'd0) ? 16'd1024 : {6'd0, p_ldw}) * 16'd4) : 16'd0;
        p_frm_len = (p_nb >= 8'd6) ? (16'd6 + p_hbytes + p_pbytes) : 16'd0;

        case ({in_push, in_pop})
          2'b01: begin
            in_v_q[0]       <= in_v_q[1];
            in_dllp_ok_q[0] <= in_dllp_ok_q[1];
            in_tlp_ok_q[0]  <= in_tlp_ok_q[1];
            in_sop_q[0]     <= in_sop_q[1];
            in_eop_q[0]     <= in_eop_q[1];
            in_quad_q[0]    <= in_quad_q[1];
            in_wide_q[0]    <= in_wide_q[1];
            in_nbytes_q[0]  <= in_nbytes_q[1];
            in_frm_len_q[0] <= in_frm_len_q[1];
            in_data_q[0]    <= in_data_q[1];
            in_v_q[1]       <= 1'b0;
          end
          2'b10: begin
            if (!in_v_q[0]) begin
              in_v_q[0]       <= 1'b1;
              in_dllp_ok_q[0] <= p_dllp_ok;
              in_tlp_ok_q[0]  <= p_tlp_ok;
              in_sop_q[0]     <= dll_tx_beat_i.sop;
              in_eop_q[0]     <= dll_tx_beat_i.eop;
              in_quad_q[0]    <= p_quad;
              in_wide_q[0]    <= p_wide;
              in_nbytes_q[0]  <= p_nb;
              in_frm_len_q[0] <= p_frm_len;
              in_data_q[0]    <= p_data;
            end else begin
              in_v_q[1]       <= 1'b1;
              in_dllp_ok_q[1] <= p_dllp_ok;
              in_tlp_ok_q[1]  <= p_tlp_ok;
              in_sop_q[1]     <= dll_tx_beat_i.sop;
              in_eop_q[1]     <= dll_tx_beat_i.eop;
              in_quad_q[1]    <= p_quad;
              in_wide_q[1]    <= p_wide;
              in_nbytes_q[1]  <= p_nb;
              in_frm_len_q[1] <= p_frm_len;
              in_data_q[1]    <= p_data;
            end
          end
          2'b11: begin
            if (in_v_q[1]) begin
              in_v_q[0]       <= 1'b1;
              in_dllp_ok_q[0] <= in_dllp_ok_q[1];
              in_tlp_ok_q[0]  <= in_tlp_ok_q[1];
              in_sop_q[0]     <= in_sop_q[1];
              in_eop_q[0]     <= in_eop_q[1];
              in_quad_q[0]    <= in_quad_q[1];
              in_wide_q[0]    <= in_wide_q[1];
              in_nbytes_q[0]  <= in_nbytes_q[1];
              in_frm_len_q[0] <= in_frm_len_q[1];
              in_data_q[0]    <= in_data_q[1];
              in_v_q[1]       <= 1'b1;
              in_dllp_ok_q[1] <= p_dllp_ok;
              in_tlp_ok_q[1]  <= p_tlp_ok;
              in_sop_q[1]     <= dll_tx_beat_i.sop;
              in_eop_q[1]     <= dll_tx_beat_i.eop;
              in_quad_q[1]    <= p_quad;
              in_wide_q[1]    <= p_wide;
              in_nbytes_q[1]  <= p_nb;
              in_frm_len_q[1] <= p_frm_len;
              in_data_q[1]    <= p_data;
            end else begin
              in_v_q[0]       <= 1'b1;
              in_dllp_ok_q[0] <= p_dllp_ok;
              in_tlp_ok_q[0]  <= p_tlp_ok;
              in_sop_q[0]     <= dll_tx_beat_i.sop;
              in_eop_q[0]     <= dll_tx_beat_i.eop;
              in_quad_q[0]    <= p_quad;
              in_wide_q[0]    <= p_wide;
              in_nbytes_q[0]  <= p_nb;
              in_frm_len_q[0] <= p_frm_len;
              in_data_q[0]    <= p_data;
              in_v_q[1]       <= 1'b0;
            end
          end
          default: ;
        endcase
      end
      tlp_len_q       <= tlp_len_d;
      frame_len_q     <= frame_len_d;
      tlp_pos_q       <= tlp_pos_d;
      tlp_rem_q       <= tlp_rem_d;
      pos_z_q         <= (tlp_pos_d == 16'd0);
      slot_b_q        <= slot_b_next;
      emit_cnt_sub_q  <= (emit_cnt_d >= {1'b0, slot_b_next})
                             ? (emit_cnt_d - {1'b0, slot_b_next}) : 7'd0;
      emit_ge_slot_q  <= (emit_cnt_d >= {1'b0, slot_b_next});
      last_beat_g3_q  <= tlp_closed_d && (tlp_rem_d <= {10'd0, sym_step_next});
      tlp_em_done_q   <= tlp_closed_d &&
                         ((sym_step_next > 6'd16)
                             ? (tlp_rem_d == 16'd0)
                             : (tlp_rem_d <= {10'd0, sym_step_next}));
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
      if (!gen3_pkt || !sym_valid_d)
        word_q <= 2'd0;
      else if ((rate_loc_q == RIVET_PIPE_RATE_GEN4) && (word_q == 2'd1))
        word_q <= 2'd0;
      else
        word_q <= word_q + 2'd1;

      // Keep the data block open for one idle cycle after a Gen3 TLP so
      // the next frame can start before the following block boundary.
      if (tlp_em_done && (gen3_pkt))
        tlp_follow_q <= 1'b1;
      else if ((mode_q == ST_OS) && (word_q == 2'd0) && !take_tlp_start)
        tlp_follow_q <= 1'b0;

      if (!pkt_en_loc_q || skp_finishing) begin
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

// Same-cycle read of four consecutive 64-bit words. DEPTH is a power of
// two and a multiple of four, and it must cover the caller's address range.
// Address[1:0] selects the bank, so four consecutive words never share one.
module rivet_ram_lane4_comb #(
  parameter int unsigned DEPTH = 1024
) (
  input  logic                     clk_i,
  input  logic [3:0]               we_i,
  input  logic [$clog2(DEPTH)-1:0] waddr_i [4],
  input  logic [63:0]              wdata_i [4],
  input  logic [$clog2(DEPTH)-3:0] ridx_i [4],
  input  logic [1:0]               rbank0_i,
  output logic [63:0]              rdata_o [4]
);
  localparam int unsigned AW     = $clog2(DEPTH);
  localparam int unsigned BANK_N = DEPTH / 4;

  logic [63:0] dout_b [4];

  generate
    for (genvar b = 0; b < 4; b++) begin : g_bank
      (* ram_style = "distributed" *) logic [63:0] mem [0:BANK_N-1];
      logic              we;
      logic [AW-3:0]     widx;
      logic [63:0]       wdat;

`ifndef SYNTHESIS
      initial begin
        for (int unsigned ii = 0; ii < BANK_N; ii++)
          mem[ii] = '0;
      end
`endif

      always_comb begin
        we   = 1'b0;
        widx = '0;
        wdat = '0;
        unique case (waddr_i[0][1:0])
          b[1:0]: begin
            we   = we_i[0];
            widx = waddr_i[0][AW-1:2];
            wdat = wdata_i[0];
          end
          (b[1:0] - 2'd1): begin
            we   = we_i[1];
            widx = waddr_i[1][AW-1:2];
            wdat = wdata_i[1];
          end
          (b[1:0] - 2'd2): begin
            we   = we_i[2];
            widx = waddr_i[2][AW-1:2];
            wdat = wdata_i[2];
          end
          default: begin
            we   = we_i[3];
            widx = waddr_i[3][AW-1:2];
            wdat = wdata_i[3];
          end
        endcase
      end

      always_ff @(posedge clk_i) begin
        if (we)
          mem[widx] <= wdat;
      end

      assign dout_b[b] = mem[ridx_i[b]];
    end
  endgenerate

  always_comb begin
    unique case (rbank0_i)
      2'd0: begin
        rdata_o[0] = dout_b[0];
        rdata_o[1] = dout_b[1];
        rdata_o[2] = dout_b[2];
        rdata_o[3] = dout_b[3];
      end
      2'd1: begin
        rdata_o[0] = dout_b[1];
        rdata_o[1] = dout_b[2];
        rdata_o[2] = dout_b[3];
        rdata_o[3] = dout_b[0];
      end
      2'd2: begin
        rdata_o[0] = dout_b[2];
        rdata_o[1] = dout_b[3];
        rdata_o[2] = dout_b[0];
        rdata_o[3] = dout_b[1];
      end
      default: begin
        rdata_o[0] = dout_b[3];
        rdata_o[1] = dout_b[0];
        rdata_o[2] = dout_b[1];
        rdata_o[3] = dout_b[2];
      end
    endcase
  end
endmodule : rivet_ram_lane4_comb
