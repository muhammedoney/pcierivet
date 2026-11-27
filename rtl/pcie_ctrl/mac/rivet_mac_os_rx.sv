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
  // Local copies of rate and lane enable. The TS counters above read
  // lane_en_rx_q, so the registers are declared here. They still update
  // with Stage IN and break the u_ltssm path into that stage.
  (* equivalent_register_removal = "no" *) logic             gf_gen3_rx_q;
  (* equivalent_register_removal = "no" *) logic [LANES-1:0] lane_en_rx_q;

  assign ts_all_lanes = ((hit_any_ts | ~lane_en_rx_q) == {LANES{1'b1}}) && (lane_en_rx_q != '0);

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
          if (lane_en_rx_q[l]) begin
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
      if (lane_en_rx_q[l]) begin
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

    if (lane_en_rx_q == '0) begin
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
        if (lane_en_rx_q[l] && (lane_num_q[l] != lane_num_ref_q[l])) rx_lane_num_changed_o = 1'b1;
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
      if (lane_en_rx_q[l]) begin
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

  // Stage P0: registered dense (hole-free) per-symbol token flags
  logic             p0_lanes_ok_q;
  logic [5:0]       p0_cnt_q;
  logic [NSYM-1:0]  p0_sdp_q;
  logic [NSYM-1:0]  p0_stp_q;
  logic [NSYM-1:0]  p0_end_q;
  logic [NSYM-1:0]  p0_edb_q;
  logic [NSYM-1:0]  p0_k_q;
  logic [NSYM-1:0]  p0_nz_q;
  logic [7:0]       p0_data_q [0:NSYM-1];
  // Stage P0a: pre-decoded first start token (SDP/STP) & after-start mask so
  // RX_IDLE does not chain prio32(start_m) into prio32(tail_m) / 32:1 muxes.
  logic             p0a_lanes_ok_q;
  logic [5:0]       p0a_cnt_q;
  logic [NSYM-1:0]  p0a_end_q;
  logic [NSYM-1:0]  p0a_edb_q;
  logic [NSYM-1:0]  p0a_k_q;
  logic [NSYM-1:0]  p0a_nz_q;
  logic [7:0]       p0a_data_q [0:NSYM-1];
  logic             p0a_saw_sdp_q;
  logic             p0a_saw_stp_q;
  logic [4:0]       p0a_start_idx_q;
  logic [5:0]       p0a_base_q;
  logic [31:0]      p0a_after_start_q;
  // Gen3 TLP: STP, then a 2-byte length, then that many DLL bytes. The length
  // is stripped here and the following idle byte is presented as END so the
  // Gen2 gearbox can run. Gen3 DLLP: SDP, then 6 payload bytes, then END.
  // Payload and CRC bytes may equal FB, 5C, FD, or FE, so both framing bodies
  // mask token detection until their byte counts expire.
  logic [2:0]       gf_st_q;
  logic [15:0]      gf_left_q;
  logic             gf_left_hi_z_q;

  // Raw token detect is per symbol. All SYMS symbols on a lane share one
  // enable bit, so lane-periodic compaction packs enabled symbols into
  // dense slots 0..gf_raw_cnt-1, registers Stage IN (in_*_q), runs Stage G0
  // (framing state + metadata -> g0_*_q), then Stage G1 (filter + 5:1 compact
  // -> p0_*_q) so every stage fits cleanly inside 4 ns at 250 MHz.
  logic              gf_gen3_c;
  logic              gf_ok_c;
  logic [5:0]        gf_raw_cnt_c;
  logic [NSYM-1:0]   gf_sdp_c, gf_stp_c, gf_end_c, gf_edb_c, gf_k_c;
  logic [8*NSYM-1:0] gf_data_pack;

  // Stage IN registers (dense raw stream + pre-decoded high-byte-zero hints).
  // gf_gen3_rx_q and lane_en_rx_q are declared with the TS counters.
  logic              in_gen3_q;
  logic              in_ok_q;
  logic [5:0]        in_cnt_q;
  logic [NSYM-1:0]   in_sdp_q, in_stp_q, in_end_q, in_edb_q, in_k_q;
  logic [8*NSYM-1:0] in_data_q;
  logic [31:0]       in_tok_q;
  logic [31:0]       in_l_hi_z_q;
  logic [31:0]       in_l_hi6_z_q;
  logic [31:0]       in_l_hi6_1_q;

  // Stage G0 combinational outputs from rivet_mac_gf_scan_meta.
  logic [2:0]        gf_st_f;
  logic [15:0]       gf_left_f;
  logic              gf_left_hi_z_f;
  logic              g0_open_fin_c;
  logic [5:0]        g0_h0_c;
  logic              g0_end_pos0_v_c, g0_dllp_end0_v_c;
  logic [5:0]        g0_end_pos0_c, g0_dllp_end0_c;
  logic [1:0]        g0_s1_drops_c;
  logic              g0_found_c;
  logic [4:0]        g0_s_idx_c;
  logic              g0_end_pos1_v_c, g0_dllp_end1_v_c;
  logic [5:0]        g0_end_pos1_c, g0_dllp_end1_c;
  logic [1:0]        g0_s2_drops_c;

  // Stage G0 pipeline registers feeding Stage G1 compaction.
  logic              g0_gen3_q;
  logic              g0_ok_q;
  logic [5:0]        g0_cnt_q;
  logic [NSYM-1:0]   g0_sdp_q, g0_stp_q, g0_end_q, g0_edb_q, g0_k_q;
  logic [8*NSYM-1:0] g0_data_q;
  logic              g0_open_fin_q;
  logic [5:0]        g0_h0_q;
  logic              g0_end_pos0_v_q, g0_dllp_end0_v_q;
  logic [5:0]        g0_end_pos0_q, g0_dllp_end0_q;
  logic [1:0]        g0_s1_drops_q;
  logic              g0_found_q;
  logic [4:0]        g0_s_idx_q;
  logic              g0_end_pos1_v_q, g0_dllp_end1_v_q;
  logic [5:0]        g0_end_pos1_q, g0_dllp_end1_q;
  logic [1:0]        g0_s2_drops_q;

  // Stage G1 combinational outputs from rivet_mac_gf_compact -> p0_*_q.
  logic [5:0]        gf_cnt_f;
  logic [NSYM-1:0]   gf_sdp_f, gf_stp_f, gf_end_f, gf_edb_f, gf_k_f;
  logic [8*NSYM-1:0] gf_data_f;

  // Balanced 32-bit priority encoder (lowest set bit).
  function automatic logic [5:0] prio32(input logic [31:0] m);
    logic [7:0]  g_v;
    logic [1:0]  g_i [8];
    logic [1:0]  h_v;
    logic [3:0]  h_i [2];
    logic        v;
    logic [4:0]  idx;
    for (int unsigned g = 0; g < 8; g++) begin
      g_v[g] = |m[4*g +: 4];
      if      (m[4*g + 0]) g_i[g] = 2'd0;
      else if (m[4*g + 1]) g_i[g] = 2'd1;
      else if (m[4*g + 2]) g_i[g] = 2'd2;
      else                 g_i[g] = 2'd3;
    end
    for (int unsigned h = 0; h < 2; h++) begin
      h_v[h] = |g_v[4*h +: 4];
      if      (g_v[4*h + 0]) h_i[h] = {2'd0, g_i[4*h + 0]};
      else if (g_v[4*h + 1]) h_i[h] = {2'd1, g_i[4*h + 1]};
      else if (g_v[4*h + 2]) h_i[h] = {2'd2, g_i[4*h + 2]};
      else                   h_i[h] = {2'd3, g_i[4*h + 3]};
    end
    v   = h_v[0] || h_v[1];
    idx = h_v[0] ? {1'b0, h_i[0]} : {1'b1, h_i[1]};
    return {v, idx};
  endfunction

  always_comb begin
    logic [LANES-1:0] lane_e;
    logic [2:0]       lane_k;
    logic [1:0]       act_l [4];
    logic [5:0]       lane_cnt_c;
    logic [NSYM-1:0]  raw_sdp, raw_stp, raw_end, raw_edb, raw_k;
    logic [7:0]       raw_data [0:NSYM-1];

    gf_gen3_c = gf_gen3_rx_q;
    gf_ok_c   = (PKT_RX_OK || gf_gen3_c) && sym_valid_i[0] && lane_en_rx_q[0];

    // Keep gf_ok_c (sym_valid_i[0]) out of lane_e/lane_k/gf_data_pack so the
    // descrambler valid bit does not feed the crossbar or in_l_hi6_1_q.
    lane_k = 3'd0;
    for (int unsigned i = 0; i < 4; i++) act_l[i] = 2'd0;
    for (int unsigned l = 0; l < LANES; l++) begin
      lane_e[l] = lane_en_rx_q[l] && !(gf_gen3_c && os_block_i[l]);
      if (lane_e[l]) begin
        act_l[lane_k[1:0]] = 2'(l);
        lane_k             = lane_k + 3'd1;
      end
    end

    raw_sdp = '0;
    raw_stp = '0;
    raw_end = '0;
    raw_edb = '0;
    raw_k   = '0;
    for (int unsigned p = 0; p < NSYM; p++) raw_data[p] = '0;
    for (int unsigned s = 0; s < SYMS; s++) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        automatic int unsigned p = s * LANES + l;
        automatic logic [7:0] b = sym_data_i[PIPE_DATA_WIDTH*l + 8*s +: 8];
        automatic logic k = (s < 2) ? sym_datak_i[2*l + s] : 1'b0;
        automatic logic tok = k || (gf_gen3_c && !os_block_i[l]);
        automatic logic e = lane_e[l];
        raw_sdp[p]  = e && tok && (b == RIVET_SYM_SDP);
        raw_stp[p]  = e && tok && (b == RIVET_SYM_STP);
        raw_end[p]  = e && tok && (b == RIVET_SYM_END);
        raw_edb[p]  = e && tok && (b == RIVET_SYM_EDB);
        raw_k[p]    = e && k;
        raw_data[p] = b;
      end
    end

    lane_cnt_c   = 6'(SYMS) * {3'd0, lane_k};
    gf_raw_cnt_c = gf_ok_c ? lane_cnt_c : 6'd0;
    gf_sdp_c     = '0;
    gf_stp_c     = '0;
    gf_end_c     = '0;
    gf_edb_c     = '0;
    gf_k_c       = '0;
    gf_data_pack = '0;
    for (int unsigned d = 0; d < NSYM; d++) begin
      if (6'(d) < lane_cnt_c) begin
        automatic int unsigned src_p;
        case (lane_k)
          3'd1:    src_p = d * LANES + int'(act_l[0]);
          3'd2:    src_p = (d >> 1) * LANES + int'(act_l[d[0]]);
          3'd3:    src_p = (d / 3) * LANES + int'(act_l[d % 3]);
          default: src_p = d;
        endcase
        if (src_p < NSYM) begin
          gf_sdp_c[d]            = gf_ok_c && raw_sdp[src_p];
          gf_stp_c[d]            = gf_ok_c && raw_stp[src_p];
          gf_end_c[d]            = gf_ok_c && raw_end[src_p];
          gf_edb_c[d]            = gf_ok_c && raw_edb[src_p];
          gf_k_c[d]              = gf_ok_c && raw_k[src_p];
          gf_data_pack[8*d +: 8] = raw_data[src_p];
        end
      end
    end
  end

  generate
    if (PIPE_DATA_WIDTH >= 32) begin : g_gf_scan
      rivet_mac_gf_scan_meta #(
        .NSYM      (NSYM),
        .DLLP_BYTES(RIVET_DLLP_WIRE_BYTES)
      ) u_gf_meta (
        .st_i         (gf_st_q),
        .left_i       (gf_left_q),
        .left_hi_z_i  (gf_left_hi_z_q),
        .cnt_i        (in_cnt_q),
        .stp_i        (in_stp_q),
        .tok_i        (in_tok_q),
        .data_i       (in_data_q),
        .l_hi_z_i     (in_l_hi_z_q),
        .l_hi6_z_i    (in_l_hi6_z_q),
        .l_hi6_1_i    (in_l_hi6_1_q),
        .st_o         (gf_st_f),
        .left_o       (gf_left_f),
        .left_hi_z_o  (gf_left_hi_z_f),
        .open_fin_o   (g0_open_fin_c),
        .h0_o         (g0_h0_c),
        .end_pos0_v_o (g0_end_pos0_v_c),
        .end_pos0_o   (g0_end_pos0_c),
        .dllp_end0_v_o(g0_dllp_end0_v_c),
        .dllp_end0_o  (g0_dllp_end0_c),
        .s1_drops_o   (g0_s1_drops_c),
        .found_o      (g0_found_c),
        .s_idx_o      (g0_s_idx_c),
        .end_pos1_v_o (g0_end_pos1_v_c),
        .end_pos1_o   (g0_end_pos1_c),
        .dllp_end1_v_o(g0_dllp_end1_v_c),
        .dllp_end1_o  (g0_dllp_end1_c),
        .s2_drops_o   (g0_s2_drops_c)
      );

      rivet_mac_gf_compact #(
        .NSYM(NSYM)
      ) u_gf_compact (
        .cnt_i        (g0_cnt_q),
        .sdp_i        (g0_sdp_q),
        .stp_i        (g0_stp_q),
        .end_i        (g0_end_q),
        .edb_i        (g0_edb_q),
        .k_i          (g0_k_q),
        .data_i       (g0_data_q),
        .open_fin_i   (g0_open_fin_q),
        .h0_i         (g0_h0_q),
        .end_pos0_v_i (g0_end_pos0_v_q),
        .end_pos0_i   (g0_end_pos0_q),
        .dllp_end0_v_i(g0_dllp_end0_v_q),
        .dllp_end0_i  (g0_dllp_end0_q),
        .s1_drops_i   (g0_s1_drops_q),
        .found_i      (g0_found_q),
        .s_idx_i      (g0_s_idx_q),
        .end_pos1_v_i (g0_end_pos1_v_q),
        .end_pos1_i   (g0_end_pos1_q),
        .dllp_end1_v_i(g0_dllp_end1_v_q),
        .dllp_end1_i  (g0_dllp_end1_q),
        .s2_drops_i   (g0_s2_drops_q),
        .cnt_o        (gf_cnt_f),
        .sdp_o        (gf_sdp_f),
        .stp_o        (gf_stp_f),
        .end_o        (gf_end_f),
        .edb_o        (gf_edb_f),
        .k_o          (gf_k_f),
        .data_o       (gf_data_f)
      );
    end else begin : g_gf_passthru
      assign gf_st_f          = '0;
      assign gf_left_f        = '0;
      assign gf_left_hi_z_f   = 1'b1;
      assign g0_open_fin_c    = 1'b0;
      assign g0_h0_c          = '0;
      assign g0_end_pos0_v_c  = 1'b0;
      assign g0_end_pos0_c    = '0;
      assign g0_dllp_end0_v_c = 1'b0;
      assign g0_dllp_end0_c   = '0;
      assign g0_s1_drops_c    = '0;
      assign g0_found_c       = 1'b0;
      assign g0_s_idx_c       = '0;
      assign g0_end_pos1_v_c  = 1'b0;
      assign g0_end_pos1_c    = '0;
      assign g0_dllp_end1_v_c = 1'b0;
      assign g0_dllp_end1_c   = '0;
      assign g0_s2_drops_c    = '0;
      assign gf_cnt_f         = g0_cnt_q;
      assign gf_sdp_f         = g0_sdp_q;
      assign gf_stp_f         = g0_stp_q;
      assign gf_end_f         = g0_end_q;
      assign gf_edb_f         = g0_edb_q;
      assign gf_k_f           = g0_k_q;
      assign gf_data_f        = g0_data_q;
    end
  endgenerate

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gf_gen3_rx_q     <= 1'b0;
      lane_en_rx_q     <= '0;
      in_gen3_q        <= 1'b0;
      in_ok_q          <= 1'b0;
      in_cnt_q         <= '0;
      in_sdp_q         <= '0;
      in_stp_q         <= '0;
      in_end_q         <= '0;
      in_edb_q         <= '0;
      in_k_q           <= '0;
      in_data_q        <= '0;
      in_tok_q         <= '0;
      in_l_hi_z_q      <= '0;
      in_l_hi6_z_q     <= '0;
      in_l_hi6_1_q     <= '0;
      gf_st_q          <= '0;
      gf_left_q        <= '0;
      gf_left_hi_z_q   <= 1'b1;
      g0_gen3_q        <= 1'b0;
      g0_ok_q          <= 1'b0;
      g0_cnt_q         <= '0;
      g0_sdp_q         <= '0;
      g0_stp_q         <= '0;
      g0_end_q         <= '0;
      g0_edb_q         <= '0;
      g0_k_q           <= '0;
      g0_data_q        <= '0;
      g0_open_fin_q    <= 1'b0;
      g0_h0_q          <= '0;
      g0_end_pos0_v_q  <= 1'b0;
      g0_end_pos0_q    <= '0;
      g0_dllp_end0_v_q <= 1'b0;
      g0_dllp_end0_q   <= '0;
      g0_s1_drops_q    <= '0;
      g0_found_q       <= 1'b0;
      g0_s_idx_q       <= '0;
      g0_end_pos1_v_q  <= 1'b0;
      g0_end_pos1_q    <= '0;
      g0_dllp_end1_v_q <= 1'b0;
      g0_dllp_end1_q   <= '0;
      g0_s2_drops_q    <= '0;
      p0_lanes_ok_q    <= 1'b0;
      p0_cnt_q         <= '0;
      p0_sdp_q         <= '0;
      p0_stp_q         <= '0;
      p0_end_q         <= '0;
      p0_edb_q         <= '0;
      p0_k_q           <= '0;
      p0_nz_q          <= '0;
      for (int unsigned p = 0; p < NSYM; p++) p0_data_q[p] <= '0;
      p0a_lanes_ok_q    <= 1'b0;
      p0a_cnt_q         <= '0;
      p0a_end_q         <= '0;
      p0a_edb_q         <= '0;
      p0a_k_q           <= '0;
      p0a_nz_q          <= '0;
      for (int unsigned p = 0; p < NSYM; p++) p0a_data_q[p] <= '0;
      p0a_saw_sdp_q     <= 1'b0;
      p0a_saw_stp_q     <= 1'b0;
      p0a_start_idx_q   <= '0;
      p0a_base_q        <= '0;
      p0a_after_start_q <= '0;
    end else begin
      // Local copies of LTSSM control for packet-RX Stage IN.
      gf_gen3_rx_q <= ((PIPE_DATA_WIDTH == 32) && (rate_i == RIVET_PIPE_RATE_GEN3)) ||
                      ((PIPE_DATA_WIDTH == 64) && (rate_i == RIVET_PIPE_RATE_GEN4));
      lane_en_rx_q <= lane_en_i;

      // Stage IN: register dense raw symbols + pre-decoded TLP length hints.
      in_gen3_q <= gf_gen3_c;
      in_ok_q   <= gf_ok_c;
      in_cnt_q  <= gf_raw_cnt_c;
      in_sdp_q  <= gf_sdp_c;
      in_stp_q  <= gf_stp_c;
      in_end_q  <= gf_end_c;
      in_edb_q  <= gf_edb_c;
      in_k_q    <= gf_k_c;
      in_data_q <= gf_data_pack;
      for (int unsigned d = 0; d < 32; d++) begin
        automatic logic [7:0] b0 = ((d + 1) < NSYM) ? gf_data_pack[8*(d + 1) +: 8] : 8'h00;
        automatic logic [7:0] b1 = ((d + 2) < NSYM) ? gf_data_pack[8*(d + 2) +: 8] : 8'h00;
        in_tok_q[d]     <= (d < NSYM) && (6'(d) < gf_raw_cnt_c) &&
                           (gf_stp_c[d] || gf_sdp_c[d]);
        in_l_hi_z_q[d]  <= (b1 == 8'h00) && (b0[7:5] == 3'b000);
        in_l_hi6_z_q[d] <= (b1 == 8'h00) && (b0[7:6] == 2'b00);
        in_l_hi6_1_q[d] <= (b1 == 8'h00) && (b0[7:6] == 2'b01);
      end

      // Stage G0: advance framing state and latch compact metadata.
      g0_gen3_q <= in_gen3_q;
      g0_ok_q   <= in_ok_q;
      g0_cnt_q  <= in_cnt_q;
      g0_sdp_q  <= in_sdp_q;
      g0_stp_q  <= in_stp_q;
      g0_end_q  <= in_end_q;
      g0_edb_q  <= in_edb_q;
      g0_k_q    <= in_k_q;
      g0_data_q <= in_data_q;
      if (in_gen3_q) begin
        gf_st_q          <= gf_st_f;
        gf_left_q        <= gf_left_f;
        gf_left_hi_z_q   <= gf_left_hi_z_f;
        g0_open_fin_q    <= g0_open_fin_c;
        g0_h0_q          <= g0_h0_c;
        g0_end_pos0_v_q  <= g0_end_pos0_v_c;
        g0_end_pos0_q    <= g0_end_pos0_c;
        g0_dllp_end0_v_q <= g0_dllp_end0_v_c;
        g0_dllp_end0_q   <= g0_dllp_end0_c;
        g0_s1_drops_q    <= g0_s1_drops_c;
        g0_found_q       <= g0_found_c;
        g0_s_idx_q       <= g0_s_idx_c;
        g0_end_pos1_v_q  <= g0_end_pos1_v_c;
        g0_end_pos1_q    <= g0_end_pos1_c;
        g0_dllp_end1_v_q <= g0_dllp_end1_v_c;
        g0_dllp_end1_q   <= g0_dllp_end1_c;
        g0_s2_drops_q    <= g0_s2_drops_c;
      end else begin
        gf_st_q          <= '0;
        gf_left_q        <= '0;
        gf_left_hi_z_q   <= 1'b1;
        g0_open_fin_q    <= 1'b0;
        g0_h0_q          <= '0;
        g0_end_pos0_v_q  <= 1'b0;
        g0_end_pos0_q    <= '0;
        g0_dllp_end0_v_q <= 1'b0;
        g0_dllp_end0_q   <= '0;
        g0_s1_drops_q    <= '0;
        g0_found_q       <= 1'b0;
        g0_s_idx_q       <= '0;
        g0_end_pos1_v_q  <= 1'b0;
        g0_end_pos1_q    <= '0;
        g0_dllp_end1_v_q <= 1'b0;
        g0_dllp_end1_q   <= '0;
        g0_s2_drops_q    <= '0;
      end

      // Stage G1: register filtered & compacted P0 stream.
      p0_lanes_ok_q <= g0_ok_q;
      if (g0_gen3_q) begin
        p0_cnt_q <= gf_cnt_f;
        p0_sdp_q <= gf_sdp_f;
        p0_stp_q <= gf_stp_f;
        p0_end_q <= gf_end_f;
        p0_edb_q <= gf_edb_f;
        p0_k_q   <= gf_k_f;
        for (int unsigned p = 0; p < NSYM; p++) begin
          p0_data_q[p] <= gf_data_f[8*p +: 8];
          p0_nz_q[p]   <= (gf_data_f[8*p +: 8] != 8'h00);
        end
      end else begin
        p0_cnt_q <= g0_cnt_q;
        p0_sdp_q <= g0_sdp_q;
        p0_stp_q <= g0_stp_q;
        p0_end_q <= g0_end_q;
        p0_edb_q <= g0_edb_q;
        p0_k_q   <= g0_k_q;
        for (int unsigned p = 0; p < NSYM; p++) begin
          p0_data_q[p] <= g0_data_q[8*p +: 8];
          p0_nz_q[p]   <= (g0_data_q[8*p +: 8] != 8'h00);
        end
      end

      // Stage P0a: pre-decode first SDP/STP index & after-start mask.
      p0a_lanes_ok_q <= p0_lanes_ok_q;
      p0a_cnt_q      <= p0_cnt_q;
      p0a_end_q      <= p0_end_q;
      p0a_edb_q      <= p0_edb_q;
      p0a_k_q        <= p0_k_q;
      p0a_nz_q       <= p0_nz_q;
      for (int unsigned p = 0; p < NSYM; p++) p0a_data_q[p] <= p0_data_q[p];
      begin
        automatic logic [31:0] sdp_w = '0;
        automatic logic [31:0] stp_w = '0;
        automatic logic [31:0] sm;
        automatic logic [31:0] po;
        automatic logic [5:0]  sp;
        for (int unsigned i = 0; i < NSYM; i++) begin
          sdp_w[i] = p0_sdp_q[i];
          stp_w[i] = p0_stp_q[i];
        end
        sm = sdp_w | stp_w;
        po = {sm[30:0], 1'b0};
        po = po | {po[30:0], 1'b0};
        po = po | {po[29:0], 2'b0};
        po = po | {po[27:0], 4'b0};
        po = po | {po[23:0], 8'b0};
        p0a_after_start_q <= po | {po[15:0], 16'b0};
        sp = prio32(sm);
        p0a_start_idx_q <= sp[4:0];
        p0a_base_q      <= {1'b0, sp[4:0]} + 6'd1;
        p0a_saw_sdp_q   <= sp[5] && sdp_w[sp[4:0]];
        p0a_saw_stp_q   <= sp[5] && !sdp_w[sp[4:0]] && stp_w[sp[4:0]];
      end
    end
  end

  rx_pkt_e                rx_pkt_q, rx_pkt_d;
  logic [63:0]            rx_body_q, rx_body_d;
  logic [3:0]             rx_cnt_q, rx_cnt_d;
  logic                   rx_err_pkt_q, rx_err_pkt_d;
  logic                   dll_beat_valid_q, dll_beat_valid_d;
  rivet_dll_mac_rx_beat_t dll_beat_q, dll_beat_d;

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
  logic [63:0]             tlp_raw [4];
  logic                    tlp_use_hi_q, tlp_use_c_q, tlp_use_d_q;
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
  logic [12:0]             live_rem_q;
  logic [TLP_AW-1:0]       live_base_q, live_base_d;
  // A finished DLLP waits here when the beat slot is busy. Framing stays in
  // IDLE/RX_TLP so the next TLP is not dropped while the DLLP waits.
  logic                    dllp_park_q, dllp_park_d;
  logic [63:0]             dllp_park_data_q, dllp_park_data_d;
  logic                    dllp_park_err_q, dllp_park_err_d;
  logic                    dllp_park_ld;

  // Stage P1 pipeline between P0 framing decode and TLP RAM store/used_q.
  logic                    st_valid_q, st_valid_d;
  logic                    st_start_q, st_start_d;
  logic                    st_done_q, st_done_d;
  logic                    st_err_q, st_err_d;
  logic [5:0]              st_n_q, st_n_d;
  logic [255:0]            st_data_q, st_data_d;
  logic                    st_open_q, st_open_d;
  logic [12:0]             rx_tlp_cnt_q, rx_tlp_cnt_d;
  logic                    used_hi_q;

  logic [TLP_AW-1:0] tlp_raddr1, tlp_raddr2, tlp_raddr3;

  assign tlp_raddr1 = rd_addr_q + TLP_AW'(1);
  assign tlp_raddr2 = rd_addr_q + TLP_AW'(2);
  assign tlp_raddr3 = rd_addr_q + TLP_AW'(3);
  assign tlp_ram_rd_q    = tlp_raw[0];
  assign tlp_ram_rd_hi_q = tlp_use_hi_q ? tlp_raw[1] : '0;
  assign tlp_ram_rd_c_q  = tlp_use_c_q  ? tlp_raw[2] : '0;
  assign tlp_ram_rd_d_q  = tlp_use_d_q  ? tlp_raw[3] : '0;

  rivet_ram_lane4 #(.DEPTH(TLP_RAM_N)) u_tlp_ram (
    .clk_i   (pclk_i),
    .rst_ni  (rst_ni),
    .we_i    ({tlp_ram_we4, tlp_ram_we3, tlp_ram_we2, tlp_ram_we}),
    .waddr_i ('{tlp_ram_waddr, tlp_ram_waddr2, tlp_ram_waddr3, tlp_ram_waddr4}),
    .wdata_i ('{tlp_ram_wdata, tlp_ram_wdata2, tlp_ram_wdata3, tlp_ram_wdata4}),
    .re_i    (tlp_rd_issue),
    .raddr_i ('{rd_addr_q, tlp_raddr1, tlp_raddr2, tlp_raddr3}),
    .rdata_o (tlp_raw)
  );

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
    logic [5:0] n6;
    logic [2:0] nwords;
    logic [2:0] avail_p;
    logic [2:0] take_w;
    logic [55:0] tail_w;
    acc      = '0;
    acc_n    = '0;
    overflow = 1'b0;
    n6       = 6'(nbytes);
    nwords   = n6[5:3];
    avail_p  = (nport >= 4) ? 3'd0 : 3'(4 - nport);
    take_w   = (nwords > avail_p) ? avail_p : nwords;
    for (int unsigned step = 0; step < 4; step++) begin
      if (3'(step) < take_w) begin
        rx_push_word(nport, raw_b_bytes[64*step +: 64], slot);
        slot = slot + TLP_AW'(1);
      end
    end
    if (nwords > avail_p) begin
      overflow = 1'b1;
    end else begin
      acc_n = n6[2:0];
      case (nwords)
        3'd0:    tail_w = raw_b_bytes[55:0];
        3'd1:    tail_w = raw_b_bytes[119:64];
        3'd2:    tail_w = raw_b_bytes[183:128];
        3'd3:    tail_w = raw_b_bytes[247:192];
        default: tail_w = raw_b_bytes[311:256];
      endcase
      for (int unsigned k = 0; k < 7; k++) begin
        if (3'(k) < acc_n)
          acc[8*k +: 8] = tail_w[8*k +: 8];
      end
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

  // Destination-byte-first merge of 0..7 acc bytes + 0..32 cap bytes into
  // a 40-byte frame. acc_n is only 3 bits so each byte is an 8:1 mux.
  function automatic logic [319:0] pack_acc_cap(
      input logic [55:0] acc,
      input logic [2:0]  acc_n,
      input logic [7:0]  cap [0:31],
      input logic [5:0]  cap_n
  );
    logic [7:0]   ab [8];
    logic [319:0] raw;
    for (int unsigned i = 0; i < 7; i++) ab[i] = acc[8*i +: 8];
    ab[7] = 8'h00;
    raw = '0;
    for (int unsigned k = 0; k < 40; k++) begin
      automatic logic [5:0] diff;
      diff = 6'(k) - {3'd0, acc_n};
      if ((k < 7) && (3'(k) < acc_n)) begin
        raw[8*k +: 8] = ab[3'(k)];
      end else if ((6'(k) >= {3'd0, acc_n}) && (diff < cap_n)) begin
        raw[8*k +: 8] = cap[diff[4:0]];
      end
    end
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

  always_ff @(posedge pclk_i) begin
    if (!rst_ni) begin
      tlp_use_hi_q <= 1'b0;
      tlp_use_c_q  <= 1'b0;
      tlp_use_d_q  <= 1'b0;
    end else if (tlp_rd_issue && live_q) begin
      logic [TLP_AW-1:0] have;
      have = tlp_wr_slot_q - rd_addr_q;
      tlp_use_hi_q <= (have > TLP_AW'(1));
      tlp_use_c_q  <= (have > TLP_AW'(2));
      tlp_use_d_q  <= (have > TLP_AW'(3));
    end else if (tlp_rd_issue) begin
      tlp_use_hi_q <= (RX_PLAY_W >= 2);
      tlp_use_c_q  <= (RX_PLAY_W >= 4);
      tlp_use_d_q  <= (RX_PLAY_W >= 4);
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
    st_valid_d       = 1'b0;
    st_start_d       = 1'b0;
    st_done_d        = 1'b0;
    st_err_d         = 1'b0;
    st_n_d           = 6'd0;
    st_data_d        = '0;
    st_open_d        = st_open_q;
    rx_tlp_cnt_d     = rx_tlp_cnt_q;

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

    if (p0a_lanes_ok_q || (rx_pkt_q == RX_HOLD)) begin
      // 32-symbol padded views of dense P0a stream (0..p0a_cnt_q-1 have no holes;
      // token flags are already 0 at indices >= p0a_cnt_q).
      automatic logic [31:0] p0_end_w = '0;
      automatic logic [31:0] p0_edb_w = '0;
      automatic logic [63:0] p0_k_w   = '0;
      automatic logic [31:0] p0_nz_w  = '0;
      automatic logic [7:0]  p0_data_w [0:63];
      for (int unsigned i = 0; i < 64; i++) p0_data_w[i] = 8'h00;
      for (int unsigned i = 0; i < NSYM; i++) begin
        p0_end_w[i]  = p0a_end_q[i];
        p0_edb_w[i]  = p0a_edb_q[i];
        p0_k_w[i]    = p0a_k_q[i];
        p0_nz_w[i]   = p0a_nz_q[i];
        p0_data_w[i] = p0a_data_q[i];
      end

      unique case (rx_pkt_q)
        RX_IDLE: begin
          if (p0a_lanes_ok_q) begin
            automatic logic        saw_sdp     = p0a_saw_sdp_q;
            automatic logic        saw_stp     = p0a_saw_stp_q;
            automatic logic [3:0]  c           = 4'd0;
            automatic logic [63:0] b           = '0;
            automatic logic [5:0]  cap_n       = 6'd0;
            automatic logic [7:0]  cap_b [0:31];
            automatic logic        err         = 1'b0;
            automatic logic        done        = 1'b0;
            automatic logic        nullified   = 1'b0;
            automatic logic [31:0] after_start = p0a_after_start_q;
            automatic logic [4:0]  start_idx   = p0a_start_idx_q;
            automatic logic [5:0]  base        = p0a_base_q;

            for (int unsigned i = 0; i < 32; i++) cap_b[i] = 8'h00;

            if (saw_sdp) begin
              automatic logic [5:0]  after_n = (p0a_cnt_q > base) ? (p0a_cnt_q - base) : 6'd0;
              automatic logic [2:0]  blim    = (after_n < 6'(RIVET_DLLP_WIRE_BYTES)) ?
                                               after_n[2:0] : 3'(RIVET_DLLP_WIRE_BYTES);
              automatic logic [5:0]  kb_m    = '0;
              automatic logic [7:0]  sb [6];
              // Direct 5-bit indexing by registered start_idx.
              for (int unsigned j = 0; j < 6; j++) begin
                automatic logic [7:0]  d_col [0:31];
                automatic logic [31:0] k_col;
                for (int unsigned p = 0; p < 32; p++) begin
                  d_col[p] = p0_data_w[p + j + 1];
                  k_col[p] = p0_k_w[p + j + 1];
                end
                sb[j]   = d_col[start_idx];
                kb_m[j] = (3'(j) < blim) && k_col[start_idx];
              end
              for (int unsigned j = 0; j < 6; j++) begin
                automatic logic [5:0] pref_m = (6'd1 << (j + 1)) - 6'd1;
                if ((3'(j) < blim) && ((kb_m & pref_m) == 6'd0))
                  b[8*j +: 8] = sb[j];
              end
              if (kb_m != 6'd0) begin
                automatic logic [5:0] kp = prio32({26'd0, kb_m});
                c    = {1'b0, kp[2:0]};
                err  = 1'b1;
                done = 1'b1;
              end else begin
                c = {1'b0, blim};
                if (after_n > 6'(RIVET_DLLP_WIRE_BYTES)) begin
                  automatic logic [31:0] tail_m = '0;
                  automatic logic [5:0]  tp;
                  for (int unsigned p = 7; p < 32; p++) begin
                    tail_m[p] = after_start[p - 6] && (6'(p) < p0a_cnt_q) &&
                                (p0_end_w[p] || p0_edb_w[p] || p0_k_w[p] || p0_nz_w[p]);
                  end
                  tp = prio32(tail_m);
                  if (tp[5]) begin
                    done      = 1'b1;
                    nullified = !p0_end_w[tp[4:0]] && p0_edb_w[tp[4:0]];
                    err       = !p0_end_w[tp[4:0]] && !p0_edb_w[tp[4:0]];
                  end
                end
              end
            end else if (saw_stp) begin
              automatic logic [31:0] term_m = '0;
              automatic logic [5:0]  tp;
              for (int unsigned p = 1; p < 32; p++) begin
                term_m[p] = after_start[p] && (p0_end_w[p] || p0_edb_w[p] || p0_k_w[p]);
              end
              tp = prio32(term_m);
              if (tp[5]) begin
                done      = 1'b1;
                nullified = !p0_end_w[tp[4:0]] && p0_edb_w[tp[4:0]];
                err       = !p0_end_w[tp[4:0]] && !p0_edb_w[tp[4:0]] && p0_k_w[tp[4:0]];
                cap_n     = {1'b0, tp[4:0]} - base;
              end else begin
                cap_n     = (p0a_cnt_q > base) ? (p0a_cnt_q - base) : 6'd0;
              end
              for (int unsigned i = 0; i < 32; i++) begin
                automatic logic [7:0] d_col [0:31];
                for (int unsigned p = 0; p < 32; p++)
                  d_col[p] = p0_data_w[p + i + 1];
                cap_b[i] = d_col[start_idx];
              end
            end

            if (saw_sdp) begin
              rx_body_d    = b;
              rx_cnt_d     = c;
              rx_err_pkt_d = err;
              if (done) begin
                // Always stage completed DLLPs through dllp_park_q so P0
                // capture stays decoupled from dll_beat_q and TLP playback.
                dllp_park_d      = 1'b1;
                dllp_park_data_d = b;
                dllp_park_err_d  = err | nullified;
                dllp_park_ld     = 1'b1;
                rx_pkt_d         = RX_IDLE;
                rx_cnt_d         = 4'd0;
              end else begin
                rx_pkt_d = RX_BODY;
              end
            end else if (saw_stp) begin
              st_valid_d   = 1'b1;
              st_start_d   = 1'b1;
              st_done_d    = done;
              st_err_d     = err | nullified;
              st_n_d       = cap_n;
              for (int unsigned i = 0; i < 32; i++)
                st_data_d[8*i +: 8] = cap_b[i];
              rx_tlp_cnt_d = done ? 13'd0 : 13'(cap_n);
              rx_pkt_d     = done ? RX_IDLE : RX_TLP;
            end
          end
        end

        RX_BODY: begin
          if (p0a_lanes_ok_q) begin
            automatic logic [3:0]  c         = rx_cnt_q;
            automatic logic [63:0] b         = rx_body_q;
            automatic logic        err       = rx_err_pkt_q;
            automatic logic        done      = 1'b0;
            automatic logic        nullified = 1'b0;
            automatic logic [2:0]  rem_d     = (rx_cnt_q < 4'(RIVET_DLLP_WIRE_BYTES)) ?
                                               3'(4'(RIVET_DLLP_WIRE_BYTES) - rx_cnt_q) : 3'd0;
            automatic logic [2:0]  blim      = (p0a_cnt_q < {3'd0, rem_d}) ? p0a_cnt_q[2:0] : rem_d;
            automatic logic [5:0]  kb_m      = '0;
            automatic logic [2:0]  take_b;

            for (int unsigned j = 0; j < 6; j++)
              kb_m[j] = (3'(j) < blim) && p0_k_w[j];

            if (kb_m != 6'd0) begin
              automatic logic [5:0] kp = prio32({26'd0, kb_m});
              take_b = kp[2:0];
              err    = 1'b1;
              done   = 1'b1;
            end else begin
              take_b = blim;
            end

            for (int unsigned k = 0; k < 6; k++) begin
              if ((4'(k) >= rx_cnt_q) && ((4'(k) - rx_cnt_q) < {1'b0, take_b})) begin
                automatic logic [3:0] diff = 4'(k) - rx_cnt_q;
                b[8*k +: 8] = p0_data_w[{3'd0, diff[2:0]}];
              end
            end
            c = rx_cnt_q + {1'b0, take_b};

            if (!done && (p0a_cnt_q > {3'd0, rem_d})) begin
              automatic logic [31:0] tail_m = '0;
              automatic logic [5:0]  tp;
              for (int unsigned p = 0; p < 32; p++) begin
                tail_m[p] = (6'(p) >= {3'd0, rem_d}) && (6'(p) < p0a_cnt_q) &&
                            (p0_end_w[p] || p0_edb_w[p] || p0_k_w[p] || p0_nz_w[p]);
              end
              tp = prio32(tail_m);
              if (tp[5]) begin
                done      = 1'b1;
                nullified = !p0_end_w[tp[4:0]] && p0_edb_w[tp[4:0]];
                if (!p0_end_w[tp[4:0]] && !p0_edb_w[tp[4:0]])
                  err = 1'b1;
              end
            end

            rx_body_d    = b;
            rx_cnt_d     = c;
            rx_err_pkt_d = err;

            if (done) begin
              dllp_park_d      = 1'b1;
              dllp_park_data_d = b;
              dllp_park_err_d  = err | nullified;
              dllp_park_ld     = 1'b1;
              rx_pkt_d         = RX_IDLE;
              rx_cnt_d         = 4'd0;
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
          if (p0a_lanes_ok_q) begin
            automatic logic [5:0]   cap_n     = 6'd0;
            automatic logic [13:0]  new_cnt;
            automatic logic         len_ovf;
            automatic logic         err       = 1'b0;
            automatic logic         done      = 1'b0;
            automatic logic         nullified = 1'b0;
            automatic logic [31:0]  term_m    = '0;
            automatic logic [5:0]   tp;

            for (int unsigned p = 0; p < 32; p++)
              term_m[p] = p0_end_w[p] || p0_edb_w[p] || p0_k_w[p];
            tp = prio32(term_m);
            if (tp[5]) begin
              done      = 1'b1;
              nullified = !p0_end_w[tp[4:0]] && p0_edb_w[tp[4:0]];
              if (!p0_end_w[tp[4:0]] && !p0_edb_w[tp[4:0]] && p0_k_w[tp[4:0]])
                err = 1'b1;
              cap_n     = {1'b0, tp[4:0]};
            end else begin
              cap_n     = p0a_cnt_q;
            end

            new_cnt = {1'b0, rx_tlp_cnt_q} + 14'(cap_n);
            len_ovf = (new_cnt > 14'(TLP_FRAME_MAX)) || used_hi_q;

            st_valid_d   = 1'b1;
            st_start_d   = 1'b0;
            st_done_d    = done | len_ovf;
            st_err_d     = err | nullified | len_ovf;
            st_n_d       = cap_n;
            for (int unsigned i = 0; i < 32; i++)
              st_data_d[8*i +: 8] = p0_data_w[i];
            rx_tlp_cnt_d = (done || len_ovf) ? 13'd0 : new_cnt[12:0];
            rx_pkt_d     = (done || len_ovf) ? RX_IDLE : RX_TLP;
          end
        end

        RX_TLP_OUT: rx_pkt_d = RX_IDLE;

        default: rx_pkt_d = RX_IDLE;
      endcase
    end

    // Stage P1: pack captured TLP chunk, write full words to BRAM, and push
    // finished frames. Pipelined 1 cycle after P0 framing decode.
    if (st_valid_q) begin
      if (st_start_q) begin
        automatic logic [TLP_AW-1:0] slot;
        automatic logic [TLP_AW-1:0] base_s;
        automatic logic [319:0]      raw_b;
        automatic logic [55:0]       acc;
        automatic logic [2:0]        acc_n;
        automatic int unsigned       nport;
        automatic logic              overflow;
        nport  = tlp_tail_pend_q ? 1 : 0;
        base_s = tlp_tail_pend_q ? (tlp_wr_slot_q + TLP_AW'(1)) : tlp_wr_slot_q;
        slot   = base_s;
        raw_b  = '0;
        for (int unsigned i = 0; i < 32; i++)
          if (6'(i) < st_n_q)
            raw_b[8*i +: 8] = st_data_q[8*i +: 8];
        rx_store(raw_b, int'(st_n_q), slot, acc, acc_n, nport, overflow);
        tlp_base_d    = base_s;
        tlp_wr_slot_d = slot;
        tlp_len_d     = 13'(st_n_q);
        tlp_err_d     = st_err_q | overflow |
                        (st_done_q && (st_n_q == 6'd0)) | used_hi_q;
        if (st_done_q) begin
          if (!tlp_err_d && (acc_n != 3'd0)) begin
            tlp_acc_d       = acc;
            tlp_acc_cnt_d   = acc_n;
            tlp_tail_pend_d = 1'b1;
          end else begin
            tlp_acc_d     = '0;
            tlp_acc_cnt_d = 3'd0;
          end
          frame_push_d      = 1'b1;
          frame_push_base_d = base_s;
          frame_push_len_d  = 13'(st_n_q);
          frame_push_err_d  = tlp_err_d;
          st_open_d         = 1'b0;
        end else begin
          tlp_acc_d     = acc;
          tlp_acc_cnt_d = acc_n;
          st_open_d     = 1'b1;
        end
      end else begin
        automatic logic [7:0]        cap_b [0:31];
        automatic logic [319:0]      raw_b;
        automatic logic [13:0]       new_len;
        automatic logic              len_ovf;
        automatic logic              done_c;
        automatic logic [TLP_AW-1:0] slot;
        automatic logic [55:0]       acc;
        automatic logic [2:0]        acc_n;
        automatic int unsigned       nport;
        automatic logic              overflow;
        automatic int unsigned       nbytes;
        for (int unsigned i = 0; i < 32; i++)
          cap_b[i] = st_data_q[8*i +: 8];
        new_len   = {1'b0, tlp_len_q} + 14'(st_n_q);
        len_ovf   = (new_len > 14'(TLP_FRAME_MAX)) || used_hi_q;
        done_c    = st_done_q | len_ovf;
        raw_b     = pack_acc_cap(tlp_acc_q, tlp_acc_cnt_q, cap_b, st_n_q);
        tlp_len_d = len_ovf ? 13'(TLP_FRAME_MAX) : new_len[12:0];
        tlp_err_d = tlp_err_q | st_err_q | len_ovf |
                    (done_c && (new_len == 14'd0));
        nport  = 0;
        slot   = tlp_wr_slot_q;
        nbytes = int'(tlp_acc_cnt_q) + int'(st_n_q);
        rx_store(raw_b, nbytes, slot, acc, acc_n, nport, overflow);
        tlp_wr_slot_d = slot;
        if (overflow)
          tlp_err_d = 1'b1;
        if (done_c) begin
          if (!tlp_err_d && (acc_n != 3'd0)) begin
            tlp_acc_d       = acc;
            tlp_acc_cnt_d   = acc_n;
            tlp_tail_pend_d = 1'b1;
          end else begin
            tlp_acc_d     = '0;
            tlp_acc_cnt_d = 3'd0;
          end
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
          st_open_d = 1'b0;
        end else begin
          tlp_acc_d     = acc;
          tlp_acc_cnt_d = acc_n;
          st_open_d     = 1'b1;
        end
      end
    end

    // Parked DLLP goes out ahead of TLP playback. Capture never writes
    // dll_beat_d when dllp_park_q is set or rd_ph_q != 0, so playback only
    // checks registered slot occupancy (no combinational path from capture).
    if (dllp_park_q && !(dll_beat_valid_q && !dll_rx_ready_i)) begin
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
        if (!(dll_beat_valid_q && !dll_rx_ready_i) && !dllp_park_q) begin
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
        if (live_closed_q && (live_rem_q == 13'd0)) begin
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
    end else if (live_q && !(dll_beat_valid_q && !dll_rx_ready_i) && !dllp_park_q) begin
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
        live_rem_b = live_closed_q ? live_rem_q : 13'(RX_PLAY_B);
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
                                         live_closed_q, live_len_q)) begin
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
    end else if (!(dll_beat_valid_q && !dll_rx_ready_i) && !dllp_park_q) begin
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
        (q_count_q == 5'd0) && st_open_q && !(st_valid_q && st_done_q) &&
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
      live_rem_q       <= '0;
      live_base_q      <= '0;
      dllp_park_q      <= 1'b0;
      dllp_park_data_q <= '0;
      dllp_park_err_q  <= 1'b0;
      st_valid_q       <= 1'b0;
      st_start_q       <= 1'b0;
      st_done_q        <= 1'b0;
      st_err_q         <= 1'b0;
      st_n_q           <= '0;
      st_data_q        <= '0;
      st_open_q        <= 1'b0;
      rx_tlp_cnt_q     <= '0;
      used_hi_q        <= 1'b0;
    end else begin
      logic [2:0]  wr_cnt;
      logic [12:0] sub_cnt;
      logic [13:0] used_sum;
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
      live_rem_q       <= (live_len_d > live_sent_d) ? (live_len_d - live_sent_d) : 13'd0;
      live_base_q      <= live_base_d;
      dllp_park_q      <= dllp_park_d;
      dllp_park_data_q <= dllp_park_data_d;
      dllp_park_err_q  <= dllp_park_err_d;
      st_valid_q       <= st_valid_d;
      st_start_q       <= st_start_d;
      st_done_q        <= st_done_d;
      st_err_q         <= st_err_d;
      st_n_q           <= st_n_d;
      st_data_q        <= st_data_d;
      st_open_q        <= st_open_d;
      rx_tlp_cnt_q     <= rx_tlp_cnt_d;
      used_hi_q        <= (used_q > 13'd3600);
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
      wr_cnt   = {2'd0, tlp_ram_we} + {2'd0, tlp_ram_we2} +
                 {2'd0, tlp_ram_we3} + {2'd0, tlp_ram_we4};
      sub_cnt  = (rd_drop != 12'd0) ? {1'b0, rd_drop} : {10'd0, rd_words};
      used_sum = {1'b0, used_q} + {11'd0, wr_cnt};
      used_q  <= ({1'b0, sub_cnt} >= used_sum) ? 13'd0 : (used_sum[12:0] - sub_cnt);
    end
  end

  assign dll_rx_beat_o  = dll_beat_q;
  assign dll_rx_valid_o = dll_beat_valid_q;

endmodule : rivet_mac_os_rx

// Stage G0 of Gen3/Gen4 framing filter: advances (st_i, left_i) and produces
// compact metadata for Stage G1. Pre-decoded l_hi_z_i and registered
// left_hi_z_i eliminate 16-bit comparison carry chains from the critical path.
module rivet_mac_gf_scan_meta #(
  parameter int unsigned NSYM       = 32,
  parameter int unsigned DLLP_BYTES = 6
) (
  input  logic [2:0]          st_i,
  input  logic [15:0]         left_i,
  input  logic                left_hi_z_i,
  input  logic [5:0]          cnt_i,
  input  logic [NSYM-1:0]     stp_i,
  input  logic [31:0]         tok_i,
  input  logic [8*NSYM-1:0]   data_i,
  input  logic [31:0]         l_hi_z_i,
  input  logic [31:0]         l_hi6_z_i,
  input  logic [31:0]         l_hi6_1_i,
  output logic [2:0]          st_o,
  output logic [15:0]         left_o,
  output logic                left_hi_z_o,
  output logic                open_fin_o,
  output logic [5:0]          h0_o,
  output logic                end_pos0_v_o,
  output logic [5:0]          end_pos0_o,
  output logic                dllp_end0_v_o,
  output logic [5:0]          dllp_end0_o,
  output logic [1:0]          s1_drops_o,
  output logic                found_o,
  output logic [4:0]          s_idx_o,
  output logic                end_pos1_v_o,
  output logic [5:0]          end_pos1_o,
  output logic                dllp_end1_v_o,
  output logic [5:0]          dllp_end1_o,
  output logic [1:0]          s2_drops_o
);

  function automatic logic [5:0] prio32(input logic [31:0] m);
    logic [7:0]  g_v;
    logic [1:0]  g_i [8];
    logic [1:0]  h_v;
    logic [3:0]  h_i [2];
    logic        v;
    logic [4:0]  idx;
    for (int unsigned g = 0; g < 8; g++) begin
      g_v[g] = |m[4*g +: 4];
      if      (m[4*g + 0]) g_i[g] = 2'd0;
      else if (m[4*g + 1]) g_i[g] = 2'd1;
      else if (m[4*g + 2]) g_i[g] = 2'd2;
      else                 g_i[g] = 2'd3;
    end
    for (int unsigned h = 0; h < 2; h++) begin
      h_v[h] = |g_v[4*h +: 4];
      if      (g_v[4*h + 0]) h_i[h] = {2'd0, g_i[4*h + 0]};
      else if (g_v[4*h + 1]) h_i[h] = {2'd1, g_i[4*h + 1]};
      else if (g_v[4*h + 2]) h_i[h] = {2'd2, g_i[4*h + 2]};
      else                   h_i[h] = {2'd3, g_i[4*h + 3]};
    end
    v   = h_v[0] || h_v[1];
    idx = h_v[0] ? {1'b0, h_i[0]} : {1'b1, h_i[1]};
    return {v, idx};
  endfunction

  always_comb begin
    logic [31:0] stp_w;
    logic [7:0]  data_b [0:63];

    // Precomputed per-position Step-2 decisions (zero dependence on st_i/left_i).
    logic [31:0] stp_fin_at;
    logic [31:0] stp_hi_z_at;
    logic [31:0] dllp_fin_at;
    logic [5:0]  end1_at [0:31];
    logic [15:0] left_step2_at [0:31];
    logic [31:0] left_hi_z_step2_at;
    logic [2:0]  st_step2_at [0:31];
    logic [1:0]  s2_drops_at [0:31];
    logic [31:0] end_pos1_v_at;
    logic [31:0] dllp_end1_v_at;
    logic [5:0]  dllp_end1_at [0:31];

    // Step 1: resolve any open packet carried in (st_i, left_i).
    logic        open_fin;
    logic [5:0]  h0;
    logic        end_pos0_v, dllp_end0_v;
    logic [5:0]  end_pos0, dllp_end0;
    logic [1:0]  s1_drops;
    logic [2:0]  mid_st;
    logic [15:0] mid_left;
    logic        left_lt_cnt;

    // Step 2: hunt from h0 for the first STP or SDP in the beat.
    logic [31:0] cand;
    logic [5:0]  sp;
    logic        found;
    logic [4:0]  s_idx;
    logic        is_stp;
    logic [5:0]  rem, rem_pay;
    logic [7:0]  b0, b1;
    logic [15:0] l_new;
    logic        end_pos1_v, dllp_end1_v;
    logic [5:0]  end_pos1, dllp_end1;
    logic [1:0]  s2_drops;

    stp_w = '0;
    stp_w[NSYM-1:0] = stp_i;
    for (int unsigned i = 0; i < 64; i++)
      data_b[i] = (i < NSYM) ? data_i[8*i +: 8] : 8'h00;

    for (int unsigned d = 0; d < 32; d++) begin
      automatic logic [5:0]  rem_d = (cnt_i > (6'(d) + 6'd1)) ? (cnt_i - 6'd1 - 6'(d)) : 6'd0;
      automatic logic [5:0]  rp_d  = (rem_d >= 6'd2) ? (rem_d - 6'd2) : 6'd0;
      automatic logic [5:0]  lo_d  = data_b[d + 1][5:0] - rp_d;
      automatic logic        bor_d = (data_b[d + 1][5:0] < rp_d);
      automatic logic [9:0]  hi_d  = {data_b[d + 2], data_b[d + 1][7:6]};
      automatic logic [15:0] stp_l_d  = {hi_d - {9'd0, bor_d}, lo_d};
      automatic logic [15:0] dllp_l_d = 16'(DLLP_BYTES) - 16'(rem_d);
      stp_fin_at[d]   = (rem_d >= 6'd2) && l_hi_z_i[d] &&
                        ({1'b0, data_b[d + 1][4:0]} < rp_d);
      stp_hi_z_at[d]  = (l_hi6_z_i[d] && !bor_d) || (l_hi6_1_i[d] && bor_d);
      end1_at[d]      = 6'(d) + 6'd3 + {1'b0, data_b[d + 1][4:0]};
      dllp_fin_at[d]  = (rem_d > 6'(DLLP_BYTES));
      dllp_end1_at[d] = 6'(d) + 6'd1 + 6'(DLLP_BYTES);

      end_pos1_v_at[d]  = 1'b0;
      dllp_end1_v_at[d] = 1'b0;
      if (stp_w[d]) begin
        if (rem_d == 6'd0) begin
          s2_drops_at[d]        = 2'd0;
          st_step2_at[d]        = 3'd1;
          left_step2_at[d]      = 16'd0;
          left_hi_z_step2_at[d] = 1'b1;
        end else if (rem_d == 6'd1) begin
          s2_drops_at[d]        = 2'd1;
          st_step2_at[d]        = 3'd2;
          left_step2_at[d]      = {8'd0, data_b[d + 1]};
          left_hi_z_step2_at[d] = (data_b[d + 1][7:6] == 2'b00);
        end else begin
          s2_drops_at[d] = 2'd2;
          if (stp_fin_at[d]) begin
            end_pos1_v_at[d]      = 1'b1;
            st_step2_at[d]        = 3'd0;
            left_step2_at[d]      = 16'd0;
            left_hi_z_step2_at[d] = 1'b1;
          end else begin
            st_step2_at[d]        = 3'd3;
            left_step2_at[d]      = stp_l_d;
            left_hi_z_step2_at[d] = stp_hi_z_at[d];
          end
        end
      end else begin
        s2_drops_at[d]        = 2'd0;
        left_hi_z_step2_at[d] = 1'b1;
        if (dllp_fin_at[d]) begin
          dllp_end1_v_at[d] = 1'b1;
          st_step2_at[d]    = 3'd0;
          left_step2_at[d]  = 16'd0;
        end else begin
          st_step2_at[d]    = 3'd4;
          left_step2_at[d]  = dllp_l_d;
        end
      end
    end

    left_lt_cnt = left_hi_z_i && (left_i[5:0] < cnt_i);

    open_fin    = 1'b0;
    h0          = 6'd0;
    end_pos0_v  = 1'b0;
    end_pos0    = 6'd0;
    dllp_end0_v = 1'b0;
    dllp_end0   = 6'd0;
    s1_drops    = 2'd0;
    mid_st      = st_i;
    mid_left    = left_i;

    unique case (st_i)
      3'd0: begin
        open_fin = 1'b1;
        h0       = 6'd0;
        mid_st   = 3'd0;
        mid_left = 16'd0;
      end
      3'd1: begin
        if (cnt_i == 6'd0) begin
          open_fin = 1'b0;
          mid_st   = 3'd1;
          mid_left = left_i;
        end else if (cnt_i == 6'd1) begin
          s1_drops = 2'd1;
          open_fin = 1'b0;
          mid_st   = 3'd2;
          mid_left = {8'd0, data_b[0]};
        end else begin
          automatic logic [15:0] l1 = {data_b[1], data_b[0]};
          automatic logic [5:0]  e1 = 6'd2 + {1'b0, data_b[0][4:0]};
          automatic logic        e1_fin = (data_b[1] == 8'h00) &&
                                          (data_b[0][7:5] == 3'b000) &&
                                          (e1 < cnt_i);
          s1_drops = 2'd2;
          if (e1_fin) begin
            open_fin   = 1'b1;
            end_pos0_v = 1'b1;
            end_pos0   = e1;
            h0         = e1 + 6'd1;
            mid_st     = 3'd0;
            mid_left   = 16'd0;
          end else begin
            open_fin = 1'b0;
            mid_st   = 3'd3;
            mid_left = l1 - (16'(cnt_i) - 16'd2);
          end
        end
      end
      3'd2: begin
        if (cnt_i == 6'd0) begin
          open_fin = 1'b0;
          mid_st   = 3'd2;
          mid_left = left_i;
        end else begin
          automatic logic [15:0] l2 = {data_b[0], left_i[7:0]};
          automatic logic [5:0]  e2 = 6'd1 + {1'b0, left_i[4:0]};
          automatic logic        e2_fin = (data_b[0] == 8'h00) &&
                                          (left_i[7:5] == 3'b000) &&
                                          (e2 < cnt_i);
          s1_drops = 2'd1;
          if (e2_fin) begin
            open_fin   = 1'b1;
            end_pos0_v = 1'b1;
            end_pos0   = e2;
            h0         = e2 + 6'd1;
            mid_st     = 3'd0;
            mid_left   = 16'd0;
          end else begin
            open_fin = 1'b0;
            mid_st   = 3'd3;
            mid_left = l2 - (16'(cnt_i) - 16'd1);
          end
        end
      end
      3'd3: begin
        if (left_lt_cnt) begin
          open_fin   = 1'b1;
          end_pos0_v = 1'b1;
          end_pos0   = left_i[5:0];
          h0         = left_i[5:0] + 6'd1;
          mid_st     = 3'd0;
          mid_left   = 16'd0;
        end else begin
          open_fin = 1'b0;
          mid_st   = 3'd3;
          mid_left = left_i - 16'(cnt_i);
        end
      end
      3'd4: begin
        if (left_lt_cnt) begin
          open_fin    = 1'b1;
          dllp_end0_v = 1'b1;
          dllp_end0   = left_i[5:0];
          h0          = left_i[5:0] + 6'd1;
          mid_st      = 3'd0;
          mid_left    = 16'd0;
        end else begin
          open_fin = 1'b0;
          mid_st   = 3'd4;
          mid_left = left_i - 16'(cnt_i);
        end
      end
      default: begin
        open_fin = 1'b1;
        h0       = 6'd0;
        mid_st   = 3'd0;
        mid_left = 16'd0;
      end
    endcase

    cand = '0;
    for (int unsigned d = 0; d < 32; d++)
      cand[d] = open_fin && (6'(d) >= h0) && tok_i[d];
    sp    = prio32(cand);
    found = sp[5];
    s_idx = sp[4:0];

    is_stp      = stp_w[s_idx];
    rem         = 6'd0;
    rem_pay     = 6'd0;
    b0          = 8'd0;
    b1          = 8'd0;
    l_new       = 16'd0;
    end_pos1_v  = 1'b0;
    end_pos1    = 6'd0;
    dllp_end1_v = 1'b0;
    dllp_end1   = 6'd0;
    s2_drops    = 2'd0;
    st_o        = mid_st;
    left_o      = mid_left;
    left_hi_z_o = (mid_left[15:6] == 10'd0);

    if (open_fin && found) begin
      s2_drops    = s2_drops_at[s_idx];
      st_o        = st_step2_at[s_idx];
      left_o      = left_step2_at[s_idx];
      left_hi_z_o = left_hi_z_step2_at[s_idx];
      end_pos1_v  = end_pos1_v_at[s_idx];
      end_pos1    = end1_at[s_idx];
      dllp_end1_v = dllp_end1_v_at[s_idx];
      dllp_end1   = dllp_end1_at[s_idx];
    end

    open_fin_o    = open_fin;
    h0_o          = h0;
    end_pos0_v_o  = end_pos0_v;
    end_pos0_o    = end_pos0;
    dllp_end0_v_o = dllp_end0_v;
    dllp_end0_o   = dllp_end0;
    s1_drops_o    = s1_drops;
    found_o       = found;
    s_idx_o       = s_idx;
    end_pos1_v_o  = end_pos1_v;
    end_pos1_o    = end_pos1;
    dllp_end1_v_o = dllp_end1_v;
    dllp_end1_o   = dllp_end1;
    s2_drops_o    = s2_drops;
  end
endmodule : rivet_mac_gf_scan_meta

// Stage G1 of Gen3/Gen4 framing filter: masks payload token flags and compacts
// out the 0..4 stripped TLP length bytes with a 5:1 mux.
module rivet_mac_gf_compact #(
  parameter int unsigned NSYM = 32
) (
  input  logic [5:0]          cnt_i,
  input  logic [NSYM-1:0]     sdp_i,
  input  logic [NSYM-1:0]     stp_i,
  input  logic [NSYM-1:0]     end_i,
  input  logic [NSYM-1:0]     edb_i,
  input  logic [NSYM-1:0]     k_i,
  input  logic [8*NSYM-1:0]   data_i,
  input  logic                open_fin_i,
  input  logic [5:0]          h0_i,
  input  logic                end_pos0_v_i,
  input  logic [5:0]          end_pos0_i,
  input  logic                dllp_end0_v_i,
  input  logic [5:0]          dllp_end0_i,
  input  logic [1:0]          s1_drops_i,
  input  logic                found_i,
  input  logic [4:0]          s_idx_i,
  input  logic                end_pos1_v_i,
  input  logic [5:0]          end_pos1_i,
  input  logic                dllp_end1_v_i,
  input  logic [5:0]          dllp_end1_i,
  input  logic [1:0]          s2_drops_i,
  output logic [5:0]          cnt_o,
  output logic [NSYM-1:0]     sdp_o,
  output logic [NSYM-1:0]     stp_o,
  output logic [NSYM-1:0]     end_o,
  output logic [NSYM-1:0]     edb_o,
  output logic [NSYM-1:0]     k_o,
  output logic [8*NSYM-1:0]   data_o
);

  always_comb begin
    logic [31:0] sdp_w, stp_w, end_w, edb_w, k_w;
    logic [7:0]  data_b [0:35];
    logic [35:0] f_sdp, f_stp, f_end, f_edb, f_k;
    logic [7:0]  f_data [0:35];
    logic [5:0]  q_stp;

    sdp_w = '0;
    stp_w = '0;
    end_w = '0;
    edb_w = '0;
    k_w   = '0;
    sdp_w[NSYM-1:0] = sdp_i;
    stp_w[NSYM-1:0] = stp_i;
    end_w[NSYM-1:0] = end_i;
    edb_w[NSYM-1:0] = edb_i;
    k_w[NSYM-1:0]   = k_i;
    for (int unsigned i = 0; i < 36; i++)
      data_b[i] = (i < NSYM) ? data_i[8*i +: 8] : 8'h00;

    f_sdp = '0;
    f_stp = '0;
    f_end = '0;
    f_edb = '0;
    f_k   = '0;
    for (int unsigned d = 0; d < 36; d++)
      f_data[d] = data_b[d];

    for (int unsigned d = 0; d < 32; d++) begin
      if (6'(d) < cnt_i) begin
        f_k[d] = k_w[d];
        if (!open_fin_i || (6'(d) < h0_i)) begin
          if (end_pos0_v_i && (6'(d) == end_pos0_i)) begin
            f_end[d] = 1'b1;
          end else if (dllp_end0_v_i && (6'(d) == dllp_end0_i)) begin
            f_end[d] = end_w[d];
            f_edb[d] = edb_w[d];
          end
        end else if (!found_i || (6'(d) <= {1'b0, s_idx_i})) begin
          f_sdp[d] = sdp_w[d];
          f_stp[d] = stp_w[d];
          f_end[d] = end_w[d];
          f_edb[d] = edb_w[d];
        end else begin
          if (end_pos1_v_i && (6'(d) == end_pos1_i)) begin
            f_end[d] = 1'b1;
          end else if (dllp_end1_v_i && (6'(d) == dllp_end1_i)) begin
            f_end[d] = end_w[d];
            f_edb[d] = edb_w[d];
          end else if ((end_pos1_v_i && (6'(d) > end_pos1_i)) ||
                       (dllp_end1_v_i && (6'(d) > dllp_end1_i))) begin
            f_sdp[d] = sdp_w[d];
            f_stp[d] = stp_w[d];
            f_end[d] = end_w[d];
            f_edb[d] = edb_w[d];
          end
        end
      end
    end

    q_stp  = {1'b0, s_idx_i} - {4'd0, s1_drops_i};
    cnt_o  = cnt_i - {4'd0, s1_drops_i} - {4'd0, s2_drops_i};
    sdp_o  = '0;
    stp_o  = '0;
    end_o  = '0;
    edb_o  = '0;
    k_o    = '0;
    data_o = '0;

    for (int unsigned q = 0; q < NSYM; q++) begin
      if (6'(q) < cnt_o) begin
        automatic logic [2:0] sh;
        sh = {1'b0, s1_drops_i} +
             ((open_fin_i && found_i && (s2_drops_i != 2'd0) && (6'(q) > q_stp)) ?
              {1'b0, s2_drops_i} : 3'd0);
        unique case (sh)
          3'd0: begin
            sdp_o[q]          = f_sdp[q];
            stp_o[q]          = f_stp[q];
            end_o[q]          = f_end[q];
            edb_o[q]          = f_edb[q];
            k_o[q]            = f_k[q];
            data_o[8*q +: 8]  = f_data[q];
          end
          3'd1: begin
            sdp_o[q]          = f_sdp[q + 1];
            stp_o[q]          = f_stp[q + 1];
            end_o[q]          = f_end[q + 1];
            edb_o[q]          = f_edb[q + 1];
            k_o[q]            = f_k[q + 1];
            data_o[8*q +: 8]  = f_data[q + 1];
          end
          3'd2: begin
            sdp_o[q]          = f_sdp[q + 2];
            stp_o[q]          = f_stp[q + 2];
            end_o[q]          = f_end[q + 2];
            edb_o[q]          = f_edb[q + 2];
            k_o[q]            = f_k[q + 2];
            data_o[8*q +: 8]  = f_data[q + 2];
          end
          3'd3: begin
            sdp_o[q]          = f_sdp[q + 3];
            stp_o[q]          = f_stp[q + 3];
            end_o[q]          = f_end[q + 3];
            edb_o[q]          = f_edb[q + 3];
            k_o[q]            = f_k[q + 3];
            data_o[8*q +: 8]  = f_data[q + 3];
          end
          default: begin
            sdp_o[q]          = f_sdp[q + 4];
            stp_o[q]          = f_stp[q + 4];
            end_o[q]          = f_end[q + 4];
            edb_o[q]          = f_edb[q + 4];
            k_o[q]            = f_k[q + 4];
            data_o[8*q +: 8]  = f_data[q + 4];
          end
        endcase
      end
    end
  end
endmodule : rivet_mac_gf_compact

// Combinational wrapper pairing G0 meta + G1 compact for standalone unit tests.
module rivet_mac_gf_scan #(
  parameter int unsigned NSYM       = 32,
  parameter int unsigned DLLP_BYTES = 6
) (
  input  logic [2:0]          st_i,
  input  logic [15:0]         left_i,
  input  logic [5:0]          cnt_i,
  input  logic [NSYM-1:0]     sdp_i,
  input  logic [NSYM-1:0]     stp_i,
  input  logic [NSYM-1:0]     end_i,
  input  logic [NSYM-1:0]     edb_i,
  input  logic [NSYM-1:0]     k_i,
  input  logic [8*NSYM-1:0]   data_i,
  output logic [2:0]          st_o,
  output logic [15:0]         left_o,
  output logic [5:0]          cnt_o,
  output logic [NSYM-1:0]     sdp_o,
  output logic [NSYM-1:0]     stp_o,
  output logic [NSYM-1:0]     end_o,
  output logic [NSYM-1:0]     edb_o,
  output logic [NSYM-1:0]     k_o,
  output logic [8*NSYM-1:0]   data_o
);

  logic [31:0] tok_w;
  logic [31:0] l_hi_z_w;
  logic [31:0] l_hi6_z_w;
  logic [31:0] l_hi6_1_w;
  logic        left_hi_z_unused_w;
  logic        open_fin_w;
  logic [5:0]  h0_w;
  logic        end_pos0_v_w, dllp_end0_v_w;
  logic [5:0]  end_pos0_w, dllp_end0_w;
  logic [1:0]  s1_drops_w;
  logic        found_w;
  logic [4:0]  s_idx_w;
  logic        end_pos1_v_w, dllp_end1_v_w;
  logic [5:0]  end_pos1_w, dllp_end1_w;
  logic [1:0]  s2_drops_w;

  always_comb begin
    for (int unsigned d = 0; d < 32; d++) begin
      automatic logic [7:0] b0 = ((d + 1) < NSYM) ? data_i[8*(d + 1) +: 8] : 8'h00;
      automatic logic [7:0] b1 = ((d + 2) < NSYM) ? data_i[8*(d + 2) +: 8] : 8'h00;
      tok_w[d]     = (d < NSYM) && (6'(d) < cnt_i) && (stp_i[d] || sdp_i[d]);
      l_hi_z_w[d]  = (b1 == 8'h00) && (b0[7:5] == 3'b000);
      l_hi6_z_w[d] = (b1 == 8'h00) && (b0[7:6] == 2'b00);
      l_hi6_1_w[d] = (b1 == 8'h00) && (b0[7:6] == 2'b01);
    end
  end

  rivet_mac_gf_scan_meta #(
    .NSYM      (NSYM),
    .DLLP_BYTES(DLLP_BYTES)
  ) u_meta (
    .st_i         (st_i),
    .left_i       (left_i),
    .left_hi_z_i  (left_i[15:6] == 10'd0),
    .cnt_i        (cnt_i),
    .stp_i        (stp_i),
    .tok_i        (tok_w),
    .data_i       (data_i),
    .l_hi_z_i     (l_hi_z_w),
    .l_hi6_z_i    (l_hi6_z_w),
    .l_hi6_1_i    (l_hi6_1_w),
    .st_o         (st_o),
    .left_o       (left_o),
    .left_hi_z_o  (left_hi_z_unused_w),
    .open_fin_o   (open_fin_w),
    .h0_o         (h0_w),
    .end_pos0_v_o (end_pos0_v_w),
    .end_pos0_o   (end_pos0_w),
    .dllp_end0_v_o(dllp_end0_v_w),
    .dllp_end0_o  (dllp_end0_w),
    .s1_drops_o   (s1_drops_w),
    .found_o      (found_w),
    .s_idx_o      (s_idx_w),
    .end_pos1_v_o (end_pos1_v_w),
    .end_pos1_o   (end_pos1_w),
    .dllp_end1_v_o(dllp_end1_v_w),
    .dllp_end1_o  (dllp_end1_w),
    .s2_drops_o   (s2_drops_w)
  );

  rivet_mac_gf_compact #(
    .NSYM(NSYM)
  ) u_compact (
    .cnt_i        (cnt_i),
    .sdp_i        (sdp_i),
    .stp_i        (stp_i),
    .end_i        (end_i),
    .edb_i        (edb_i),
    .k_i          (k_i),
    .data_i       (data_i),
    .open_fin_i   (open_fin_w),
    .h0_i         (h0_w),
    .end_pos0_v_i (end_pos0_v_w),
    .end_pos0_i   (end_pos0_w),
    .dllp_end0_v_i(dllp_end0_v_w),
    .dllp_end0_i  (dllp_end0_w),
    .s1_drops_i   (s1_drops_w),
    .found_i      (found_w),
    .s_idx_i      (s_idx_w),
    .end_pos1_v_i (end_pos1_v_w),
    .end_pos1_i   (end_pos1_w),
    .dllp_end1_v_i(dllp_end1_v_w),
    .dllp_end1_i  (dllp_end1_w),
    .s2_drops_i   (s2_drops_w),
    .cnt_o        (cnt_o),
    .sdp_o        (sdp_o),
    .stp_o        (stp_o),
    .end_o        (end_o),
    .edb_o        (edb_o),
    .k_o          (k_o),
    .data_o       (data_o)
  );
endmodule : rivet_mac_gf_scan
