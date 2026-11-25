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
  input  logic [2:0] rate_i = rivet_pkg::RIVET_PIPE_RATE_GEN2,

  input  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_i,
  input  logic [2*LANES-1:0]               sym_datak_i,
  input  logic [LANES-1:0]                 sym_valid_i,
  input  logic [LANES-1:0]                 os_block_i = '0,
  input  logic [LANES-1:0]                 block_start_i = '0,
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
  output logic [7:0]         rx_eq_ctrl_o,
  output logic [7:0]         rx_eq_data_o,
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
    // 32 elaborates for Gen3. 64 elaborates for Gen4. The 64-bit block
    // pipe is a later slice.
    if (!(PIPE_DATA_WIDTH == 16 || PIPE_DATA_WIDTH == 32 ||
          PIPE_DATA_WIDTH == 64))
      $error("rivet_mac_os_rx: PIPE_DATA_WIDTH must be 16, 32, or 64 (got %0d)",
             PIPE_DATA_WIDTH);
    if (!rivet_lanes_legal(LANES))
      $error("rivet_mac_os_rx LANES must be 1, 2, or 4");
  end
`endif

  // Symbol window per lane: {valid, is_k, symbol}; index 0 is the newest symbol.
  logic [9:0] win_q [LANES][WIN];
  // First 12 bytes of a Gen3 ordered-set block. The last word is parsed live.
  logic [7:0] blk_q [LANES][12];
  logic [4:0] blk_n_q [LANES];

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        blk_n_q[l] <= '0;
        for (int unsigned j = 0; j < 12; j++) blk_q[l][j] <= '0;
      end
    end else if (!rivet_pkg::rivet_pipe_block_rate(rate_i)) begin
      for (int unsigned l = 0; l < LANES; l++) blk_n_q[l] <= '0;
    end else if (rate_i == RIVET_PIPE_RATE_GEN4) begin
      // Two 8-byte words. Bytes 0–7 are stored on the start word and parsed
      // when the second word arrives.
      for (int unsigned l = 0; l < LANES; l++) begin
        if (sym_valid_i[l] && os_block_i[l] && block_start_i[l]) begin
          for (int unsigned s = 0; s < 8; s++) begin
            if (s < SYMS)
              blk_q[l][s] <= sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          end
          blk_n_q[l] <= 5'd8;
        end else if (sym_valid_i[l] && os_block_i[l] && (blk_n_q[l] == 5'd8)) begin
          blk_n_q[l] <= '0;
        end
      end
    end else begin
      for (int unsigned l = 0; l < LANES; l++) begin
        if (sym_valid_i[l] && os_block_i[l] && block_start_i[l]) begin
          for (int unsigned s = 0; s < 4; s++) begin
            if (s < SYMS)
              blk_q[l][s] <= sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          end
          blk_n_q[l] <= 5'd4;
        end else if (sym_valid_i[l] && os_block_i[l] && (blk_n_q[l] < 5'd12)) begin
          for (int unsigned s = 0; s < 4; s++) begin
            if ((s < SYMS) && ((blk_n_q[l] + 5'(s)) < 5'd12))
              blk_q[l][blk_n_q[l] + s] <= sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          end
          blk_n_q[l] <= blk_n_q[l] + 5'd4;
        end else if (sym_valid_i[l] && os_block_i[l] && (blk_n_q[l] == 5'd12)) begin
          blk_n_q[l] <= '0;
        end
      end
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        for (int unsigned i = 0; i < WIN; i++) win_q[l][i] <= '0;
      end
    end else begin
      for (int unsigned l = 0; l < LANES; l++) begin
        // Gen1/Gen2 on a wide pipe: shift two symbols from the low 16 bits.
        if ((PIPE_DATA_WIDTH > 16) && !rivet_pkg::rivet_pipe_block_rate(rate_i)) begin
          for (int unsigned i = WIN - 1; i >= 2; i--) win_q[l][i] <= win_q[l][i-2];
          for (int unsigned s = 0; s < 2; s++) begin
            win_q[l][1-s] <= {sym_valid_i[l],
                              sym_datak_i[2*l + s],
                              sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8]};
          end
        end else begin
          for (int unsigned i = WIN - 1; i >= SYMS; i--) win_q[l][i] <= win_q[l][i-SYMS];
          for (int unsigned s = 0; s < SYMS; s++) begin
            win_q[l][SYMS-1-s] <= {sym_valid_i[l],
                                   (s < 2) ? sym_datak_i[2*l + s] : 1'b0,
                                   sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8]};
          end
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
  logic [7:0]       cap_eq_ctrl  [LANES];
  logic [7:0]       cap_eq_data  [LANES];

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
      cap_eq_ctrl[l]  = '0;
      cap_eq_data[l]  = '0;

      if (rivet_pkg::rivet_pipe_block_rate(rate_i) && sym_valid_i[l] && os_block_i[l] &&
          !block_start_i[l] &&
          (((rate_i == RIVET_PIPE_RATE_GEN3) && (blk_n_q[l] == 5'd12)) ||
           ((rate_i == RIVET_PIPE_RATE_GEN4) && (blk_n_q[l] == 5'd8))) &&
          ((blk_q[l][0] == RIVET_SYM_TS1_BLK) || (blk_q[l][0] == RIVET_SYM_TS2_BLK))) begin
        hit_any_ts[l]   = 1'b1;
        cap_link_num[l] = blk_q[l][1];
        cap_lane_num[l] = blk_q[l][2];
        cap_n_fts[l]    = blk_q[l][3];
        cap_rate_id[l]  = blk_q[l][4];
        cap_train[l]    = blk_q[l][5];
        cap_eq_ctrl[l]  = blk_q[l][6];
        cap_eq_data[l]  = blk_q[l][7];
        if (blk_q[l][0] == RIVET_SYM_TS1_BLK) begin
          if ((blk_q[l][1] == RIVET_SYM_PAD) && (blk_q[l][2] == RIVET_SYM_PAD))
            hit_ts1_pad[l] = 1'b1;
          else if ((blk_q[l][1] != RIVET_SYM_PAD) && (blk_q[l][2] == RIVET_SYM_PAD))
            hit_ts1_link[l] = 1'b1;
          else if ((blk_q[l][1] != RIVET_SYM_PAD) && (blk_q[l][2] != RIVET_SYM_PAD))
            hit_ts1_lane[l] = 1'b1;
        end else if ((blk_q[l][1] == RIVET_SYM_PAD) && (blk_q[l][2] == RIVET_SYM_PAD)) begin
          hit_ts2_pad[l] = 1'b1;
        end else if ((blk_q[l][1] != RIVET_SYM_PAD) && (blk_q[l][2] != RIVET_SYM_PAD)) begin
          hit_ts2_cfg[l] = 1'b1;
        end
      end

      // A Gen3 data block (sync header 01) is logical idle for Recovery.Idle.
      if (rivet_pkg::rivet_pipe_block_rate(rate_i) && sym_valid_i[l] && !os_block_i[l])
        hit_idle[l] = 1'b1;

      // Idle / K activity on the newest symbols of this lane.
      for (int unsigned s = 0; s < SYMS; s++) begin
        if (s >= rivet_pkg::rivet_pipe_nsym(rate_i))
          continue;
        if (sym_valid_i[l]) begin
          if ((s < 2) && sym_datak_i[2*l + s]) hit_k[l] = 1'b1;
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
        if (a >= rivet_pkg::rivet_pipe_nsym(rate_i))
          continue;

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

        if (!rivet_pkg::rivet_pipe_block_rate(rate_i) && all_valid && com_ok) begin
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
  logic [7:0]       eq_ctrl_q;
  logic [7:0]       eq_data_q;
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
      eq_ctrl_q       <= '0;
      eq_data_q       <= '0;
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
            eq_ctrl_q  <= cap_eq_ctrl[l];
            eq_data_q  <= cap_eq_data[l];
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
  assign rx_eq_ctrl_o        = eq_ctrl_q;
  assign rx_eq_data_o        = eq_data_q;
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
  // bytes through a 16-byte gearbox into a circular block RAM. Playback of
  // one frame overlaps capture of the next, so a 4 KB completion does not
  // stall the wire for a second copy.
  // ---------------------------------------------------------------------------
  localparam bit PKT_RX_OK           = (PIPE_DATA_WIDTH == 16);
  // A 32-bit PIPE symbol time is 16 bytes. Playback hands the DLL that
  // much per beat. The 16-bit PIPE stays at 8 bytes.
  // Playback beat. Gen2 is 8 bytes, Gen3 is 16, Gen4 (64-bit PIPE) is 32.
  localparam int unsigned RX_PLAY_B  = (PIPE_DATA_WIDTH >= 64) ? 32 :
                                       (PIPE_DATA_WIDTH == 32) ? 16 : 8;
  // Gen4 only. Playback starts once one beat is in RAM, while capture
  // of that frame is still running.
  localparam bit           RX_CUT     = (PIPE_DATA_WIDTH >= 64);
  localparam int unsigned RX_PLAY_W  = RX_PLAY_B / 8;
  localparam int unsigned TLP_FRAME_MAX = RIVET_MAC_TLP_BUF_BYTES;
  // Eight max-payload frames in flight. Playback cannot drain while the
  // DLL is still presenting the previous frame, so the wire runs ahead.
  localparam int unsigned TLP_RAM_N  = 4096;
  localparam int unsigned TLP_AW     = 12;
  localparam int unsigned TLP_Q      = 16;

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
  // Gen3 TLP: STP, then a 2-byte length, then that many DLL bytes. The length
  // is stripped here and the following idle byte is presented as END so the
  // Gen2 gearbox can run. Gen3 DLLP: SDP, then 6 payload bytes, then END.
  // Payload and CRC bytes may equal FB, 5C, FD, or FE, so both framing bodies
  // mask token detection until their byte counts expire.
  logic [2:0]       gf_st_q;
  logic [15:0]      gf_left_q;

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      p0_lanes_ok_q <= 1'b0;
      p0_en_q       <= '0;
      p0_sdp_q      <= '0;
      p0_stp_q      <= '0;
      p0_end_q      <= '0;
      p0_edb_q      <= '0;
      p0_k_q        <= '0;
      gf_st_q       <= '0;
      gf_left_q     <= '0;
      for (int unsigned p = 0; p < NSYM; p++) p0_data_q[p] <= '0;
    end else begin
      // A Gen3 32-bit block and a Gen4 64-bit block carry the same tokens
      // as data bytes, with no K bit, and only inside a data block.
      automatic logic gen3_pkt = ((PIPE_DATA_WIDTH == 32) &&
                                  (rate_i == RIVET_PIPE_RATE_GEN3)) ||
                                 ((PIPE_DATA_WIDTH == 64) &&
                                  (rate_i == RIVET_PIPE_RATE_GEN4));
      automatic logic ok = (PKT_RX_OK || gen3_pkt) && sym_valid_i[0] && lane_en_i[0];
      automatic logic [NSYM-1:0] en_t, sdp_t, stp_t, end_t, edb_t, k_t;
      automatic logic [7:0] data_t [0:NSYM-1];
      automatic logic [2:0]  st;
      automatic logic [15:0] left;
      en_t = '0; sdp_t = '0; stp_t = '0; end_t = '0; edb_t = '0; k_t = '0;
      for (int unsigned p = 0; p < NSYM; p++) data_t[p] = '0;
      p0_lanes_ok_q <= ok;
      for (int unsigned s = 0; s < SYMS; s++) begin
        for (int unsigned l = 0; l < LANES; l++) begin
          automatic int unsigned p = s * LANES + l;
          automatic logic [7:0]  b = sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
          automatic logic        k = (s < 2) ? sym_datak_i[2*l + s] : 1'b0;
          automatic logic        tok = k || (gen3_pkt && !os_block_i[l]);
          // Gen3 data blocks carry four symbol times. A cycle that holds
          // more than eight frame bytes writes a second RAM word below.
          automatic logic        e = ok && lane_en_i[l] && !(gen3_pkt && os_block_i[l]);
          en_t[p]   = e;
          sdp_t[p]  = e && tok && (b == RIVET_SYM_SDP);
          stp_t[p]  = e && tok && (b == RIVET_SYM_STP);
          end_t[p]  = e && tok && (b == RIVET_SYM_END);
          edb_t[p]  = e && tok && (b == RIVET_SYM_EDB);
          k_t[p]    = e && k;
          data_t[p] = b;
        end
      end
      st   = gf_st_q;
      left = gf_left_q;
      if (gen3_pkt) begin
        for (int unsigned p = 0; p < NSYM; p++) begin
          if (en_t[p]) begin
            if (st == 3'd0) begin
              if (stp_t[p]) begin
                st = 3'd1;
              end else if (sdp_t[p]) begin
                st   = 3'd4;
                left = 16'(RIVET_DLLP_WIRE_BYTES);
              end
            end else if (st == 3'd1) begin
              left     = {8'd0, data_t[p]};
              en_t[p]  = 1'b0;
              stp_t[p] = 1'b0;
              sdp_t[p] = 1'b0;
              end_t[p] = 1'b0;
              edb_t[p] = 1'b0;
              st       = 3'd2;
            end else if (st == 3'd2) begin
              left     = {data_t[p], left[7:0]};
              en_t[p]  = 1'b0;
              stp_t[p] = 1'b0;
              sdp_t[p] = 1'b0;
              end_t[p] = 1'b0;
              edb_t[p] = 1'b0;
              st       = 3'd3;
            end else if (st == 3'd4) begin
              stp_t[p] = 1'b0;
              sdp_t[p] = 1'b0;
              if (left == 16'd0) begin
                st = 3'd0;
              end else begin
                end_t[p] = 1'b0;
                edb_t[p] = 1'b0;
                left     = left - 16'd1;
              end
            end else if (left == 16'd0) begin
              end_t[p] = 1'b1;
              edb_t[p] = 1'b0;
              stp_t[p] = 1'b0;
              sdp_t[p] = 1'b0;
              st       = 3'd0;
            end else begin
              end_t[p] = 1'b0;
              edb_t[p] = 1'b0;
              stp_t[p] = 1'b0;
              sdp_t[p] = 1'b0;
              left     = left - 16'd1;
            end
          end
        end
      end else begin
        st   = 3'd0;
        left = 16'd0;
      end
      gf_st_q   <= st;
      gf_left_q <= left;
      p0_en_q   <= en_t;
      p0_sdp_q  <= sdp_t;
      p0_stp_q  <= stp_t;
      p0_end_q  <= end_t;
      p0_edb_q  <= edb_t;
      p0_k_q    <= k_t;
      for (int unsigned p = 0; p < NSYM; p++) p0_data_q[p] <= data_t[p];
    end
  end

  rx_pkt_e                rx_pkt_q, rx_pkt_d;
  logic [63:0]            rx_body_q, rx_body_d;
  logic [3:0]             rx_cnt_q, rx_cnt_d;
  logic                   rx_err_pkt_q, rx_err_pkt_d;
  logic                   dll_beat_valid_q, dll_beat_valid_d;
  rivet_dll_mac_rx_beat_t dll_beat_q, dll_beat_d;

  (* ram_style = "block" *) logic [63:0] tlp_ram [0:TLP_RAM_N-1];
  logic                    tlp_ram_we;
  logic [TLP_AW-1:0]       tlp_ram_waddr;
  logic [63:0]             tlp_ram_wdata;
  // Second write in the same cycle. A Gen3 x4 data beat is 16 bytes, and
  // the accumulator holds only seven, so the extra word cannot wait.
  logic                    tlp_ram_we2;
  logic [TLP_AW-1:0]       tlp_ram_waddr2;
  logic [63:0]             tlp_ram_wdata2;
  // Gen4 x4 delivers 32 bytes in one beat. Two write ports hold 16.
  logic                    tlp_ram_we3;
  logic [TLP_AW-1:0]       tlp_ram_waddr3;
  logic [63:0]             tlp_ram_wdata3;
  logic                    tlp_ram_we4;
  logic [TLP_AW-1:0]       tlp_ram_waddr4;
  logic [63:0]             tlp_ram_wdata4;
  logic [63:0]             tlp_ram_rd_q;
  logic [63:0]             tlp_ram_rd_hi_q;
  logic [63:0]             tlp_ram_rd_c_q;
  logic [63:0]             tlp_ram_rd_d_q;
  logic                    tlp_rd_issue;

  logic [55:0]             tlp_acc_q, tlp_acc_d;
  logic [2:0]              tlp_acc_cnt_q, tlp_acc_cnt_d;
  logic [TLP_AW-1:0]       tlp_wr_slot_q, tlp_wr_slot_d;
  logic [TLP_AW-1:0]       tlp_base_q, tlp_base_d;
  logic [12:0]             tlp_len_q, tlp_len_d;
  logic                    tlp_tail_pend_q, tlp_tail_pend_d;
  logic                    tlp_err_q, tlp_err_d;
  logic                    frame_push_d;
  logic [TLP_AW-1:0]       frame_push_base_d;
  logic [12:0]             frame_push_len_d;
  logic                    frame_push_err_d;
  logic [TLP_AW-1:0]       q_base [0:TLP_Q-1];
  logic [12:0]             q_len  [0:TLP_Q-1];
  logic                    q_err  [0:TLP_Q-1];
  logic [4:0]              q_wptr_q, q_rptr_q, q_count_q;
  logic                    rd_pop;
  logic [1:0]              rd_ph_q, rd_ph_d;
  logic [12:0]             rd_rem_q, rd_rem_d;
  logic                    rd_sop_q, rd_sop_d;
  logic                    rd_err_q, rd_err_d;
  logic [TLP_AW-1:0]       rd_addr_q, rd_addr_d;
  logic [2:0]              rd_words;
  logic [11:0]             rd_drop;
  logic [12:0]             used_q;
  // Live playback of the frame still being captured. Gen4 pipe only.
  logic                    live_q, live_d;
  logic                    live_closed_q, live_closed_d;
  logic [12:0]             live_len_q, live_len_d;
  logic [12:0]             live_sent_q, live_sent_d;
  logic [TLP_AW-1:0]       live_base_q, live_base_d;
  // A finished DLLP waits here when the beat slot is busy. Framing stays in
  // IDLE/RX_TLP so the next TLP is not dropped while the DLLP waits.
  logic                    dllp_park_q, dllp_park_d;
  logic [63:0]             dllp_park_data_q, dllp_park_data_d;
  logic                    dllp_park_err_q, dllp_park_err_d;
  logic                    dllp_park_ld;

`ifndef SYNTHESIS
  initial begin
    for (int unsigned ii = 0; ii < TLP_RAM_N; ii++) tlp_ram[ii] = '0;
  end
