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
// A polarity-inverted lane delivers the complement of the TS identifier
// (Base 2.1 §4.2.4.4). Polling accepts "training sequences or their complement",
// so inverted sets still count and the inversion is reported for rxpolarity.

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
  output logic idle_all_o,      // consecutive Idle Symbol Times
  output logic idle_any_o,

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

  // Toward DLL (idle until the DLL slice)
  output rivet_pkg::rivet_dll_mac_rx_beat_t dll_rx_beat_o,
  output logic                              dll_rx_valid_o,
  input  logic                              dll_rx_ready_i
);

  import rivet_pkg::*;

  localparam int unsigned SYMS = PIPE_DATA_WIDTH / 8;
  localparam int unsigned WIN  = RIVET_TS_LEN + SYMS - 1;

  localparam logic [3:0] TH_TS   = 4'(RIVET_N_TS_CONSEC);
  localparam logic [3:0] TH_NUM  = 4'(RIVET_N_TS_NUM_CONSEC);
  localparam logic [3:0] TH_IDLE = 4'(RIVET_N_IDLE_CONSEC);
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
          if (sym_datak_i[SYMS*l + s]) hit_k[l]    = 1'b1;
          else                         hit_idle[l] = 1'b1;
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
  logic [7:0]       lane_num_q  [LANES];
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

        // Idle Symbol Times: any K symbol restarts the run.
        if (hit_k[l])         c_idle_q[l] <= 4'd0;
        else if (hit_idle[l]) c_idle_q[l] <= (c_idle_q[l] >= (CNT_MAX - IDLE_STEP)) ? CNT_MAX
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

  // DLL RX path is not driven yet.
  assign dll_rx_beat_o  = '0;
  assign dll_rx_valid_o = 1'b0;

  logic _unused_ok;
  assign _unused_ok = dll_rx_ready_i;

endmodule : rivet_mac_os_rx
