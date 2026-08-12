// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Gen2 LTSSM: Detect -> Polling -> Configuration -> L0.
// Encodings: rivet_pkg::rivet_ltssm_state_e (PG213 cfg_ltssm_state).
//
// MODE=EP/USP: Upstream Port Config (adopt Link# / Lane# from Downstream).
// MODE=RC/DSP: Downstream Port Config (offer Link# then assign Lane#).
//
// The link always trains at 2.5 GT/s regardless of GEN; 5.0 GT/s is reached
// only by entering Recovery.Speed from L0 (Base 2.1 §4.2.6.2.4), which is not
// implemented yet. Gen2 capability is still advertised in the TS Data Rate
// Identifier, which is what Configuration.Complete records on the peer side.
//
// Timeouts are parameters so simulation can shrink 12/24/48/2 ms to a few
// hundred cycles without touching the RTL.

module rivet_ltssm #(
  parameter int unsigned MODE  = 0,
  parameter int unsigned GEN   = 2,
  parameter int unsigned LANES = 1,

  parameter int unsigned T_DETECT_QUIET_CYC = rivet_pkg::RIVET_T_12MS_CYC,
  parameter int unsigned T_DETECT_RETRY_CYC = rivet_pkg::RIVET_T_12MS_CYC,
  parameter int unsigned T_POLL_ACTIVE_CYC  = rivet_pkg::RIVET_T_24MS_CYC,
  parameter int unsigned T_POLL_CFG_CYC     = rivet_pkg::RIVET_T_48MS_CYC,
  parameter int unsigned T_CONFIG_CYC       = rivet_pkg::RIVET_T_24MS_CYC,
  parameter int unsigned T_CFG_COMPLETE_CYC = rivet_pkg::RIVET_T_2MS_CYC,
  parameter int unsigned T_CFG_IDLE_CYC     = rivet_pkg::RIVET_T_2MS_CYC,
  parameter int unsigned T_RCVRLOCK_CYC     = rivet_pkg::RIVET_T_24MS_CYC,
  parameter int unsigned N_TS1_POLLING      = rivet_pkg::RIVET_N_TS1_POLLING,
  parameter logic [7:0]  N_FTS_ADV          = 8'hFF
) (
  input  logic pclk_i,
  input  logic rst_ni,

  // PHY status, fanned out of the PIPE adapter
  input  logic [LANES-1:0] phystatus_i,
  input  logic [LANES-1:0] rx_detected_i,
  input  logic [LANES-1:0] rxelecidle_i,
  input  logic [LANES-1:0] rxvalid_i,

  // Ordered-set reception (rivet_mac_os_rx)
  input  logic             ts1_pad_all_i,
  input  logic             ts1_pad_any_i,
  input  logic             ts2_pad_all_i,
  input  logic             ts2_pad_any_i,
  input  logic             ts1_link_all_i,
  input  logic             ts1_link_any_i,
  input  logic             ts1_lane_all_i,
  input  logic             ts1_lane_any_i,
  input  logic             ts2_cfg_all_i,
  input  logic             ts2_cfg_any_i,
  input  logic             idle_all_i,
  input  logic             idle_any_i,
  input  logic [7:0]       rx_link_num_i,
  input  logic [8*LANES-1:0] rx_lane_num_i,
  input  logic [7:0]       rx_rate_id_i,
  input  logic [7:0]       rx_n_fts_i,
  input  logic [LANES-1:0] polarity_inverted_i,
  input  logic             deskew_done_i,
  input  logic             rx_err_i,

  // Ordered-set transmission (rivet_mac_os_tx)
  output rivet_pkg::rivet_mac_os_type_e os_req_o,
  output logic                          os_req_valid_o,
  output logic                          os_cnt_clr_o,
  output logic [7:0]                    tx_link_num_o,
  output logic [8*LANES-1:0]            tx_lane_num_o,
  output logic                          tx_link_pad_o,
  output logic                          tx_lane_pad_o,
  output logic [7:0]                    tx_n_fts_o,
  output logic [7:0]                    tx_rate_id_o,
  output logic [7:0]                    tx_train_ctrl_o,
  input  logic [11:0]                   os_sent_cnt_i,
  output logic                          capture_clr_o,
  output logic [LANES-1:0]              lane_en_o,

  // PIPE command / assist (toward pipe adapter)
  output logic                    txdetectrx_o,
  output logic [LANES-1:0]        txelecidle_o,
  output logic [LANES-1:0]        rxpolarity_o,
  output logic [1:0]              powerdown_o,
  output logic [2:0]              rate_o,
  output logic                    as_mac_in_detect_o,
  output logic                    as_cdr_hold_req_o,
  output logic                    as_mac_in_L0_o,

  // Status toward DLL / user
  output rivet_pkg::rivet_ltssm_state_e ltssm_state_o,
  output logic                          link_up_o,
  output logic [2:0]                    negotiated_width_o,
  output logic [1:0]                    negotiated_speed_o,
  output logic                          accept_dll_tlp_o,
  output logic [7:0]                    remote_rate_id_o,
  output logic [7:0]                    remote_n_fts_o
);

  import rivet_pkg::*;

  // Cycles to transmit one TS on a 16-bit per-lane PIPE datapath. Used only by
  // the elaboration checks below, which catch scaled-down simulation timeouts
  // that are too short to ever satisfy the "N sent" exit conditions.
  localparam int unsigned CYC_PER_TS = RIVET_TS_LEN / 2;