`endif

  always_ff @(posedge pclk_i) begin
    if (tlp_ram_we)
      tlp_ram[tlp_ram_waddr] <= tlp_ram_wdata;
    if (tlp_ram_we2)
      tlp_ram[tlp_ram_waddr2] <= tlp_ram_wdata2;
    if (tlp_ram_we3)
      tlp_ram[tlp_ram_waddr3] <= tlp_ram_wdata3;
    if (tlp_ram_we4)
      tlp_ram[tlp_ram_waddr4] <= tlp_ram_wdata4;
  end

  // Pack payload bytes into RAM words. A tail flush already owns port 0,
  // so nport starts at 1 in that cycle. At most four words (32 bytes).
  task automatic rx_push_word(
      inout int unsigned       nport,
      input logic [63:0]       word,
      input logic [TLP_AW-1:0] addr
  );
    if (nport == 0) begin
      tlp_ram_we    = 1'b1;
      tlp_ram_waddr = addr;
      tlp_ram_wdata = word;
    end else if (nport == 1) begin
      tlp_ram_we2    = 1'b1;
      tlp_ram_waddr2 = addr;
      tlp_ram_wdata2 = word;
    end else if (nport == 2) begin
      tlp_ram_we3    = 1'b1;
      tlp_ram_waddr3 = addr;
      tlp_ram_wdata3 = word;
    end else if (nport == 3) begin
      tlp_ram_we4    = 1'b1;
      tlp_ram_waddr4 = addr;
      tlp_ram_wdata4 = word;
    end
    if (nport < 4)
      nport = nport + 1;
  endtask

  task automatic rx_store(
      input  logic [319:0]       raw_b_bytes,
      input  int unsigned        nbytes,
      inout  logic [TLP_AW-1:0]  slot,
      output logic [55:0]        acc,
      output logic [2:0]         acc_n,
      inout  int unsigned        nport,
      output logic               overflow
  );
    int unsigned bi;
    int unsigned nleft;
    logic [63:0] word;
    logic [7:0]  bb [64];
    logic [7:0]  ab [8];
    logic [5:0]  ix;
    logic [2:0]  ak;
    acc      = '0;
    acc_n    = '0;
    overflow = 1'b0;
    bi       = 0;
    nleft    = nbytes;
    for (int unsigned i = 0; i < 64; i++)
      bb[i] = '0;
    for (int unsigned i = 0; i < 40; i++)
      bb[i] = raw_b_bytes[8*i +: 8];
    for (int unsigned step = 0; step < 4; step++) begin
      if ((nleft >= 8) && (nport < 4)) begin
        word = '0;
        for (int unsigned k = 0; k < 8; k++) begin
          ix = 6'(bi + k);
          word[8*k +: 8] = bb[ix];
        end
        rx_push_word(nport, word, slot);
        slot  = slot + TLP_AW'(1);
        bi    = bi + 8;
        nleft = nleft - 8;
      end
    end
    if (nleft >= 8) begin
      overflow = 1'b1;
    end else begin
      acc_n = 3'(nleft);
      for (int unsigned k = 0; k < 8; k++)
        ab[3'(k)] = '0;
      for (int unsigned k = 0; k < 7; k++) begin
        if (k < nleft) begin
          ak = 3'(k);
          ix = 6'(bi + k);
          ab[ak] = bb[ix];
        end
      end
      acc = {ab[6], ab[5], ab[4], ab[3], ab[2], ab[1], ab[0]};
    end
  endtask

  // Four RAM words are 8 bytes each. A variable part-select of (i-8) can
  // address past a 64-bit word, so the byte index is narrowed to 3 bits.
  function automatic logic [7:0] play_byte(
      input logic [63:0] w0,
      input logic [63:0] w1,
      input logic [63:0] w2,
      input logic [63:0] w3,
      input int unsigned idx
  );
    logic [7:0] b0 [8];
    logic [7:0] b1 [8];
    logic [7:0] b2 [8];
    logic [7:0] b3 [8];
    logic [2:0] ix;
    for (int unsigned k = 0; k < 8; k++) begin
      b0[3'(k)] = w0[8*3'(k) +: 8];
      b1[3'(k)] = w1[8*3'(k) +: 8];
      b2[3'(k)] = w2[8*3'(k) +: 8];
      b3[3'(k)] = w3[8*3'(k) +: 8];
    end
    if (idx < 8) begin
      ix = 3'(idx);
      return b0[ix];
    end else if (idx < 16) begin
      ix = 3'(idx - 8);
      return b1[ix];
    end else if (idx < 24) begin
      ix = 3'(idx - 16);
      return b2[ix];
    end
    ix = 3'(idx - 24);
    return b3[ix];
  endfunction

  // acc is 7 bytes and cap is 32. Their sum stays inside the 40-byte frame.
  // A byte array keeps the index inside that frame for Vivado.
  function automatic logic [319:0] pack_acc_cap(
      input logic [55:0] acc,
      input logic [2:0]  acc_n,
      input logic [7:0]  cap [0:31],
      input logic [5:0]  cap_n
  );
    logic [7:0]   rb [64];
    logic [5:0]   ix;
    logic [319:0] raw;
    for (int unsigned i = 0; i < 64; i++)
      rb[i] = '0;
    for (int unsigned i = 0; i < 7; i++) begin
      if (3'(i) < acc_n)
        rb[3'(i)] = acc[8*3'(i) +: 8];
    end
    ix = '0;
    for (int unsigned i = 0; i < 32; i++) begin
      if (6'(i) < cap_n) begin
        ix = {3'b0, acc_n} + 6'(i);
        rb[ix] = cap[5'(i)];
      end
    end
    raw = '0;
    for (int unsigned i = 0; i < 40; i++)
      raw[8*i +: 8] = rb[i];
    return raw;
  endfunction

  // Bytes at addr are readable when capture wrote them on an earlier cycle.
  // An open frame only releases a full playback beat. A closed frame also
  // releases its short tail.
  function automatic logic live_words_ready(
      input logic [TLP_AW-1:0] addr,
      input logic [TLP_AW-1:0] wr,
      input logic [TLP_AW-1:0] base,
      input logic              closed,
      input logic [12:0]       len
  );
    logic [TLP_AW-1:0] have;
    logic [12:0]       at_b, left, need;
    have = wr - addr;
    if (!closed) begin
      live_words_ready = (have >= TLP_AW'(RX_PLAY_W));
    end else begin
      at_b = 13'(addr - base) * 13'd8;
      if (at_b >= len) begin
        live_words_ready = 1'b0;
      end else begin
        left = len - at_b;
        need = (left + 13'd7) >> 3;
        live_words_ready = (13'(have) >= need);
      end
    end
  endfunction

  // Synchronous read-data reset so Versal does not see an async BRAM reset.
  always_ff @(posedge pclk_i) begin
    if (!rst_ni) begin
      tlp_ram_rd_q    <= '0;
      tlp_ram_rd_hi_q <= '0;
      tlp_ram_rd_c_q  <= '0;
      tlp_ram_rd_d_q  <= '0;
    end else if (tlp_rd_issue && live_q) begin
      logic [TLP_AW-1:0] have;
      have = tlp_wr_slot_q - rd_addr_q;
      tlp_ram_rd_q <= tlp_ram[rd_addr_q];
      tlp_ram_rd_hi_q <= (have > TLP_AW'(1)) ? tlp_ram[rd_addr_q + TLP_AW'(1)] : '0;
      tlp_ram_rd_c_q  <= (have > TLP_AW'(2)) ? tlp_ram[rd_addr_q + TLP_AW'(2)] : '0;
      tlp_ram_rd_d_q  <= (have > TLP_AW'(3)) ? tlp_ram[rd_addr_q + TLP_AW'(3)] : '0;
    end else if (tlp_rd_issue) begin
      tlp_ram_rd_q <= tlp_ram[rd_addr_q];
      if (RX_PLAY_W >= 2)
        tlp_ram_rd_hi_q <= tlp_ram[rd_addr_q + TLP_AW'(1)];
      if (RX_PLAY_W >= 4) begin
        tlp_ram_rd_c_q <= tlp_ram[rd_addr_q + TLP_AW'(2)];
        tlp_ram_rd_d_q <= tlp_ram[rd_addr_q + TLP_AW'(3)];
      end
    end
  end

  always_comb begin
    logic [12:0] live_rem_b;
    logic [5:0]  live_n;
    logic        live_fin;
    live_rem_b = '0;
    live_n     = '0;
    live_fin   = 1'b0;
    rx_pkt_d         = rx_pkt_q;
    rx_body_d        = rx_body_q;
    rx_cnt_d         = rx_cnt_q;
    rx_err_pkt_d     = rx_err_pkt_q;
    dll_beat_valid_d = dll_beat_valid_q;
    dll_beat_d       = dll_beat_q;
    tlp_acc_d        = tlp_acc_q;
    tlp_acc_cnt_d    = tlp_acc_cnt_q;
    tlp_wr_slot_d    = tlp_wr_slot_q;
    tlp_base_d       = tlp_base_q;
    tlp_len_d        = tlp_len_q;
    tlp_tail_pend_d  = 1'b0;
    tlp_err_d        = tlp_err_q;
    frame_push_d     = 1'b0;
    frame_push_base_d = tlp_wr_slot_q;
    frame_push_len_d = tlp_len_q;
    frame_push_err_d = 1'b0;
    rd_ph_d          = rd_ph_q;
    rd_rem_d         = rd_rem_q;
    rd_sop_d         = rd_sop_q;
    rd_err_d         = rd_err_q;
    rd_addr_d        = rd_addr_q;
    rd_pop           = 1'b0;
    rd_words         = 3'd0;
    rd_drop          = '0;
    tlp_rd_issue     = 1'b0;
    live_d        = live_q;
    live_closed_d = live_closed_q;
    live_len_d    = live_len_q;
    live_sent_d   = live_sent_q;
    live_base_d   = live_base_q;
    dllp_park_d      = dllp_park_q;
    dllp_park_data_d = dllp_park_data_q;
    dllp_park_err_d  = dllp_park_err_q;
    dllp_park_ld     = 1'b0;

    tlp_ram_we       = 1'b0;
    tlp_ram_waddr    = tlp_wr_slot_q;
    tlp_ram_wdata    = '0;
    tlp_ram_we2      = 1'b0;
    tlp_ram_waddr2   = tlp_wr_slot_q;
    tlp_ram_wdata2   = '0;
    tlp_ram_we3      = 1'b0;
    tlp_ram_waddr3   = tlp_wr_slot_q;
    tlp_ram_wdata3   = '0;
    tlp_ram_we4      = 1'b0;
    tlp_ram_waddr4   = tlp_wr_slot_q;
    tlp_ram_wdata4   = '0;

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

    if (p0_lanes_ok_q || (rx_pkt_q == RX_HOLD)) begin
      unique case (rx_pkt_q)
        RX_IDLE: begin
          if (p0_lanes_ok_q) begin
            automatic logic        saw_sdp = 1'b0;
            automatic logic        saw_stp = 1'b0;
            automatic logic [3:0]  c       = 4'd0;
            automatic logic [63:0] b       = '0;
            automatic logic [5:0]  cap_n   = 6'd0;
            automatic logic [7:0]  cap_b [0:31];
            automatic logic        err       = 1'b0;
            automatic logic        done      = 1'b0;
            automatic logic        nullified = 1'b0;

            for (int unsigned i = 0; i < 32; i++) cap_b[i] = '0;

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
                  end else if (cap_n < 6'd32) begin
                    cap_b[cap_n] = p0_data_q[p];
                    cap_n = cap_n + 6'd1;
                  end
                end
              end
            end

            if (saw_sdp) begin
              rx_body_d    = b;
              rx_cnt_d     = c;
              rx_err_pkt_d = err;
              if (done) begin
                // Slot free and nothing parked: emit now. Otherwise park and
                // stay in IDLE so a TLP that follows is still framed.
                if ((!dll_beat_valid_q || dll_rx_ready_i) && !dllp_park_q) begin
                  dll_beat_d.data     = b;
                  dll_beat_d.keep     = 8'hFF;
                  dll_beat_d.sop      = 1'b1;
                  dll_beat_d.eop      = 1'b1;
                  dll_beat_d.err      = err | nullified;
                  dll_beat_d.pkt_type = RIVET_MAC_PKT_DLLP;
                  dll_beat_valid_d    = 1'b1;
                end else begin
                  dllp_park_d      = 1'b1;
                  dllp_park_data_d = b;
                  dllp_park_err_d  = err | nullified;
                  dllp_park_ld     = 1'b1;
                end
                rx_pkt_d = RX_IDLE;
                rx_cnt_d = 4'd0;
              end else begin
                rx_pkt_d = RX_BODY;
              end
            end else if (saw_stp) begin
              // A tail write still owns port 0. Full words go to the RAM.
              // Fewer than eight bytes stay in the accumulator.
              automatic logic [TLP_AW-1:0] slot;
              automatic logic [TLP_AW-1:0] base;
              automatic logic [319:0]      raw_b;
              automatic logic [55:0]       acc;
              automatic logic [2:0]        acc_n;
              automatic int unsigned       nport;
              automatic logic              overflow;
              nport  = tlp_tail_pend_q ? 1 : 0;
              base   = tlp_tail_pend_q ? (tlp_wr_slot_q + TLP_AW'(1)) : tlp_wr_slot_q;
              slot   = base;
              raw_b = '0;
              for (int unsigned i = 0; i < 32; i++)
                if (6'(i) < cap_n)
                  raw_b[8*i +: 8] = cap_b[i];
              rx_store(raw_b, int'(cap_n), slot, acc, acc_n, nport, overflow);
              tlp_base_d    = base;
              tlp_wr_slot_d = slot;
              tlp_len_d     = 13'(cap_n);
              tlp_err_d     = err | nullified | overflow |
                              (done && (cap_n == 6'd0)) | (used_q > 13'd3600);
              if (done) begin
                if (!tlp_err_d && (acc_n != 3'd0)) begin
                  tlp_acc_d       = acc;
                  tlp_acc_cnt_d   = acc_n;
                  tlp_tail_pend_d = 1'b1;
                end else begin
                  tlp_acc_d     = '0;
                  tlp_acc_cnt_d = 3'd0;
                end
                frame_push_d      = 1'b1;
                frame_push_base_d = base;
                frame_push_len_d  = 13'(cap_n);
                frame_push_err_d  = tlp_err_d;
                rx_pkt_d          = RX_IDLE;
              end else begin
                tlp_acc_d     = acc;
                tlp_acc_cnt_d = acc_n;
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
              if ((!dll_beat_valid_q || dll_rx_ready_i) && !dllp_park_q) begin
                dll_beat_d.data     = b;
                dll_beat_d.keep     = 8'hFF;
                dll_beat_d.sop      = 1'b1;
                dll_beat_d.eop      = 1'b1;
                dll_beat_d.err      = err | nullified;
                dll_beat_d.pkt_type = RIVET_MAC_PKT_DLLP;
                dll_beat_valid_d    = 1'b1;
              end else begin
                dllp_park_d      = 1'b1;
                dllp_park_data_d = b;
                dllp_park_err_d  = err | nullified;
                dllp_park_ld     = 1'b1;
              end
              rx_pkt_d = RX_IDLE;
              rx_cnt_d = 4'd0;
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
            automatic logic [7:0]   cap_b [0:31];
            automatic logic [5:0]   cap_n     = 6'd0;
            automatic logic [319:0] raw_b;
            automatic logic [13:0]  new_len;
            automatic logic         len_ovf;
            automatic logic         err       = tlp_err_q;
            automatic logic         done      = 1'b0;
            automatic logic         nullified = 1'b0;

            for (int unsigned i = 0; i < 32; i++) cap_b[i] = '0;

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
                end else if (cap_n < 6'd32) begin
                  cap_b[cap_n] = p0_data_q[p];
                  cap_n = cap_n + 6'd1;
                end
              end
            end

            new_len = {1'b0, tlp_len_q} + 14'(cap_n);
            len_ovf = (new_len > 14'(TLP_FRAME_MAX)) || (used_q > 13'd3600);
            if (len_ovf) begin
              err  = 1'b1;
              done = 1'b1;
            end

            raw_b = pack_acc_cap(tlp_acc_q, tlp_acc_cnt_q, cap_b, cap_n);

            tlp_len_d = len_ovf ? 13'(TLP_FRAME_MAX) : new_len[12:0];
            tlp_err_d = err | nullified | (done && (new_len == 14'd0));

            begin
              automatic logic [TLP_AW-1:0] slot;
              automatic logic [55:0]       acc;
              automatic logic [2:0]        acc_n;
              automatic int unsigned       nport;
              automatic logic              overflow;
              automatic int unsigned       nbytes;
              nport  = 0;
              slot   = tlp_wr_slot_q;
              nbytes = int'(tlp_acc_cnt_q) + int'(cap_n);
              rx_store(raw_b, nbytes, slot, acc, acc_n, nport, overflow);
              tlp_wr_slot_d = slot;
              if (overflow)
                tlp_err_d = 1'b1;
              if (done) begin
                if (!tlp_err_d && (acc_n != 3'd0)) begin
                  tlp_acc_d       = acc;
                  tlp_acc_cnt_d   = acc_n;
                  tlp_tail_pend_d = 1'b1;
                end else begin
                  tlp_acc_d     = '0;
                  tlp_acc_cnt_d = 3'd0;
                end
                // A frame already in live playback just needs its final
                // length. Pushing it again would play the bytes twice.
                if (RX_CUT && live_q && !live_closed_q) begin
                  live_closed_d = 1'b1;
                  live_len_d    = tlp_len_d;
                  if (tlp_err_d)
                    rd_err_d = 1'b1;
                end else begin
                  frame_push_d      = 1'b1;
                  frame_push_base_d = tlp_base_q;
                  frame_push_len_d  = tlp_len_d;
                  frame_push_err_d  = tlp_err_d;
                end
                rx_pkt_d          = RX_IDLE;
              end else begin
                tlp_acc_d     = acc;
                tlp_acc_cnt_d = acc_n;
                rx_pkt_d      = RX_TLP;
              end
            end
          end
        end

        RX_TLP_OUT: rx_pkt_d = RX_IDLE;

        default: rx_pkt_d = RX_IDLE;
      endcase
    end

    // Parked DLLP goes out ahead of TLP playback. Capture already ran above.
    if (dllp_park_q && !dll_beat_valid_d) begin
      dll_beat_d            = '0;
      dll_beat_d.data       = dllp_park_data_q;
      dll_beat_d.keep       = 8'hFF;
      dll_beat_d.sop        = 1'b1;
      dll_beat_d.eop        = 1'b1;
      dll_beat_d.err        = dllp_park_err_q;
      dll_beat_d.pkt_type   = RIVET_MAC_PKT_DLLP;
      dll_beat_valid_d      = 1'b1;
      if (!dllp_park_ld)
        dllp_park_d = 1'b0;
    end

    // Playback is independent of capture so the next frame can land while
    // the previous one is still moving toward the DLL.
    if (rd_ph_q == 2'd0) begin
      if (q_count_q != 5'd0) begin
        rd_addr_d    = q_base[q_rptr_q[3:0]];
        rd_rem_d     = q_len[q_rptr_q[3:0]];
        rd_err_d     = q_err[q_rptr_q[3:0]];
        rd_sop_d     = 1'b1;
        rd_ph_d      = 2'd1;
        rd_pop       = 1'b1;
      end
    end else if (rd_ph_q == 2'd1) begin
      if (rd_err_q) begin
        if (!dll_beat_valid_d) begin
          dll_beat_d            = '0;
          dll_beat_d.pkt_type   = RIVET_MAC_PKT_TLP;
          dll_beat_d.sop        = 1'b1;
          dll_beat_d.eop        = 1'b1;
          dll_beat_d.err        = 1'b1;
          dll_beat_d.keep       = 8'hFF;
          dll_beat_valid_d      = 1'b1;
          rd_ph_d               = 2'd0;
          rd_drop               = 12'((rd_rem_q + 13'd7) >> 3);
        end
      end else if (live_q && !live_words_ready(rd_addr_q, tlp_wr_slot_q,
                                              live_base_q, live_closed_q,
                                              live_len_q)) begin
        if (live_closed_q && (live_sent_q >= live_len_q)) begin
          live_d        = 1'b0;
          live_closed_d = 1'b0;
          live_sent_d   = '0;
          rd_ph_d       = 2'd0;
        end else begin
          rd_ph_d = 2'd1;
        end
      end else begin
        tlp_rd_issue = 1'b1;
        rd_addr_d    = rd_addr_q + 11'(RX_PLAY_W);
        rd_ph_d      = 2'd2;
      end
    end else if (live_q && !dll_beat_valid_d) begin
      if (rd_err_q) begin
        dll_beat_d            = '0;
        dll_beat_d.pkt_type   = RIVET_MAC_PKT_TLP;
        dll_beat_d.sop        = 1'b1;
        dll_beat_d.eop        = 1'b1;
        dll_beat_d.err        = 1'b1;
        dll_beat_d.keep       = 8'hFF;
        dll_beat_valid_d      = 1'b1;
        live_d                = 1'b0;
        live_closed_d         = 1'b0;
        live_sent_d           = '0;
        rd_ph_d               = 2'd0;
      end else begin
        live_rem_b = 13'(RX_PLAY_B);
        if (live_closed_q)
          live_rem_b = (live_len_q > live_sent_q) ? (live_len_q - live_sent_q) : 13'd0;
        if (live_rem_b != 13'd0) begin
          live_n = (live_rem_b >= 13'(RX_PLAY_B)) ? 6'(RX_PLAY_B) : live_rem_b[5:0];
          live_fin = live_closed_q && (live_rem_b <= 13'(live_n));
          dll_beat_d          = '0;
          dll_beat_d.pkt_type = RIVET_MAC_PKT_TLP;
          dll_beat_d.sop      = rd_sop_q;
          for (int unsigned i = 0; i < 32; i++) begin
            if (6'(i) < live_n) begin
              dll_beat_d.data[8*5'(i) +: 8] = play_byte(
                  tlp_ram_rd_q, tlp_ram_rd_hi_q, tlp_ram_rd_c_q, tlp_ram_rd_d_q, i);
              dll_beat_d.keep[i] = 1'b1;
            end
          end
          dll_beat_d.eop   = live_fin;
          dll_beat_d.err   = 1'b0;
          dll_beat_valid_d = 1'b1;
          rd_sop_d         = 1'b0;
          live_sent_d      = live_sent_q + 13'(live_n);
          rd_words         = 3'd1;
          if (live_n > 6'd8)
            rd_words = 3'd2;
          if (live_n > 6'd16)
            rd_words = 3'd3;
          if (live_n > 6'd24)
            rd_words = 3'd4;
          if (live_fin) begin
            live_d        = 1'b0;
            live_closed_d = 1'b0;
            live_sent_d   = '0;
            rd_ph_d       = 2'd0;
            rd_rem_d      = 13'd0;
          end else if (!live_words_ready(rd_addr_q, tlp_wr_slot_q, live_base_q,
                                         live_closed_d, live_len_d)) begin
            rd_ph_d = 2'd1;
          end else begin
            rd_addr_d    = rd_addr_q + 11'(rd_words);
            tlp_rd_issue = 1'b1;
            rd_ph_d      = 2'd2;
          end
        end else begin
          live_d        = 1'b0;
          live_closed_d = 1'b0;
          rd_ph_d       = 2'd0;
        end
      end
    end else if (!dll_beat_valid_d) begin
      if (rd_rem_q != 13'd0) begin
        automatic logic [5:0] n;
        automatic logic [5:0] nmax;
        nmax = 6'(RX_PLAY_B);
        n = (rd_rem_q >= 13'(nmax)) ? nmax : rd_rem_q[5:0];
        dll_beat_d          = '0;
        dll_beat_d.pkt_type = RIVET_MAC_PKT_TLP;
        dll_beat_d.sop      = rd_sop_q;
        for (int unsigned i = 0; i < 32; i++) begin
          if (6'(i) < n) begin
            dll_beat_d.data[8*5'(i) +: 8] = play_byte(
                tlp_ram_rd_q, tlp_ram_rd_hi_q, tlp_ram_rd_c_q, tlp_ram_rd_d_q, i);
            dll_beat_d.keep[i] = 1'b1;
          end
        end
        dll_beat_d.eop   = (rd_rem_q <= 13'(n));
        dll_beat_d.err   = 1'b0;
        dll_beat_valid_d = 1'b1;
        rd_sop_d         = 1'b0;
        rd_words         = 3'd1;
        if (n > 6'd8)
          rd_words = 3'd2;
        if (n > 6'd16)
          rd_words = 3'd3;
        if (n > 6'd24)
          rd_words = 3'd4;
        if (rd_rem_q <= 13'(n)) begin
          rd_rem_d = 13'd0;
          rd_ph_d  = 2'd0;
        end else begin
          rd_rem_d     = rd_rem_q - 13'(n);
          rd_addr_d    = rd_addr_q + 11'(rd_words);
          tlp_rd_issue = 1'b1;
        end
      end else begin
        rd_ph_d = 2'd0;
      end
    end

    // Start cut-through only while capture is still open. The end-of-packet
    // cycle pushes the frame instead, so a short TLP is unchanged.
    if (RX_CUT && !live_d && (rd_ph_q == 2'd0) && (rd_ph_d == 2'd0) &&
        (q_count_q == 5'd0) && (rx_pkt_q == RX_TLP) && (rx_pkt_d == RX_TLP) &&
        !tlp_err_q &&
        ((tlp_wr_slot_q - tlp_base_q) >= TLP_AW'(RX_PLAY_W))) begin
      live_d        = 1'b1;
      live_closed_d = 1'b0;
      live_len_d    = '0;
      live_sent_d   = '0;
      live_base_d   = tlp_base_q;
      rd_addr_d     = tlp_base_q;
      rd_sop_d      = 1'b1;
      rd_err_d      = 1'b0;
      rd_ph_d       = 2'd1;
      rd_rem_d      = 13'd1;
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
      tlp_base_q       <= '0;
      tlp_len_q        <= '0;
      tlp_tail_pend_q  <= 1'b0;
      tlp_err_q        <= 1'b0;
      q_wptr_q         <= '0;
      q_rptr_q         <= '0;
      q_count_q        <= '0;
      rd_ph_q          <= '0;
      rd_rem_q         <= '0;
      rd_sop_q         <= 1'b0;
      rd_err_q         <= 1'b0;
      rd_addr_q        <= '0;
      used_q           <= '0;
      live_q           <= 1'b0;
      live_closed_q    <= 1'b0;
      live_len_q       <= '0;
      live_sent_q      <= '0;
      live_base_q      <= '0;
      dllp_park_q      <= 1'b0;
      dllp_park_data_q <= '0;
      dllp_park_err_q  <= 1'b0;
    end else begin
      logic [12:0] used_next;
      rx_pkt_q         <= rx_pkt_d;
      rx_body_q        <= rx_body_d;
      rx_cnt_q         <= rx_cnt_d;
      rx_err_pkt_q     <= rx_err_pkt_d;
      dll_beat_valid_q <= dll_beat_valid_d;
      dll_beat_q       <= dll_beat_d;
      tlp_acc_q        <= tlp_acc_d;
      tlp_acc_cnt_q    <= tlp_acc_cnt_d;
      tlp_wr_slot_q    <= tlp_wr_slot_d;
      tlp_base_q       <= tlp_base_d;
      tlp_len_q        <= tlp_len_d;
      tlp_tail_pend_q  <= tlp_tail_pend_d;
      tlp_err_q        <= tlp_err_d;
      rd_ph_q          <= rd_ph_d;
      rd_rem_q         <= rd_rem_d;
      rd_sop_q         <= rd_sop_d;
      rd_err_q         <= rd_err_d;
      rd_addr_q        <= rd_addr_d;
      live_q           <= live_d;
      live_closed_q    <= live_closed_d;
      live_len_q       <= live_len_d;
      live_sent_q      <= live_sent_d;
      live_base_q      <= live_base_d;
      dllp_park_q      <= dllp_park_d;
      dllp_park_data_q <= dllp_park_data_d;
      dllp_park_err_q  <= dllp_park_err_d;
      if (frame_push_d && (q_count_q < 5'(TLP_Q))) begin
        q_base[q_wptr_q[3:0]] <= frame_push_base_d;
        q_len[q_wptr_q[3:0]]  <= frame_push_len_d;
        q_err[q_wptr_q[3:0]]  <= frame_push_err_d;
        q_wptr_q              <= q_wptr_q + 5'd1;
      end
      if (rd_pop && (q_count_q != 5'd0))
        q_rptr_q <= q_rptr_q + 5'd1;
      case ({frame_push_d && (q_count_q < 5'(TLP_Q)), rd_pop && (q_count_q != 5'd0)})
        2'b10:   q_count_q <= q_count_q + 5'd1;
        2'b01:   q_count_q <= q_count_q - 5'd1;
        default: q_count_q <= q_count_q;
      endcase
      used_next = used_q;
      if (tlp_ram_we)
        used_next = used_next + 12'd1;
      if (tlp_ram_we2)
        used_next = used_next + 12'd1;
      if (tlp_ram_we3)
        used_next = used_next + 12'd1;
      if (tlp_ram_we4)
        used_next = used_next + 12'd1;
      if (rd_words != 3'd0) begin
        if (13'(rd_words) >= used_next)
          used_next = 13'd0;
        else
          used_next = used_next - 13'(rd_words);
      end
      if (rd_drop != 12'd0) begin
        if (rd_drop >= used_next)
          used_next = 12'd0;
        else
          used_next = used_next - rd_drop;
      end
      used_q <= used_next;
    end
  end

  assign dll_rx_beat_o  = dll_beat_q;
  assign dll_rx_valid_o = dll_beat_valid_q;

endmodule : rivet_mac_os_rx
