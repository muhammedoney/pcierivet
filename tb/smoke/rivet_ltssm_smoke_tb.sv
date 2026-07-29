// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Smoke test: drive rivet_pcie_ctrl from a minimal PIPE peer and check that the
// LTSSM walks Detect -> Polling -> Configuration -> L0.
//
// The peer is deliberately written by hand rather than reusing rivet_mac_os_tx,
// so a mistake in the TS symbol layout cannot cancel itself out. It reacts to
// what the DUT transmits, the way a Root Port reacts on the wire, and never
// looks inside the DUT.
//
// This is a fast pre-UVM gate, not a replacement for the UVM environment.

`timescale 1ns/1ps

module rivet_ltssm_smoke_tb;

`ifndef RIVET_SMOKE_LANES
  `define RIVET_SMOKE_LANES 1
`endif

  localparam int unsigned LANES = `RIVET_SMOKE_LANES;
  localparam int unsigned PIPE_W = 16;
  localparam int unsigned AXI_W  = 64;
  localparam int unsigned KEEP_W = AXI_W / 32;

  localparam int unsigned LTSSM_TIMER_SCALE = 500;
  localparam int unsigned N_TS1_POLLING     = 32;
  localparam int unsigned WATCHDOG_CYCLES   = 200_000;

  // TS / control symbols (Base 2.1 Tables 4-2/4-3)
  localparam logic [7:0] SYM_COM    = 8'hBC;
  localparam logic [7:0] SYM_PAD    = 8'hF7;
  localparam logic [7:0] SYM_TS1_ID = 8'h4A;
  localparam logic [7:0] SYM_TS2_ID = 8'h45;
  localparam logic [7:0] PEER_LINK  = 8'h00;
  localparam logic [7:0] PEER_NFTS  = 8'h00;
  localparam logic [7:0] PEER_RATE  = 8'h06; // 2.5 + 5.0 GT/s advertised

  localparam logic [5:0] LTSSM_L0 = 6'h10;

  logic pclk;
  logic user_clk;
  logic preset_n;
  logic user_resetn;

  initial begin
    pclk = 1'b0;
    forever #2 pclk = ~pclk;
  end

  initial begin
    user_clk = 1'b0;
    forever #4 user_clk = ~user_clk;
  end

  initial begin
    preset_n    = 1'b0;
    user_resetn = 1'b0;
    repeat (10) @(posedge pclk);
    preset_n    = 1'b1;
    user_resetn = 1'b1;
  end

  // ---------------------------------------------------------------------------
  // DUT PIPE nets
  // ---------------------------------------------------------------------------
  logic [PIPE_W*LANES-1:0] pipe_txdata;
  logic [2*LANES-1:0]      pipe_txdatak;
  logic [LANES-1:0]        pipe_txdata_valid;
  logic [LANES-1:0]        pipe_txstart_block;
  logic [2*LANES-1:0]      pipe_txsync_header;
  logic [PIPE_W*LANES-1:0] pipe_rxdata;
  logic [2*LANES-1:0]      pipe_rxdatak;
  logic [LANES-1:0]        pipe_rxdata_valid;
  logic [2*LANES-1:0]      pipe_rxstart_block;
  logic [2*LANES-1:0]      pipe_rxsync_header;
  logic                    pipe_txdetectrx;
  logic [LANES-1:0]        pipe_txelecidle;
  logic [LANES-1:0]        pipe_txcompliance;
  logic [LANES-1:0]        pipe_rxpolarity;
  logic [1:0]              pipe_powerdown;
  logic [2:0]              pipe_rate;
  logic [LANES-1:0]        pipe_rxvalid;
  logic [LANES-1:0]        pipe_phystatus;
  logic [LANES-1:0]        pipe_phystatus_rst;
  logic [LANES-1:0]        pipe_rxelecidle;
  logic [3*LANES-1:0]      pipe_rxstatus;
  logic [2:0]              pipe_txmargin;
  logic                    pipe_txswing;
  logic                    pipe_txdeemph;
  logic [2*LANES-1:0]      pipe_txeq_ctrl;
  logic [4*LANES-1:0]      pipe_txeq_preset;
  logic [6*LANES-1:0]      pipe_txeq_coeff;
  logic [2*LANES-1:0]      pipe_rxeq_ctrl;
  logic [4*LANES-1:0]      pipe_rxeq_txpreset;
  logic                    pipe_as_mac_in_detect;
  logic                    pipe_as_cdr_hold_req;
  logic                    pipe_as_mac_in_L0;
  logic [1:0]              pipe_cfg_rx_pm_state;

  logic [5:0] cfg_ltssm_state;
  logic       link_up;

  // Unused user-side nets
  logic [AXI_W-1:0]  m_axis_cq_tdata,  m_axis_rc_tdata;
  logic [KEEP_W-1:0] m_axis_cq_tkeep,  m_axis_rc_tkeep;
  logic              m_axis_cq_tlast,  m_axis_rc_tlast;
  logic              m_axis_cq_tvalid, m_axis_rc_tvalid;
  logic [87:0]       m_axis_cq_tuser;
  logic [74:0]       m_axis_rc_tuser;
  logic [3:0]        s_axis_cc_tready, s_axis_rq_tready;
  logic [5:0]        pcie_cq_np_req_count, pcie_rq_seq_num0;
  logic              pcie_rq_seq_num_vld0;
  logic [9:0]        pcie_rq_tag0, pcie_rq_tag1;
  logic              pcie_rq_tag_vld0, pcie_rq_tag_vld1;
  logic [3:0]        pcie_rq_tag_av, pcie_tfc_nph_av, pcie_tfc_npd_av;
  logic [31:0]       cfg_mgmt_read_data;
  logic              cfg_mgmt_read_write_done;

  rivet_pcie_ctrl #(
    .MODE              (0),
    .GEN               (2),
    .LANES             (LANES),
    .AXI_DATA_WIDTH    (AXI_W),
    .PIPE_DATA_WIDTH   (PIPE_W),
    .LTSSM_TIMER_SCALE (LTSSM_TIMER_SCALE),
    .N_TS1_POLLING     (N_TS1_POLLING)
  ) dut (
    .user_clk                 (user_clk),
    .user_resetn              (user_resetn),
    .pclk                     (pclk),
    .preset_n                 (preset_n),

    .m_axis_cq_tdata          (m_axis_cq_tdata),
    .m_axis_cq_tkeep          (m_axis_cq_tkeep),
    .m_axis_cq_tlast          (m_axis_cq_tlast),
    .m_axis_cq_tvalid         (m_axis_cq_tvalid),
    .m_axis_cq_tready         (1'b1),
    .m_axis_cq_tuser          (m_axis_cq_tuser),

    .s_axis_cc_tdata          ('0),
    .s_axis_cc_tkeep          ('0),
    .s_axis_cc_tlast          (1'b0),
    .s_axis_cc_tvalid         (1'b0),
    .s_axis_cc_tready         (s_axis_cc_tready),
    .s_axis_cc_tuser          ('0),

    .s_axis_rq_tdata          ('0),
    .s_axis_rq_tkeep          ('0),
    .s_axis_rq_tlast          (1'b0),
    .s_axis_rq_tvalid         (1'b0),
    .s_axis_rq_tready         (s_axis_rq_tready),
    .s_axis_rq_tuser          ('0),

    .m_axis_rc_tdata          (m_axis_rc_tdata),
    .m_axis_rc_tkeep          (m_axis_rc_tkeep),
    .m_axis_rc_tlast          (m_axis_rc_tlast),
    .m_axis_rc_tvalid         (m_axis_rc_tvalid),
    .m_axis_rc_tready         (1'b1),
    .m_axis_rc_tuser          (m_axis_rc_tuser),

    .pcie_cq_np_req           (2'b01),
    .pcie_cq_np_req_count     (pcie_cq_np_req_count),
    .pcie_rq_seq_num0         (pcie_rq_seq_num0),
    .pcie_rq_seq_num_vld0     (pcie_rq_seq_num_vld0),
    .pcie_rq_tag0             (pcie_rq_tag0),
    .pcie_rq_tag_vld0         (pcie_rq_tag_vld0),
    .pcie_rq_tag1             (pcie_rq_tag1),
    .pcie_rq_tag_vld1         (pcie_rq_tag_vld1),
    .pcie_rq_tag_av           (pcie_rq_tag_av),
    .pcie_tfc_nph_av          (pcie_tfc_nph_av),
    .pcie_tfc_npd_av          (pcie_tfc_npd_av),

    .cfg_mgmt_addr            ('0),
    .cfg_mgmt_function_number ('0),
    .cfg_mgmt_write           (1'b0),
    .cfg_mgmt_write_data      ('0),
    .cfg_mgmt_byte_enable     ('0),
    .cfg_mgmt_read            (1'b0),
    .cfg_mgmt_read_data       (cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done (cfg_mgmt_read_write_done),
    .cfg_mgmt_debug_access    (1'b0),

    .pipe_txdata              (pipe_txdata),
    .pipe_txdatak             (pipe_txdatak),
    .pipe_txdata_valid        (pipe_txdata_valid),
    .pipe_txstart_block       (pipe_txstart_block),
    .pipe_txsync_header       (pipe_txsync_header),
    .pipe_rxdata              (pipe_rxdata),
    .pipe_rxdatak             (pipe_rxdatak),
    .pipe_rxdata_valid        (pipe_rxdata_valid),
    .pipe_rxstart_block       (pipe_rxstart_block),
    .pipe_rxsync_header       (pipe_rxsync_header),
    .pipe_txdetectrx          (pipe_txdetectrx),
    .pipe_txelecidle          (pipe_txelecidle),
    .pipe_txcompliance        (pipe_txcompliance),
    .pipe_rxpolarity          (pipe_rxpolarity),
    .pipe_powerdown           (pipe_powerdown),
    .pipe_rate                (pipe_rate),
    .pipe_rxvalid             (pipe_rxvalid),
    .pipe_phystatus           (pipe_phystatus),
    .pipe_phystatus_rst       (pipe_phystatus_rst),
    .pipe_rxelecidle          (pipe_rxelecidle),
    .pipe_rxstatus            (pipe_rxstatus),
    .pipe_txmargin            (pipe_txmargin),
    .pipe_txswing             (pipe_txswing),
    .pipe_txdeemph            (pipe_txdeemph),
    .pipe_txeq_ctrl           (pipe_txeq_ctrl),
    .pipe_txeq_preset         (pipe_txeq_preset),
    .pipe_txeq_coeff          (pipe_txeq_coeff),
    .pipe_txeq_fs             ('0),
    .pipe_txeq_lf             ('0),
    .pipe_txeq_new_coeff      ('0),
    .pipe_txeq_done           ('0),
    .pipe_rxeq_ctrl           (pipe_rxeq_ctrl),
    .pipe_rxeq_txpreset       (pipe_rxeq_txpreset),
    .pipe_rxeq_preset_sel     ('0),
    .pipe_rxeq_new_txcoeff    ('0),
    .pipe_rxeq_adapt_done     ('0),
    .pipe_rxeq_done           ('0),
    .pipe_as_mac_in_detect    (pipe_as_mac_in_detect),
    .pipe_as_cdr_hold_req     (pipe_as_cdr_hold_req),
    .pipe_as_mac_in_L0        (pipe_as_mac_in_L0),
    .pipe_cfg_rx_pm_state     (pipe_cfg_rx_pm_state),

    .cfg_ltssm_state          (cfg_ltssm_state),
    .link_up                  (link_up)
  );

  assign pipe_rxdata_valid  = '0; // Gen3+
  assign pipe_rxstart_block = '0;
  assign pipe_rxsync_header = '0;
  assign pipe_phystatus_rst = '0;

  // ---------------------------------------------------------------------------
  // What is the DUT transmitting? Only wire-visible symbols are inspected.
  // ---------------------------------------------------------------------------
  logic dut_tx_ts1, dut_tx_ts2, dut_tx_k, dut_tx_data_only;

  always_comb begin
    dut_tx_ts1 = 1'b0;
    dut_tx_ts2 = 1'b0;
    dut_tx_k   = 1'b0;
    for (int unsigned l = 0; l < LANES; l++) begin
      for (int unsigned s = 0; s < 2; s++) begin
        if (pipe_txdatak[2*l + s]) begin
          dut_tx_k = 1'b1;
        end else begin
          if (pipe_txdata[PIPE_W*l + 8*s +: 8] == SYM_TS1_ID) dut_tx_ts1 = 1'b1;
          if (pipe_txdata[PIPE_W*l + 8*s +: 8] == SYM_TS2_ID) dut_tx_ts2 = 1'b1;
        end
      end
    end
  end

  assign dut_tx_data_only = !dut_tx_k && !dut_tx_ts1 && !dut_tx_ts2 &&
                            (pipe_txelecidle == '0);

  // ---------------------------------------------------------------------------
  // Receiver detection: PhyStatus pulse with RxStatus = 011
  // ---------------------------------------------------------------------------
  logic [3:0] detect_cnt;
  logic       detect_ack;
  logic       peer_active;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      detect_cnt     <= '0;
      detect_ack     <= 1'b0;
      peer_active    <= 1'b0;
      pipe_phystatus <= '0;
      pipe_rxstatus  <= '0;
      pipe_rxvalid   <= '0;
      pipe_rxelecidle <= '1;
    end else begin
      pipe_phystatus <= '0;
      pipe_rxstatus  <= '0;

      if (pipe_txdetectrx && (pipe_powerdown == 2'b10) && !detect_ack) begin
        detect_cnt <= detect_cnt + 4'd1;
        if (detect_cnt == 4'd4) begin
          detect_ack     <= 1'b1;
          pipe_phystatus <= '1;
          for (int unsigned l = 0; l < LANES; l++) pipe_rxstatus[3*l +: 3] <= 3'b011;
        end
      end

      // Once detected, the peer transmitter comes out of Electrical Idle and the
      // receiver reports symbol lock.
      if (detect_ack) begin
        peer_active     <= 1'b1;
        pipe_rxvalid    <= '1;
        pipe_rxelecidle <= '0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Peer ordered-set transmitter and phase machine
  // ---------------------------------------------------------------------------
  typedef enum int unsigned {
    P_TS1_PAD,   // Polling.Active partner
    P_TS2_PAD,   // Polling.Configuration partner
    P_TS1_LINK,  // offer a Link number, Lane still PAD
    P_TS1_LANE,  // offer Lane numbers
    P_TS2_CFG,   // Configuration.Complete partner
    P_IDLE       // logical Idle
  } peer_phase_e;

  peer_phase_e phase;
  logic [4:0]  peer_ptr;
  logic [11:0] phase_sets;
  logic [7:0]  idle_seen;

  function automatic logic [8:0] peer_sym(input logic [3:0] idx,
                                          input bit          ts2,
                                          input bit          link_pad,
                                          input bit          lane_pad,
                                          input logic [7:0]  lane);
    case (idx)
      4'd0:    return {1'b1, SYM_COM};
      4'd1:    return link_pad ? {1'b1, SYM_PAD} : {1'b0, PEER_LINK};
      4'd2:    return lane_pad ? {1'b1, SYM_PAD} : {1'b0, lane};
      4'd3:    return {1'b0, PEER_NFTS};
      4'd4:    return {1'b0, PEER_RATE};
      4'd5:    return {1'b0, 8'h00};
      default: return ts2 ? {1'b0, SYM_TS2_ID} : {1'b0, SYM_TS1_ID};
    endcase
  endfunction

  logic send_ts2, send_link_pad, send_lane_pad, send_os;

  always_comb begin
    send_ts2      = (phase == P_TS2_PAD) || (phase == P_TS2_CFG);
    send_link_pad = (phase == P_TS1_PAD) || (phase == P_TS2_PAD);
    send_lane_pad = (phase != P_TS1_LANE) && (phase != P_TS2_CFG);
    send_os       = peer_active && (phase != P_IDLE);
  end

  logic [8:0] peer_tmp;

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
      phase        <= P_TS1_PAD;
      peer_ptr     <= '0;
      phase_sets   <= '0;
      idle_seen    <= '0;
      pipe_rxdata  <= '0;
      pipe_rxdatak <= '0;
    end else begin
      // Drive two symbols per cycle on every lane.
      pipe_rxdata  <= '0;
      pipe_rxdatak <= '0;
      if (peer_active) begin
        for (int unsigned l = 0; l < LANES; l++) begin
          for (int unsigned s = 0; s < 2; s++) begin
            peer_tmp = send_os ? peer_sym(4'(peer_ptr + 5'(s)), send_ts2,
                                          send_link_pad, send_lane_pad, 8'(l))
                               : {1'b0, 8'h00};
            pipe_rxdata[PIPE_W*l + 8*s +: 8] <= peer_tmp[7:0];
            pipe_rxdatak[2*l + s]            <= peer_tmp[8];
          end
        end

        if (send_os) begin
          if (peer_ptr >= 5'd14) begin
            peer_ptr   <= '0;
            phase_sets <= phase_sets + 12'd1;
          end else begin
            peer_ptr <= peer_ptr + 5'd2;
          end
        end
      end

      // Follow the DUT: react to the ordered set it is sending.
      case (phase)
        P_TS1_PAD: if (dut_tx_ts2) begin
          phase      <= P_TS2_PAD;
          phase_sets <= '0;
          peer_ptr   <= '0;
        end
        P_TS2_PAD: if (dut_tx_ts1) begin
          phase      <= P_TS1_LINK;
          phase_sets <= '0;
          peer_ptr   <= '0;
        end
        // Give the DUT room to reach Linkwidth.Accept before Lane numbers appear.
        P_TS1_LINK: if (phase_sets >= 12'd16) begin
          phase      <= P_TS1_LANE;
          phase_sets <= '0;
          peer_ptr   <= '0;
        end
        P_TS1_LANE: if (dut_tx_ts2) begin
          phase      <= P_TS2_CFG;
          phase_sets <= '0;
          peer_ptr   <= '0;
        end
        P_TS2_CFG: begin
          if (dut_tx_data_only) idle_seen <= idle_seen + 8'd1;
          else                  idle_seen <= '0;
          if (idle_seen >= 8'd4) phase <= P_IDLE;
        end
        default: ; // P_IDLE: keep sending Idle data
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------
  logic [5:0] state_prev;
  int unsigned cycles;
  bit          reached_l0;

  initial begin
    state_prev = 6'h3F;
    reached_l0 = 1'b0;
    cycles     = 0;
  end

  always @(posedge pclk) begin
    if (preset_n) begin
      cycles = cycles + 1;

      if (cfg_ltssm_state != state_prev) begin
        $display("[%0t] LTSSM 0x%02h -> 0x%02h (link_up=%0b)",
                 $time, state_prev, cfg_ltssm_state, link_up);
        state_prev = cfg_ltssm_state;
      end

      // Training must stay at 2.5 GT/s; Gen2 is only reachable via Recovery.
      if (pipe_rate != 3'd0) begin
        $error("rate must be 2.5 GT/s during training, saw %0d", pipe_rate);
        $finish;
      end

      if ((cfg_ltssm_state == LTSSM_L0) && !reached_l0) begin
        reached_l0 = 1'b1;
        if (!link_up) begin
          $error("L0 reached without link_up");
          $finish;
        end
        $display("PASS: LANES=%0d reached L0 in %0d pclk cycles", LANES, cycles);
        repeat (200) @(posedge pclk);
        if (cfg_ltssm_state != LTSSM_L0) begin
          $error("left L0 unexpectedly (state 0x%02h)", cfg_ltssm_state);
          $finish;
        end
        $display("PASS: stayed in L0");
        $finish;
      end

      if (cycles > WATCHDOG_CYCLES) begin
        $error("TIMEOUT: LTSSM stuck at 0x%02h after %0d cycles",
               cfg_ltssm_state, cycles);
        $finish;
      end
    end
  end

endmodule : rivet_ltssm_smoke_tb
