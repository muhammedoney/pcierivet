// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC ordered-set / TS receiver (Gen2, 8b/10b symbol plane).
//
// Every LTSSM exit out of Polling and Configuration is phrased as "N consecutive
// ordered sets of a given shape", so this block does the counting and hands the
// LTSSM booleans plus the captured TS fields. Detection is a sliding symbol
// window: with two symbols per pclk a TS can complete on either symbol phase,
// so both alignments are compared each cycle.
//
// Packet framing uses a registered symbol pre-decoder feeding a 16-byte
// byte-packing gearbox and a 32x64b distributed LUTRAM so 250 MHz timing
// closes without a 160-byte byte-address mux.

module rivet_mac_os_rx #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_i,
  input  logic [2*LANES-1:0]               sym_datak_i,
  input  logic [LANES-1:0]                 sym_valid_i,
  input  logic [3*LANES-1:0]               rxstatus_i,

  input  logic [LANES-1:0]                 lane_en_i,
  input  logic                             capture_clr_i, // LTSSM state entry

  // Consecutive-reception flags ("all"/"any" over enabled lanes)
  output logic ts1_pad_all_o,   // TS1, Link and Lane = PAD
  output logic ts1_pad_any_o,
  output logic ts2_pad_all_o,   // TS2, Link and Lane = PAD
  output logic ts2_pad_any_o,
  output logic ts1_link_all_o,  // TS1, Link non-PAD, Lane = PAD
  output logic ts1_link_any_o,
  output logic ts1_lane_all_o,  // TS1, Link and Lane non-PAD
  output logic ts1_lane_any_o,
  output logic ts2_cfg_all_o,   // TS2, Link and Lane non-PAD
  output logic ts2_cfg_any_o,
  output logic idle_all_o,      // 8 consecutive Idle Symbol Times (all/any lanes)
  output logic idle_any_o,
  // Combinational: any enabled Lane saw descrambled 00h D this cycle (Base:
  // "16 Idle Symbols sent after receiving one" — one Symbol, not eight).
  output logic idle_sym_any_o,

  // Per-lane TS shape (threshold met). Used to narrow lane_en when the partner
  // configures fewer Lanes than our port width (docs/mac.md §7.1).
  output logic [LANES-1:0] ts1_link_lanes_o,
  output logic [LANES-1:0] ts1_lane_lanes_o,

  // Captured TS fields (sticky until capture_clr_i)
  output logic [7:0]         rx_link_num_o,
  output logic [8*LANES-1:0] rx_lane_num_o,
  output logic [7:0]         rx_n_fts_o,
  output logic [7:0]         rx_rate_id_o,
  output logic [7:0]         rx_train_ctrl_o,
  output logic               rx_lane_num_changed_o,

  output logic [LANES-1:0]   polarity_inverted_o,
  output logic               deskew_done_o,
  output logic               rx_err_o,

  // Toward DLL
  output rivet_pkg::rivet_dll_mac_rx_beat_t dll_rx_beat_o,
  output logic                              dll_rx_valid_o,
  input  logic                              dll_rx_ready_i
);

  import rivet_pkg::*;

  localparam int unsigned SYMS = PIPE_DATA_WIDTH / 8;
  localparam int unsigned WIN  = RIVET_TS_LEN + SYMS - 1;
  localparam int unsigned NSYM = SYMS * LANES;

  localparam logic [3:0] TH_TS     = 4'(RIVET_N_TS_CONSEC);
  localparam logic [3:0] TH_NUM    = 4'(RIVET_N_TS_NUM_CONSEC);
  localparam logic [3:0] TH_IDLE   = 4'(RIVET_N_IDLE_CONSEC);
  localparam logic [3:0] CNT_MAX   = 4'hF;
  localparam logic [3:0] IDLE_STEP = 4'(SYMS); // Idle counts Symbol Times