`ifndef SYNTHESIS
  initial begin
    if (!(MODE == RIVET_MODE_EP || MODE == RIVET_MODE_RC ||
          MODE == RIVET_MODE_USP || MODE == RIVET_MODE_DSP))
      $error("rivet_ltssm: MODE must be EP/RC/USP/DSP (got %0d)", MODE);
    if (GEN != RIVET_GEN2)
      $error("rivet_ltssm: GEN=2 only (got %0d)", GEN);
    if (!rivet_lanes_legal(LANES))
      $error("rivet_ltssm LANES must be 1, 2, or 4");
    if (N_TS1_POLLING > 4095)
      $error("rivet_ltssm: N_TS1_POLLING must fit the 12-bit TX counter");
    if (T_POLL_ACTIVE_CYC <= (N_TS1_POLLING * CYC_PER_TS))
      $error("rivet_ltssm: T_POLL_ACTIVE_CYC=%0d cannot fit %0d TS1 (%0d cycles)",
             T_POLL_ACTIVE_CYC, N_TS1_POLLING, N_TS1_POLLING * CYC_PER_TS);
    if (T_POLL_CFG_CYC <= (RIVET_N_TS_AFTER_RX * CYC_PER_TS))
      $error("rivet_ltssm: T_POLL_CFG_CYC=%0d cannot fit %0d TS2",
             T_POLL_CFG_CYC, RIVET_N_TS_AFTER_RX);
    if (T_CFG_COMPLETE_CYC <= (RIVET_N_TS_AFTER_RX * CYC_PER_TS))
      $error("rivet_ltssm: T_CFG_COMPLETE_CYC=%0d cannot fit %0d TS2",
             T_CFG_COMPLETE_CYC, RIVET_N_TS_AFTER_RX);
  end
`endif

  // Downstream Port offers Link# / Lane#; Upstream adopts them.
  localparam bit IS_DOWNSTREAM =
      (MODE == RIVET_MODE_RC) || (MODE == RIVET_MODE_DSP);

  // Fixed Link number offered by Downstream Port Config (single-link soft IP).
  localparam logic [7:0] DP_LINK_NUM = 8'h00;

  // Sequential Lane numbers 0..n-1 (also the Downstream assignment).
  logic [8*LANES-1:0] default_lane_num;
  always_comb begin
    default_lane_num = '0;
    for (int unsigned l = 0; l < LANES; l++) default_lane_num[8*l +: 8] = 8'(l);
  end

  rivet_ltssm_state_e state_q, state_d;

  logic [LANES-1:0] lane_en_q,     lane_en_d;
  logic [LANES-1:0] detect_map_q,  detect_map_d;
  logic [LANES-1:0] detect_seen_q, detect_seen_d;
  logic [LANES-1:0] detect_prev_q, detect_prev_d;
  logic             detect_pass_q, detect_pass_d;
  logic             detect_wait_q, detect_wait_d;
  logic [7:0]       link_num_q,    link_num_d;
  logic [8*LANES-1:0] lane_num_q,  lane_num_d;
  logic             link_pad_q,    link_pad_d;
  logic             lane_pad_q,    lane_pad_d;
  logic [LANES-1:0] rxpolarity_q,  rxpolarity_d;
  logic             rx_seen_q,     rx_seen_d;
  logic             link_up_q,     link_up_d;
  logic             idle_to_rlock_q, idle_to_rlock_d;
  logic [7:0]       remote_rate_q, remote_rate_d;
  logic [7:0]       remote_nfts_q, remote_nfts_d;

  logic timer_expired;
  logic timer_load;
  logic [RIVET_LTSSM_TIMER_W-1:0] timer_limit;

  logic detect_done;
  logic detect_all;
  logic detect_none;
  logic lane_num_match;
  logic rxvalid_lost;
  logic state_change;

  assign detect_done = (detect_seen_q == {LANES{1'b1}});
  assign detect_all  = (detect_map_q  == {LANES{1'b1}});
  assign detect_none = (detect_map_q  == '0);

  always_comb begin
    lane_num_match = 1'b1;
    for (int unsigned l = 0; l < LANES; l++) begin
      if (lane_en_q[l] && (rx_lane_num_i[8*l +: 8] != lane_num_q[8*l +: 8]))
        lane_num_match = 1'b0;
    end
  end

  assign rxvalid_lost = ((rxvalid_i & lane_en_q) != lane_en_q);

  // ---------------------------------------------------------------------------
  // Next state and outputs
  // ---------------------------------------------------------------------------
  always_comb begin
    state_d         = state_q;
    lane_en_d       = lane_en_q;
    detect_map_d    = detect_map_q;
    detect_seen_d   = detect_seen_q;
    detect_prev_d   = detect_prev_q;
    detect_pass_d   = detect_pass_q;
    detect_wait_d   = detect_wait_q;
    link_num_d      = link_num_q;
    lane_num_d      = lane_num_q;
    link_pad_d      = link_pad_q;
    lane_pad_d      = lane_pad_q;
    rxpolarity_d    = rxpolarity_q;
    rx_seen_d       = rx_seen_q;
    link_up_d       = link_up_q;
    idle_to_rlock_d = idle_to_rlock_q;
    remote_rate_d   = remote_rate_q;
    remote_nfts_d   = remote_nfts_q;

    os_req_o           = RIVET_MAC_OS_NONE;
    txdetectrx_o       = 1'b0;
    powerdown_o        = RIVET_PIPE_P0;
    as_mac_in_detect_o = 1'b0;
    as_cdr_hold_req_o  = 1'b0;
    as_mac_in_L0_o     = 1'b0;
    accept_dll_tlp_o   = 1'b0;

    unique case (state_q)
      // ---------------------------------------------------------------- Detect
      RIVET_LTSSM_DETECT_QUIET: begin
        powerdown_o        = RIVET_PIPE_P1;
        as_mac_in_detect_o = 1'b1;
        link_up_d          = 1'b0;
        lane_en_d          = {LANES{1'b1}};
        detect_map_d       = '0;
        detect_seen_d      = '0;
        detect_prev_d      = '0;
        detect_pass_d      = 1'b0;
        detect_wait_d      = 1'b0;
        link_pad_d         = 1'b1;
        lane_pad_d         = 1'b1;
        rxpolarity_d       = '0;
        idle_to_rlock_d    = 1'b0;

        // 12 ms, or as soon as Electrical Idle is broken on any Lane.
        if (timer_expired || (rxelecidle_i != {LANES{1'b1}}))
          state_d = RIVET_LTSSM_DETECT_ACTIVE;
      end

      RIVET_LTSSM_DETECT_ACTIVE: begin
        powerdown_o        = RIVET_PIPE_P1;
        as_mac_in_detect_o = 1'b1;
        txdetectrx_o       = !detect_wait_q;

        if (detect_wait_q) begin
          // Partial detect: wait 12 ms, then repeat the detection sequence.
          if (timer_expired) begin
            detect_wait_d = 1'b0;
            detect_pass_d = 1'b1;
            detect_map_d  = '0;
            detect_seen_d = '0;
          end
        end else begin
          detect_seen_d = detect_seen_q | phystatus_i;
          detect_map_d  = detect_map_q  | rx_detected_i;

          if (detect_done) begin
            if (detect_all) begin
              lane_en_d = {LANES{1'b1}};
              state_d   = RIVET_LTSSM_POLLING_ACTIVE;
            end else if (detect_none) begin
              state_d = RIVET_LTSSM_DETECT_QUIET;
            end else if (!detect_pass_q) begin
              detect_prev_d = detect_map_q;
              detect_wait_d = 1'b1;
            end else if (detect_map_q == detect_prev_q) begin
              lane_en_d = detect_map_q;
              state_d   = RIVET_LTSSM_POLLING_ACTIVE;
            end else begin
              state_d = RIVET_LTSSM_DETECT_QUIET;
            end
          end
        end
      end

      // --------------------------------------------------------------- Polling
      RIVET_LTSSM_POLLING_ACTIVE: begin
        os_req_o = RIVET_MAC_OS_TS1; // Link and Lane numbers = PAD

        if (ts1_pad_all_i && (os_sent_cnt_i >= 12'(N_TS1_POLLING))) begin
          state_d = RIVET_LTSSM_POLLING_CONFIGURATION;
        end else if (timer_expired) begin
          // Relaxed 24 ms path: any Lane trained is enough to move on.
          state_d = (ts1_pad_any_i && (os_sent_cnt_i >= 12'(N_TS1_POLLING)))
                    ? RIVET_LTSSM_POLLING_CONFIGURATION
                    : RIVET_LTSSM_DETECT_QUIET;
        end
      end

      RIVET_LTSSM_POLLING_CONFIGURATION: begin
        os_req_o = RIVET_MAC_OS_TS2; // Link and Lane numbers = PAD

        // Receiver polarity inversion is decided here.
        rxpolarity_d = rxpolarity_q | polarity_inverted_i;

        if (ts2_pad_any_i) rx_seen_d = 1'b1;

        if (ts2_pad_any_i && rx_seen_q && (os_sent_cnt_i >= 12'(RIVET_N_TS_AFTER_RX)))
          state_d = RIVET_LTSSM_CFG_LINKWIDTH_START;
        else if (timer_expired)
          state_d = RIVET_LTSSM_DETECT_QUIET;
      end

      // --------------------------------------------------------- Configuration
      RIVET_LTSSM_CFG_LINKWIDTH_START: begin
        os_req_o = RIVET_MAC_OS_TS1;

        if (IS_DOWNSTREAM) begin
          // Downstream Port: offer a Link number with Lane# still PAD.
          link_num_d = DP_LINK_NUM;
          link_pad_d = 1'b0;
          if (ts1_link_all_i && (rx_link_num_i == DP_LINK_NUM))
            state_d = RIVET_LTSSM_CFG_LINKWIDTH_ACCEPT;
          else if (timer_expired)
            state_d = RIVET_LTSSM_DETECT_QUIET;
        end else begin
          // Upstream Port: adopt the Link number offered by the Downstream Port,
          // then transmit it with the Lane number still PAD.
          if (ts1_link_any_i) begin
            link_num_d = rx_link_num_i;
            link_pad_d = 1'b0;
            state_d    = RIVET_LTSSM_CFG_LINKWIDTH_ACCEPT;
          end else if (timer_expired) begin
            state_d = RIVET_LTSSM_DETECT_QUIET;
          end
        end
      end

      RIVET_LTSSM_CFG_LINKWIDTH_ACCEPT: begin
        os_req_o = RIVET_MAC_OS_TS1;

        if (IS_DOWNSTREAM) begin
          // Downstream Port: assign sequential Lane numbers on enabled Lanes.
          // Also accept TS2 with numbers — the Upstream Port may already have
          // raced into Configuration.Complete while we were still here.
          lane_num_d = default_lane_num;
          lane_pad_d = 1'b0;
          if (lane_num_match && (ts1_lane_all_i || ts2_cfg_all_i))
            state_d = RIVET_LTSSM_CFG_LANENUM_WAIT;
          else if (timer_expired)
            state_d = RIVET_LTSSM_DETECT_QUIET;
        end else begin
          if (ts1_lane_all_i) begin
            lane_num_d = rx_lane_num_i; // no Lane reversal in this milestone
            lane_pad_d = 1'b0;
            state_d    = RIVET_LTSSM_CFG_LANENUM_WAIT;
          end else if (timer_expired) begin
            state_d = RIVET_LTSSM_DETECT_QUIET;
          end
        end
      end

      RIVET_LTSSM_CFG_LANENUM_WAIT: begin
        os_req_o = RIVET_MAC_OS_TS1;

        // ts2_cfg: peer reached Complete first; numbers still latch in os_rx.
        if (lane_num_match && (ts1_lane_all_i || ts2_cfg_all_i)) begin
          state_d = RIVET_LTSSM_CFG_LANENUM_ACCEPT;
        end else if (ts1_lane_all_i && !lane_num_match) begin
          // Upstream may be told a new set; Downstream keeps its assignment.
          if (!IS_DOWNSTREAM) lane_num_d = rx_lane_num_i;
        end else if (timer_expired) begin
          state_d = RIVET_LTSSM_DETECT_QUIET;
        end
      end

      RIVET_LTSSM_CFG_LANENUM_ACCEPT: begin
        os_req_o = RIVET_MAC_OS_TS1;

        // Only act on fresh evidence, so a mismatch cannot ping-pong with
        // Lanenum.Wait at zero delay and reload the timeout forever.
        // Accept TS2 numbered sets so a peer that already entered Complete
        // cannot leave us stranded on TS1-only exits.
        if (lane_num_match && (ts1_lane_all_i || ts2_cfg_all_i)) begin
          state_d = RIVET_LTSSM_CFG_COMPLETE;
        end else if (ts1_lane_all_i && !lane_num_match) begin
          if (!IS_DOWNSTREAM) begin
            lane_num_d = rx_lane_num_i;
            state_d    = RIVET_LTSSM_CFG_LANENUM_WAIT;
          end
        end else if (timer_expired) begin
          state_d = RIVET_LTSSM_DETECT_QUIET;
        end
      end

      RIVET_LTSSM_CFG_COMPLETE: begin
        os_req_o = RIVET_MAC_OS_TS2;

        if (ts2_cfg_any_i) begin
          rx_seen_d     = 1'b1;
          remote_rate_d = rx_rate_id_i; // peer speed capability for Recovery
          remote_nfts_d = rx_n_fts_i;   // N_FTS to use when leaving L0s
        end

        if (ts2_cfg_all_i && rx_seen_q && deskew_done_i &&
            (os_sent_cnt_i >= 12'(RIVET_N_TS_AFTER_RX)))
          state_d = RIVET_LTSSM_CFG_IDLE;
        else if (timer_expired)
          state_d = RIVET_LTSSM_DETECT_QUIET;
      end

      RIVET_LTSSM_CFG_IDLE: begin
        os_req_o  = RIVET_MAC_OS_IDLE;
        link_up_d = 1'b1; // LinkUp is set here, not on L0 entry

        if (idle_any_i) rx_seen_d = 1'b1;

        if (idle_all_i && rx_seen_q && (os_sent_cnt_i >= 12'(RIVET_N_IDLE_TX))) begin
          state_d = RIVET_LTSSM_L0;
        end else if (timer_expired) begin
          if (!idle_to_rlock_q) begin
            idle_to_rlock_d = 1'b1;
            state_d         = RIVET_LTSSM_RECOVERY_RCVRLOCK;
          end else begin
            state_d = RIVET_LTSSM_DETECT_QUIET;
          end
        end
      end

      // -------------------------------------------------------------------- L0
      RIVET_LTSSM_L0: begin
        os_req_o         = RIVET_MAC_OS_IDLE; // DLL payload arrives with the DLL
        as_mac_in_L0_o   = 1'b1;
        accept_dll_tlp_o = 1'b1;

        if (rx_err_i || rxvalid_lost) state_d = RIVET_LTSSM_RECOVERY_RCVRLOCK;
      end

      // Minimal Recovery so timeouts and link errors cannot dead-end. The real
      // Recovery ladder (RcvrCfg / Idle / Speed) is a later milestone.
      RIVET_LTSSM_RECOVERY_RCVRLOCK: begin
        os_req_o = RIVET_MAC_OS_TS1;
        if (timer_expired) state_d = RIVET_LTSSM_DETECT_QUIET;
      end

      default: state_d = RIVET_LTSSM_DETECT_QUIET;
    endcase

    // Reset the "consecutive since entry" bookkeeping when the state changes.
    if (state_d != state_q) rx_seen_d = 1'b0;
  end

  assign state_change  = (state_d != state_q);
  assign capture_clr_o = state_change;
  assign os_cnt_clr_o  = state_change ||
                         (((state_q == RIVET_LTSSM_POLLING_CONFIGURATION) ||
                           (state_q == RIVET_LTSSM_CFG_COMPLETE) ||
                           (state_q == RIVET_LTSSM_CFG_IDLE)) && !rx_seen_q);

  // ---------------------------------------------------------------------------
  // Timeout counter (one shared instance; states are mutually exclusive)
  // ---------------------------------------------------------------------------
  always_comb begin
    unique case (state_d)
      RIVET_LTSSM_DETECT_QUIET:          timer_limit = T_DETECT_QUIET_CYC;
      RIVET_LTSSM_DETECT_ACTIVE:         timer_limit = T_DETECT_RETRY_CYC;
      RIVET_LTSSM_POLLING_ACTIVE:        timer_limit = T_POLL_ACTIVE_CYC;
      RIVET_LTSSM_POLLING_CONFIGURATION: timer_limit = T_POLL_CFG_CYC;
      RIVET_LTSSM_CFG_LINKWIDTH_START,
      RIVET_LTSSM_CFG_LINKWIDTH_ACCEPT,
      RIVET_LTSSM_CFG_LANENUM_ACCEPT,
      RIVET_LTSSM_CFG_LANENUM_WAIT:      timer_limit = T_CONFIG_CYC;
      RIVET_LTSSM_CFG_COMPLETE:          timer_limit = T_CFG_COMPLETE_CYC;
      RIVET_LTSSM_CFG_IDLE:              timer_limit = T_CFG_IDLE_CYC;
      RIVET_LTSSM_RECOVERY_RCVRLOCK:     timer_limit = T_RCVRLOCK_CYC;
      default:                           timer_limit = T_DETECT_QUIET_CYC;
    endcase
  end

  // Reload on entry, on the first cycle after reset (Detect.Quiet is entered by
  // reset, not by a transition), and when Detect.Active starts its retry wait.
  logic timer_init_q;

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) timer_init_q <= 1'b1;
    else         timer_init_q <= 1'b0;
  end

  assign timer_load = state_change || timer_init_q ||
                      (!detect_wait_q && detect_wait_d);

  rivet_mac_timer #(
    .WIDTH (RIVET_LTSSM_TIMER_W)
  ) u_timer (
    .pclk_i    (pclk_i),
    .rst_ni    (rst_ni),
    .load_i    (timer_load),
    .limit_i   (timer_limit),
    .expired_o (timer_expired)
  );

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= RIVET_LTSSM_DETECT_QUIET;
      lane_en_q       <= {LANES{1'b1}};
      detect_map_q    <= '0;
      detect_seen_q   <= '0;
      detect_prev_q   <= '0;
      detect_pass_q   <= 1'b0;
      detect_wait_q   <= 1'b0;
      link_num_q      <= '0;
      lane_num_q      <= '0;
      link_pad_q      <= 1'b1;
      lane_pad_q      <= 1'b1;
      rxpolarity_q    <= '0;
      rx_seen_q       <= 1'b0;
      link_up_q       <= 1'b0;
      idle_to_rlock_q <= 1'b0;
      remote_rate_q   <= '0;
      remote_nfts_q   <= '0;
    end else begin
      state_q         <= state_d;
      lane_en_q       <= lane_en_d;
      detect_map_q    <= detect_map_d;
      detect_seen_q   <= detect_seen_d;
      detect_prev_q   <= detect_prev_d;
      detect_pass_q   <= detect_pass_d;
      detect_wait_q   <= detect_wait_d;
      link_num_q      <= link_num_d;
      lane_num_q      <= lane_num_d;
      link_pad_q      <= link_pad_d;
      lane_pad_q      <= lane_pad_d;
      rxpolarity_q    <= rxpolarity_d;
      rx_seen_q       <= rx_seen_d;
      link_up_q       <= link_up_d;
      idle_to_rlock_q <= idle_to_rlock_d;
      remote_rate_q   <= remote_rate_d;
      remote_nfts_q   <= remote_nfts_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------
  logic in_detect;
  assign in_detect = (state_q == RIVET_LTSSM_DETECT_QUIET) ||
                     (state_q == RIVET_LTSSM_DETECT_ACTIVE);

  assign ltssm_state_o  = state_q;
  assign link_up_o      = link_up_q;
  assign lane_en_o      = lane_en_q;
  assign os_req_valid_o = (os_req_o != RIVET_MAC_OS_NONE);

  // Transmitter is in Electrical Idle through Detect and on unused Lanes.
  assign txelecidle_o = in_detect ? {LANES{1'b1}} : ~lane_en_q;
  assign rxpolarity_o = rxpolarity_q;

  // Training runs at 2.5 GT/s; Recovery.Speed will make this stateful.
  assign rate_o             = RIVET_PIPE_RATE_GEN1;
  assign negotiated_speed_o = 2'b00; // 2.5 GT/s

  assign tx_link_num_o   = link_num_q;
  assign tx_lane_num_o   = lane_pad_q ? default_lane_num : lane_num_q;
  assign tx_link_pad_o   = link_pad_q;
  assign tx_lane_pad_o   = lane_pad_q;
  assign tx_n_fts_o      = N_FTS_ADV;
  assign tx_rate_id_o    = (GEN >= 2) ? RIVET_TS_RATE_GEN2 : RIVET_TS_RATE_GEN1;
  assign tx_train_ctrl_o = 8'h00;

  assign remote_rate_id_o = remote_rate_q;
  assign remote_n_fts_o   = remote_nfts_q;

  always_comb begin
    negotiated_width_o = '0;
    for (int unsigned l = 0; l < LANES; l++) begin
      if (lane_en_q[l]) negotiated_width_o = negotiated_width_o + 3'd1;
    end
  end

  // Reserved for the multi-lane milestone, where per-lane "all vs any" matters.
  logic _unused_ok;
  assign _unused_ok = ts2_pad_all_i ^ ts1_link_all_i ^ ts1_lane_any_i;

endmodule : rivet_ltssm