`ifndef SYNTHESIS
  initial begin
    if (PIPE_DATA_WIDTH != 16)
      $error("rivet_mac_os_rx: only PIPE_DATA_WIDTH=16 is implemented (got %0d)",
             PIPE_DATA_WIDTH);
    if (!rivet_lanes_legal(LANES))
      $error("rivet_mac_os_rx LANES must be 1, 2, or 4");
  end
`endif

  // Symbol window per lane: {valid, is_k, symbol}; index 0 is the newest symbol.
  logic [9:0] win_q [LANES][WIN];

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        for (int unsigned i = 0; i < WIN; i++) win_q[l][i] <= '0;
      end
    end else begin
      for (int unsigned l = 0; l < LANES; l++) begin
        for (int unsigned i = WIN - 1; i >= SYMS; i--) win_q[l][i] <= win_q[l][i-SYMS];
        for (int unsigned s = 0; s < SYMS; s++) begin
          win_q[l][SYMS-1-s] <= {sym_valid_i[l],
                                 sym_datak_i[SYMS*l + s],
                                 sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8]};
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // TS classification
  // ---------------------------------------------------------------------------
  logic [LANES-1:0] hit_ts1_pad;
  logic [LANES-1:0] hit_ts2_pad;
  logic [LANES-1:0] hit_ts1_link;
  logic [LANES-1:0] hit_ts1_lane;
  logic [LANES-1:0] hit_ts2_cfg;
  logic [LANES-1:0] hit_any_ts;
  logic [LANES-1:0] hit_inverted;
  logic [LANES-1:0] hit_idle;
  logic [LANES-1:0] hit_k;

  logic [7:0]       cap_link_num [LANES];
  logic [7:0]       cap_lane_num [LANES];
  logic [7:0]       cap_n_fts    [LANES];
  logic [7:0]       cap_rate_id  [LANES];
  logic [7:0]       cap_train    [LANES];

  always_comb begin
    hit_ts1_pad  = '0;
    hit_ts2_pad  = '0;
    hit_ts1_link = '0;
    hit_ts1_lane = '0;
    hit_ts2_cfg  = '0;
    hit_any_ts   = '0;
    hit_inverted = '0;
    hit_idle     = '0;
    hit_k        = '0;

    for (int unsigned l = 0; l < LANES; l++) begin
      cap_link_num[l] = '0;
      cap_lane_num[l] = '0;
      cap_n_fts[l]    = '0;
      cap_rate_id[l]  = '0;
      cap_train[l]    = '0;

      // Idle / K activity on the newest symbols of this lane.
      for (int unsigned s = 0; s < SYMS; s++) begin
        if (sym_valid_i[l]) begin
          if (sym_datak_i[SYMS*l + s]) hit_k[l] = 1'b1;
          else if (sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8] == 8'h00)
            hit_idle[l] = 1'b1;
        end
      end

      for (int unsigned a = 0; a < SYMS; a++) begin
        logic all_valid;
        logic id_ts1, id_ts2, id_ts1_inv, id_ts2_inv;
        logic com_ok, link_pad, lane_pad;
        logic is_ts1, is_ts2;

        all_valid  = 1'b1;
        id_ts1     = 1'b1;
        id_ts2     = 1'b1;
        id_ts1_inv = 1'b1;
        id_ts2_inv = 1'b1;
        is_ts1     = 1'b0;
        is_ts2     = 1'b0;

        for (int unsigned j = 0; j < RIVET_TS_LEN; j++) begin
          if (!win_q[l][a + RIVET_TS_LEN - 1 - j][9]) all_valid = 1'b0;
        end

        com_ok   = win_q[l][a + 15][8] && (win_q[l][a + 15][7:0] == RIVET_SYM_COM);
        link_pad = win_q[l][a + 14][8] && (win_q[l][a + 14][7:0] == RIVET_SYM_PAD);
        lane_pad = win_q[l][a + 13][8] && (win_q[l][a + 13][7:0] == RIVET_SYM_PAD);

        // Symbols 6..15 carry the TS identifier (or its complement).
        for (int unsigned j = 6; j < RIVET_TS_LEN; j++) begin
          if (win_q[l][a + RIVET_TS_LEN - 1 - j][8]) begin
            id_ts1     = 1'b0;
            id_ts2     = 1'b0;
            id_ts1_inv = 1'b0;
            id_ts2_inv = 1'b0;
          end else begin
            if (win_q[l][a + RIVET_TS_LEN - 1 - j][7:0] != RIVET_SYM_TS1_ID)     id_ts1     = 1'b0;
            if (win_q[l][a + RIVET_TS_LEN - 1 - j][7:0] != RIVET_SYM_TS2_ID)     id_ts2     = 1'b0;
            if (win_q[l][a + RIVET_TS_LEN - 1 - j][7:0] != RIVET_SYM_TS1_ID_INV) id_ts1_inv = 1'b0;
            if (win_q[l][a + RIVET_TS_LEN - 1 - j][7:0] != RIVET_SYM_TS2_ID_INV) id_ts2_inv = 1'b0;
          end
        end

        if (all_valid && com_ok) begin
          is_ts1 = id_ts1 || id_ts1_inv;
          is_ts2 = id_ts2 || id_ts2_inv;

          if (is_ts1 || is_ts2) begin
            hit_any_ts[l]   = 1'b1;
            cap_link_num[l] = win_q[l][a + 14][7:0];
            cap_lane_num[l] = win_q[l][a + 13][7:0];
            cap_n_fts[l]    = win_q[l][a + 12][7:0];
            cap_rate_id[l]  = win_q[l][a + 11][7:0];
            cap_train[l]    = win_q[l][a + 10][7:0];
            if (id_ts1_inv || id_ts2_inv) hit_inverted[l] = 1'b1;

            if (is_ts1) begin
              if (link_pad && lane_pad)        hit_ts1_pad[l]  = 1'b1;
              else if (!link_pad && lane_pad)  hit_ts1_link[l] = 1'b1;
              else if (!link_pad && !lane_pad) hit_ts1_lane[l] = 1'b1;
            end else begin
              if (link_pad && lane_pad)        hit_ts2_pad[l]  = 1'b1;
              else if (!link_pad && !lane_pad) hit_ts2_cfg[l]  = 1'b1;
            end
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Consecutive counters and field capture
  // ---------------------------------------------------------------------------
  logic [3:0] c_ts1_pad_q  [LANES];
  logic [3:0] c_ts2_pad_q  [LANES];
  logic [3:0] c_ts1_link_q [LANES];
  logic [3:0] c_ts1_lane_q [LANES];
  logic [3:0] c_ts2_cfg_q  [LANES];
  logic [3:0] c_idle_q     [LANES];

  logic [7:0]       link_num_q;
  logic [7:0]       n_fts_q;
  logic [7:0]       rate_id_q;
  logic [7:0]       train_q;
  logic [7:0]       lane_num_q     [LANES];
  logic [7:0]       lane_num_ref_q [LANES];
  logic             lane_num_seen_q;
  logic [LANES-1:0] inverted_q;
  logic             deskew_q;
  logic             ts_all_lanes;

  assign ts_all_lanes = ((hit_any_ts | ~lane_en_i) == {LANES{1'b1}}) && (lane_en_i != '0);

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        c_ts1_pad_q[l]    <= '0;
        c_ts2_pad_q[l]    <= '0;
        c_ts1_link_q[l]   <= '0;
        c_ts1_lane_q[l]   <= '0;
        c_ts2_cfg_q[l]    <= '0;
        c_idle_q[l]       <= '0;
        lane_num_q[l]     <= '0;
        lane_num_ref_q[l] <= '0;
      end
      link_num_q      <= '0;
      n_fts_q         <= '0;
      rate_id_q       <= '0;
      train_q         <= '0;
      lane_num_seen_q <= 1'b0;
      inverted_q      <= '0;
      deskew_q        <= 1'b0;
    end else if (capture_clr_i) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        c_ts1_pad_q[l]    <= '0;
        c_ts2_pad_q[l]    <= '0;
        c_ts1_link_q[l]   <= '0;
        c_ts1_lane_q[l]   <= '0;
        c_ts2_cfg_q[l]    <= '0;
        c_idle_q[l]       <= '0;
        lane_num_ref_q[l] <= lane_num_q[l];
      end
      lane_num_seen_q <= 1'b0;
      inverted_q      <= '0;
      deskew_q        <= 1'b0;
    end else begin
      if (ts_all_lanes) deskew_q <= 1'b1;

      for (int unsigned l = 0; l < LANES; l++) begin
        // A TS of one shape breaks the run of every other shape.
        if (hit_any_ts[l]) begin
          c_ts1_pad_q[l]  <= hit_ts1_pad[l]  ? ((c_ts1_pad_q[l]  == CNT_MAX) ? CNT_MAX : c_ts1_pad_q[l]  + 4'd1) : 4'd0;
          c_ts2_pad_q[l]  <= hit_ts2_pad[l]  ? ((c_ts2_pad_q[l]  == CNT_MAX) ? CNT_MAX : c_ts2_pad_q[l]  + 4'd1) : 4'd0;
          c_ts1_link_q[l] <= hit_ts1_link[l] ? ((c_ts1_link_q[l] == CNT_MAX) ? CNT_MAX : c_ts1_link_q[l] + 4'd1) : 4'd0;
          c_ts1_lane_q[l] <= hit_ts1_lane[l] ? ((c_ts1_lane_q[l] == CNT_MAX) ? CNT_MAX : c_ts1_lane_q[l] + 4'd1) : 4'd0;
          c_ts2_cfg_q[l]  <= hit_ts2_cfg[l]  ? ((c_ts2_cfg_q[l]  == CNT_MAX) ? CNT_MAX : c_ts2_cfg_q[l]  + 4'd1) : 4'd0;

          if (hit_inverted[l]) inverted_q[l] <= 1'b1;

          if (!hit_ts1_pad[l] && !hit_ts2_pad[l]) begin
            lane_num_q[l]   <= cap_lane_num[l];
            lane_num_seen_q <= 1'b1;
          end
          // Every lane of a Link carries the same Link number and rate ID.
          if (lane_en_i[l]) begin
            link_num_q <= cap_link_num[l];
            n_fts_q    <= cap_n_fts[l];
            rate_id_q  <= cap_rate_id[l];
            train_q    <= cap_train[l];
          end
        end

        // Idle Symbol Times: descrambled 00h only; any K or non-zero D restarts.
        if (hit_k[l] || (sym_valid_i[l] && !hit_idle[l] && !hit_any_ts[l]))
          c_idle_q[l] <= 4'd0;
        else if (hit_idle[l])
          c_idle_q[l] <= (c_idle_q[l] >= (CNT_MAX - IDLE_STEP)) ? CNT_MAX
                                                                : c_idle_q[l] + IDLE_STEP;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Reductions over enabled lanes
  // ---------------------------------------------------------------------------
  always_comb begin
    ts1_pad_all_o  = 1'b1;
    ts2_pad_all_o  = 1'b1;
    ts1_link_all_o = 1'b1;
    ts1_lane_all_o = 1'b1;
    ts2_cfg_all_o  = 1'b1;
    idle_all_o     = 1'b1;
    ts1_pad_any_o  = 1'b0;
    ts2_pad_any_o  = 1'b0;
    ts1_link_any_o = 1'b0;
    ts1_lane_any_o = 1'b0;
    ts2_cfg_any_o  = 1'b0;
    idle_any_o     = 1'b0;
    idle_sym_any_o = 1'b0;

    for (int unsigned l = 0; l < LANES; l++) begin
      if (lane_en_i[l]) begin
        ts1_pad_all_o  &= (c_ts1_pad_q[l]  >= TH_TS);
        ts2_pad_all_o  &= (c_ts2_pad_q[l]  >= TH_TS);
        ts1_link_all_o &= (c_ts1_link_q[l] >= TH_NUM);
        ts1_lane_all_o &= (c_ts1_lane_q[l] >= TH_NUM);
        ts2_cfg_all_o  &= (c_ts2_cfg_q[l]  >= TH_TS);
        idle_all_o     &= (c_idle_q[l]     >= TH_IDLE);

        ts1_pad_any_o  |= (c_ts1_pad_q[l]  >= TH_TS);
        ts2_pad_any_o  |= (c_ts2_pad_q[l]  >= TH_TS);
        ts1_link_any_o |= (c_ts1_link_q[l] >= TH_NUM);
        ts1_lane_any_o |= (c_ts1_lane_q[l] >= TH_NUM);
        ts2_cfg_any_o  |= (c_ts2_cfg_q[l]  >= TH_TS);
        idle_any_o     |= (c_idle_q[l]     >= TH_IDLE);
        idle_sym_any_o |= hit_idle[l];
      end
    end

    if (lane_en_i == '0) begin
      ts1_pad_all_o  = 1'b0;
      ts2_pad_all_o  = 1'b0;
      ts1_link_all_o = 1'b0;
      ts1_lane_all_o = 1'b0;
      ts2_cfg_all_o  = 1'b0;
      idle_all_o     = 1'b0;
    end
  end

  always_comb begin
    ts1_link_lanes_o = '0;
    ts1_lane_lanes_o = '0;
    for (int unsigned l = 0; l < LANES; l++) begin
      ts1_link_lanes_o[l] = (c_ts1_link_q[l] >= TH_NUM);
      ts1_lane_lanes_o[l] = (c_ts1_lane_q[l] >= TH_NUM);
    end
  end

  always_comb begin
    rx_lane_num_o = '0;
    for (int unsigned l = 0; l < LANES; l++) rx_lane_num_o[8*l +: 8] = lane_num_q[l];
  end

  always_comb begin
    rx_lane_num_changed_o = 1'b0;
    if (lane_num_seen_q) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        if (lane_en_i[l] && (lane_num_q[l] != lane_num_ref_q[l])) rx_lane_num_changed_o = 1'b1;
      end
    end
  end

  assign rx_link_num_o       = link_num_q;
  assign rx_n_fts_o          = n_fts_q;
  assign rx_rate_id_o        = rate_id_q;
  assign rx_train_ctrl_o     = train_q;
  assign polarity_inverted_o = inverted_q;
  assign deskew_done_o       = (LANES == 1) ? 1'b1 : deskew_q;

  // RxStatus errors that the LTSSM treats as loss of a trained link. SKP
  // add/remove are expected elastic-buffer activity, not errors.
  always_comb begin
    rx_err_o = 1'b0;
    for (int unsigned l = 0; l < LANES; l++) begin
      if (lane_en_i[l]) begin
        case (rxstatus_i[3*l +: 3])
          RIVET_RXSTATUS_DECODE_ERR,
          RIVET_RXSTATUS_EB_OVERFLOW,
          RIVET_RXSTATUS_EB_UNDERFLOW,
          RIVET_RXSTATUS_DISPARITY: rx_err_o = 1'b1;
          default: ;
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Packet framing RX: SDP + 6 D-bytes + END, or STP + N D-bytes + END/EDB
  // striped across enabled lanes (Gen2 16b PIPE).
  // Stage P0 pre-decodes framing tokens per symbol slot; Stage P1 packs TLP
  // bytes through a 16-byte gearbox into a 32x64b distributed LUTRAM.
  // ---------------------------------------------------------------------------
  localparam bit PKT_RX_OK        = (PIPE_DATA_WIDTH == 16);
  localparam int unsigned TLP_BUF_B  = RIVET_MAC_TLP_BUF_BYTES;
  localparam int unsigned TLP_RAM_N  = 32;

  typedef enum logic [2:0] {
    RX_IDLE    = 3'b000,
    RX_BODY    = 3'b001,
    RX_HOLD    = 3'b010,
    RX_TLP     = 3'b011,
    RX_TLP_OUT = 3'b100
  } rx_pkt_e;

  // Stage P0: registered per-symbol token flags
  logic             p0_lanes_ok_q;
  logic [NSYM-1:0]  p0_en_q;
  logic [NSYM-1:0]  p0_sdp_q;
  logic [NSYM-1:0]  p0_stp_q;
  logic [NSYM-1:0]  p0_end_q;
  logic [NSYM-1:0]  p0_edb_q;
  logic [NSYM-1:0]  p0_k_q;
  logic [7:0]       p0_data_q [0:NSYM-1];

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      p0_lanes_ok_q <= 1'b0;
      p0_en_q       <= '0;
      p0_sdp_q      <= '0;
      p0_stp_q      <= '0;
      p0_end_q      <= '0;
      p0_edb_q      <= '0;
      p0_k_q        <= '0;
      for (int unsigned p = 0; p < NSYM; p++) p0_data_q[p] <= '0;
    end else begin
      automatic logic ok = PKT_RX_OK && sym_valid_i[0] && lane_en_i[0];
      p0_lanes_ok_q <= ok;
      for (int unsigned s = 0; s < SYMS; s++) begin
        for (int unsigned l = 0; l < LANES; l++) begin
          automatic int unsigned p = s * LANES + l;
          automatic logic [7:0]  b = sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          automatic logic        k = sym_datak_i[SYMS*l + s];
          automatic logic        e = ok && lane_en_i[l];
          p0_en_q[p]   <= e;
          p0_sdp_q[p]  <= e && k && (b == RIVET_SYM_SDP);
          p0_stp_q[p]  <= e && k && (b == RIVET_SYM_STP);
          p0_end_q[p]  <= e && k && (b == RIVET_SYM_END);
          p0_edb_q[p]  <= e && k && (b == RIVET_SYM_EDB);
          p0_k_q[p]    <= e && k;
          p0_data_q[p] <= b;
        end
      end
    end
  end

  rx_pkt_e                rx_pkt_q, rx_pkt_d;
  logic [63:0]            rx_body_q, rx_body_d;
  logic [3:0]             rx_cnt_q, rx_cnt_d;
  logic                   rx_err_pkt_q, rx_err_pkt_d;
  logic                   dll_beat_valid_q, dll_beat_valid_d;
  rivet_dll_mac_rx_beat_t dll_beat_q, dll_beat_d;

  (* ram_style = "distributed" *) logic [63:0] tlp_ram [0:TLP_RAM_N-1];
  logic        tlp_ram_we;
  logic [4:0]  tlp_ram_waddr;
  logic [63:0] tlp_ram_wdata;
  logic [63:0] tlp_ram_rdata;

  logic [55:0] tlp_acc_q, tlp_acc_d;
  logic [2:0]  tlp_acc_cnt_q, tlp_acc_cnt_d;
  logic [4:0]  tlp_wr_slot_q, tlp_wr_slot_d;
  logic [4:0]  tlp_rd_slot_q, tlp_rd_slot_d;
  logic [7:0]  tlp_len_q, tlp_len_d;
  logic [7:0]  tlp_rem_q, tlp_rem_d;
  logic        tlp_sop_q, tlp_sop_d;
  logic        tlp_tail_pend_q, tlp_tail_pend_d;
  logic        tlp_err_q, tlp_err_d;

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

  always_comb begin
    rx_pkt_d         = rx_pkt_q;
    rx_body_d        = rx_body_q;
    rx_cnt_d         = rx_cnt_q;
    rx_err_pkt_d     = rx_err_pkt_q;
    dll_beat_valid_d = dll_beat_valid_q;
    dll_beat_d       = dll_beat_q;
    tlp_acc_d        = tlp_acc_q;
    tlp_acc_cnt_d    = tlp_acc_cnt_q;
    tlp_wr_slot_d    = tlp_wr_slot_q;
    tlp_rd_slot_d    = tlp_rd_slot_q;
    tlp_len_d        = tlp_len_q;
    tlp_rem_d        = tlp_rem_q;
    tlp_sop_d        = tlp_sop_q;
    tlp_tail_pend_d  = 1'b0;
    tlp_err_d        = tlp_err_q;

    tlp_ram_we       = 1'b0;
    tlp_ram_waddr    = tlp_wr_slot_q;
    tlp_ram_wdata    = '0;

    if (dll_beat_valid_q && dll_rx_ready_i) dll_beat_valid_d = 1'b0;

    // Pending tail bytes (<8B) from a TLP whose END beat crossed an 8B boundary
    // write into slot >= 1 while RX_TLP_OUT reads slot 0.
    if (tlp_tail_pend_q) begin
      tlp_ram_we    = 1'b1;
      tlp_ram_waddr = tlp_wr_slot_q;
      tlp_ram_wdata = {8'd0, tlp_acc_q};
      tlp_wr_slot_d = tlp_wr_slot_q + 5'd1;
      tlp_acc_d     = '0;
      tlp_acc_cnt_d = 3'd0;
    end

    if (p0_lanes_ok_q || (rx_pkt_q == RX_HOLD) || (rx_pkt_q == RX_TLP_OUT)) begin
      unique case (rx_pkt_q)
        RX_IDLE: begin
          if (p0_lanes_ok_q) begin
            automatic logic        saw_sdp = 1'b0;
            automatic logic        saw_stp = 1'b0;
            automatic logic [3:0]  c       = 4'd0;
            automatic logic [63:0] b       = '0;
            automatic logic [3:0]  cap_n   = 4'd0;
            automatic logic [7:0]  cap_b [0:7];
            automatic logic [63:0] cap_word;
            automatic logic        err       = 1'b0;
            automatic logic        done      = 1'b0;
            automatic logic        nullified = 1'b0;

            for (int unsigned i = 0; i < 8; i++) cap_b[i] = '0;

            for (int unsigned p = 0; p < NSYM; p++) begin
              if (p0_en_q[p] && !done) begin
                if (!saw_sdp && !saw_stp) begin
                  if (p0_sdp_q[p])      saw_sdp = 1'b1;
                  else if (p0_stp_q[p]) saw_stp = 1'b1;
                end else if (saw_sdp) begin
                  if (c < 4'(RIVET_DLLP_WIRE_BYTES)) begin
                    if (p0_k_q[p]) begin
                      err  = 1'b1;
                      done = 1'b1;
                    end else begin
                      b[8*c +: 8] = p0_data_q[p];
                      c = c + 4'd1;
                    end
                  end else begin
                    if (p0_end_q[p]) begin
                      done = 1'b1;
                    end else if (p0_edb_q[p]) begin
                      nullified = 1'b1;
                      done      = 1'b1;
                    end else if (!p0_k_q[p] && (p0_data_q[p] == 8'h00)) begin
                    end else begin
                      err  = 1'b1;
                      done = 1'b1;
                    end
                  end
                end else begin
                  if (p0_end_q[p]) begin
                    done = 1'b1;
                  end else if (p0_edb_q[p]) begin
                    nullified = 1'b1;
                    done      = 1'b1;
                  end else if (p0_k_q[p]) begin
                    err  = 1'b1;
                    done = 1'b1;
                  end else begin
                    cap_b[cap_n[2:0]] = p0_data_q[p];
                    cap_n = cap_n + 4'd1;
                  end
                end
              end
            end

            cap_word = {cap_b[7], cap_b[6], cap_b[5], cap_b[4],
                        cap_b[3], cap_b[2], cap_b[1], cap_b[0]};

            if (saw_sdp) begin
              rx_body_d    = b;
              rx_cnt_d     = c;
              rx_err_pkt_d = err;
              if (done) begin
                if (!dll_beat_valid_q || dll_rx_ready_i) begin
                  dll_beat_d.data     = b;
                  dll_beat_d.keep     = 8'hFF;
                  dll_beat_d.sop      = 1'b1;
                  dll_beat_d.eop      = 1'b1;
                  dll_beat_d.err      = err | nullified;
                  dll_beat_d.pkt_type = RIVET_MAC_PKT_DLLP;
                  dll_beat_valid_d    = 1'b1;
                  rx_pkt_d            = RX_IDLE;
                  rx_cnt_d            = 4'd0;
                end else begin
                  rx_pkt_d = RX_HOLD;
                end
              end else begin
                rx_pkt_d = RX_BODY;
              end
            end else if (saw_stp) begin
              tlp_len_d     = {4'd0, cap_n};
              tlp_rem_d     = {4'd0, cap_n};
              tlp_err_d     = err | nullified | (done && (cap_n == 4'd0));
              tlp_rd_slot_d = 5'd0;
              tlp_sop_d     = 1'b1;
              if (done) begin
                tlp_ram_we    = 1'b1;
                tlp_ram_waddr = 5'd0;
                tlp_ram_wdata = cap_word;
                tlp_wr_slot_d = 5'd1;
                tlp_acc_d     = '0;
                tlp_acc_cnt_d = 3'd0;
                rx_pkt_d      = RX_TLP_OUT;
              end else begin
                tlp_wr_slot_d = 5'd0;
                tlp_acc_d     = cap_word[55:0];
                tlp_acc_cnt_d = cap_n[2:0];
                rx_pkt_d      = RX_TLP;
              end
            end
          end
        end

        RX_BODY: begin
          if (p0_lanes_ok_q) begin
            automatic logic [3:0]  c         = rx_cnt_q;
            automatic logic [63:0] b         = rx_body_q;
            automatic logic        err       = rx_err_pkt_q;
            automatic logic        done      = 1'b0;
            automatic logic        nullified = 1'b0;

            for (int unsigned p = 0; p < NSYM; p++) begin
              if (p0_en_q[p] && !done) begin
                if (c < 4'(RIVET_DLLP_WIRE_BYTES)) begin
                  if (p0_k_q[p]) begin
                    err  = 1'b1;
                    done = 1'b1;
                  end else begin
                    b[8*c +: 8] = p0_data_q[p];
                    c = c + 4'd1;
                  end
                end else begin
                  if (p0_end_q[p]) begin
                    done = 1'b1;
                  end else if (p0_edb_q[p]) begin
                    nullified = 1'b1;
                    done      = 1'b1;
                  end else if (!p0_k_q[p] && (p0_data_q[p] == 8'h00)) begin
                  end else begin
                    err  = 1'b1;
                    done = 1'b1;
                  end
                end
              end
            end

            rx_body_d    = b;
            rx_cnt_d     = c;
            rx_err_pkt_d = err;

            if (done) begin
              if (!dll_beat_valid_q || dll_rx_ready_i) begin
                dll_beat_d.data     = b;
                dll_beat_d.keep     = 8'hFF;
                dll_beat_d.sop      = 1'b1;
                dll_beat_d.eop      = 1'b1;
                dll_beat_d.err      = err | nullified;
                dll_beat_d.pkt_type = RIVET_MAC_PKT_DLLP;
                dll_beat_valid_d    = 1'b1;
                rx_pkt_d            = RX_IDLE;
                rx_cnt_d            = 4'd0;
              end else begin
                rx_pkt_d = RX_HOLD;
              end
            end
          end
        end

        RX_HOLD: begin
          if (dll_rx_ready_i) begin
            dll_beat_d.data     = rx_body_q;
            dll_beat_d.keep     = 8'hFF;
            dll_beat_d.sop      = 1'b1;
            dll_beat_d.eop      = 1'b1;
            dll_beat_d.err      = rx_err_pkt_q;
            dll_beat_d.pkt_type = RIVET_MAC_PKT_DLLP;
            dll_beat_valid_d    = 1'b1;
            rx_pkt_d            = RX_IDLE;
            rx_cnt_d            = 4'd0;
          end
        end

        RX_TLP: begin
          if (p0_lanes_ok_q) begin
            automatic logic [7:0]   cap_b [0:7];
            automatic logic [3:0]   cap_n     = 4'd0;
            automatic logic [63:0]  cap_word;
            automatic logic [119:0] comb_bytes;
            automatic logic [3:0]   comb_cnt;
            automatic logic [8:0]   new_len;
            automatic logic         len_ovf;
            automatic logic         err       = tlp_err_q;
            automatic logic         done      = 1'b0;
            automatic logic         nullified = 1'b0;

            for (int unsigned i = 0; i < 8; i++) cap_b[i] = '0;

            for (int unsigned p = 0; p < NSYM; p++) begin
              if (p0_en_q[p] && !done) begin
                if (p0_end_q[p]) begin
                  done = 1'b1;
                end else if (p0_edb_q[p]) begin
                  nullified = 1'b1;
                  done      = 1'b1;
                end else if (p0_k_q[p]) begin
                  err  = 1'b1;
                  done = 1'b1;
                end else begin
                  cap_b[cap_n[2:0]] = p0_data_q[p];
                  cap_n = cap_n + 4'd1;
                end
              end
            end

            new_len = {1'b0, tlp_len_q} + {5'd0, cap_n};
            len_ovf = (new_len > 9'(TLP_BUF_B));
            if (len_ovf) begin
              err  = 1'b1;
              done = 1'b1;
            end

            cap_word = {cap_b[7], cap_b[6], cap_b[5], cap_b[4],
                        cap_b[3], cap_b[2], cap_b[1], cap_b[0]};
            unique case (tlp_acc_cnt_q)
              3'd0: comb_bytes = {56'd0, cap_word};
              3'd1: comb_bytes = {48'd0, cap_word, tlp_acc_q[ 7:0]};
              3'd2: comb_bytes = {40'd0, cap_word, tlp_acc_q[15:0]};
              3'd3: comb_bytes = {32'd0, cap_word, tlp_acc_q[23:0]};
              3'd4: comb_bytes = {24'd0, cap_word, tlp_acc_q[31:0]};
              3'd5: comb_bytes = {16'd0, cap_word, tlp_acc_q[39:0]};
              3'd6: comb_bytes = { 8'd0, cap_word, tlp_acc_q[47:0]};
              3'd7: comb_bytes = {       cap_word, tlp_acc_q[55:0]};
            endcase
            comb_cnt = {1'b0, tlp_acc_cnt_q} + cap_n;

            tlp_len_d = len_ovf ? 8'(TLP_BUF_B) : new_len[7:0];
            tlp_err_d = err | nullified | (done && (new_len == 9'd0));

            if (!done) begin
              if (comb_cnt[3]) begin
                tlp_ram_we    = 1'b1;
                tlp_ram_waddr = tlp_wr_slot_q;
                tlp_ram_wdata = comb_bytes[63:0];
                tlp_wr_slot_d = tlp_wr_slot_q + 5'd1;
                tlp_acc_d     = comb_bytes[119:64];
                tlp_acc_cnt_d = comb_cnt[2:0];
              end else begin
                tlp_acc_d     = comb_bytes[55:0];
                tlp_acc_cnt_d = comb_cnt[2:0];
              end
            end else begin
              tlp_rd_slot_d = 5'd0;
              tlp_sop_d     = 1'b1;
              tlp_rem_d     = tlp_len_d;
              if (!tlp_err_d && (comb_cnt != 4'd0)) begin
                tlp_ram_we    = 1'b1;
                tlp_ram_waddr = tlp_wr_slot_q;
                tlp_ram_wdata = comb_bytes[63:0];
                tlp_wr_slot_d = tlp_wr_slot_q + 5'd1;
              end
              if (!tlp_err_d && comb_cnt[3] && (comb_cnt[2:0] != 3'd0)) begin
                tlp_acc_d       = comb_bytes[119:64];
                tlp_acc_cnt_d   = comb_cnt[2:0];
                tlp_tail_pend_d = 1'b1;
              end else begin
                tlp_acc_d     = '0;
                tlp_acc_cnt_d = 3'd0;
              end
              rx_pkt_d = RX_TLP_OUT;
            end
          end
        end

        RX_TLP_OUT: begin
          automatic logic [3:0] n;
          automatic logic       slot;
          n    = (tlp_rem_q >= 8'd8) ? 4'd8 : tlp_rem_q[3:0];
          slot = !dll_beat_valid_q || dll_rx_ready_i;
          if (slot) begin
            dll_beat_d          = '0;
            dll_beat_d.pkt_type = RIVET_MAC_PKT_TLP;
            dll_beat_d.sop      = tlp_sop_q;
            if (tlp_err_q) begin
              dll_beat_d.eop   = 1'b1;
              dll_beat_d.err   = 1'b1;
              dll_beat_d.keep  = 8'hFF;
              dll_beat_valid_d = 1'b1;
              rx_pkt_d         = RX_IDLE;
              tlp_rem_d        = 8'd0;
            end else if (n != 4'd0) begin
              for (int unsigned i = 0; i < 8; i++) begin
                if (4'(i) < n) begin
                  dll_beat_d.data[8*i +: 8] = tlp_ram_rdata[8*i +: 8];
                  dll_beat_d.keep[i]        = 1'b1;
                end
              end
              dll_beat_d.eop   = (tlp_rem_q <= 8'd8);
              dll_beat_d.err   = 1'b0;
              dll_beat_valid_d = 1'b1;
              tlp_sop_d        = 1'b0;
              if (tlp_rem_q <= 8'd8) begin
                tlp_rem_d = 8'd0;
                rx_pkt_d  = RX_IDLE;
              end else begin
                tlp_rem_d     = tlp_rem_q - 8'd8;
                tlp_rd_slot_d = tlp_rd_slot_q + 5'd1;
              end
            end else begin
              rx_pkt_d = RX_IDLE;
            end
          end
        end

        default: rx_pkt_d = RX_IDLE;
      endcase
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_pkt_q         <= RX_IDLE;
      rx_body_q        <= '0;
      rx_cnt_q         <= '0;
      rx_err_pkt_q     <= 1'b0;
      dll_beat_valid_q <= 1'b0;
      dll_beat_q       <= '0;
      tlp_acc_q        <= '0;
      tlp_acc_cnt_q    <= '0;
      tlp_wr_slot_q    <= '0;
      tlp_rd_slot_q    <= '0;
      tlp_len_q        <= '0;
      tlp_rem_q        <= '0;
      tlp_sop_q        <= 1'b0;
      tlp_tail_pend_q  <= 1'b0;
      tlp_err_q        <= 1'b0;
    end else begin
      rx_pkt_q         <= rx_pkt_d;
      rx_body_q        <= rx_body_d;
      rx_cnt_q         <= rx_cnt_d;
      rx_err_pkt_q     <= rx_err_pkt_d;
      dll_beat_valid_q <= dll_beat_valid_d;
      dll_beat_q       <= dll_beat_d;
      tlp_acc_q        <= tlp_acc_d;
      tlp_acc_cnt_q    <= tlp_acc_cnt_d;
      tlp_wr_slot_q    <= tlp_wr_slot_d;
      tlp_rd_slot_q    <= tlp_rd_slot_d;
      tlp_len_q        <= tlp_len_d;
      tlp_rem_q        <= tlp_rem_d;
      tlp_sop_q        <= tlp_sop_d;
      tlp_tail_pend_q  <= tlp_tail_pend_d;
      tlp_err_q        <= tlp_err_d;
    end
  end

  assign dll_rx_beat_o  = dll_beat_q;
  assign dll_rx_valid_o = dll_beat_valid_q;

endmodule : rivet_mac_os_rx
