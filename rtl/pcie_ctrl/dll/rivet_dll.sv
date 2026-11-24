// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Data Link Layer top: FC + DL SM + streaming TL hook + TLP seq/LCRC +
// ACK/NAK + replay (D5).
// Boundary streams (dll_tx, dll_rx, tl_tx, tl_rx) pass through 2-entry
// registered skid buffers so valid/data and ready have no cross-layer
// combinational feedthrough at 250 MHz.

module rivet_dll #(
  parameter int unsigned LANES             = 1,
  parameter int unsigned PIPE_DATA_WIDTH   = 16,
  parameter int unsigned INITFC_GAP_CYC    = 8,
  parameter int unsigned UPDATEFC_GAP_CYC  = 32,
  parameter int unsigned REPLAY_TLP_SLOTS  = 16,
  parameter int unsigned REPLAY_SLOT_BYTES = 4128,
  // RX frame cap. The bytes live in a word RAM, not a wide vector.
  parameter int unsigned RX_SLOT_BYTES     = 4128,
  // Starts at push, and a new push reloads it, so it must cover a max
  // frame already in the MAC plus the one just pushed. Collect is one
  // 8-byte beat per pclk. Gen2 16-bit PIPE then shifts LANES*2 bytes
  // per pclk. The pad is the ACK turnaround.
  parameter int unsigned REPLAY_TIMER_CYC  =
      2 * (((REPLAY_SLOT_BYTES + 7) / 8) +
           ((REPLAY_SLOT_BYTES + (LANES * 2) - 1) / (LANES * 2))) + 256,
  parameter int unsigned REPLAY_NUM_LIMIT  = 3,
  parameter int unsigned TL_DATA_W         = rivet_pkg::RIVET_TL_DLL_DATA_W,
  // TX beat width. 64 keeps the 8-byte transmitter. 128 streams 16 bytes.
  parameter int unsigned TX_DATA_W         = rivet_pkg::RIVET_TL_DLL_DATA_W
) (
  input  logic pclk_i,
  input  logic rst_ni,

  output rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_o,
  output logic                              dll_tx_valid_o,
  input  logic                              dll_tx_ready_i,
  input  rivet_pkg::rivet_dll_mac_rx_beat_t dll_rx_beat_i,
  input  logic                              dll_rx_valid_i,
  output logic                              dll_rx_ready_o,
  input  rivet_pkg::rivet_mac_dll_sb_t      mac_to_dll_sb_i,
  output rivet_pkg::rivet_dll_mac_sb_t      dll_to_mac_sb_o,

  input  rivet_pkg::rivet_tl_dll_fc_sb_t    tl_to_dll_fc_i,
  output rivet_pkg::rivet_dll_tl_fc_sb_t    dll_to_tl_fc_o,

  // TL <-> DLL TLP stream (payload only; seq/LCRC added/stripped in DLL)
  input  logic [TX_DATA_W-1:0]              tl_tx_tdata_i,
  input  logic [TX_DATA_W/8-1:0]            tl_tx_tkeep_i,
  input  logic                              tl_tx_tlast_i,
  input  logic                              tl_tx_tvalid_i,
  output logic                              tl_tx_tready_o,

  output logic [TL_DATA_W-1:0]              tl_rx_tdata_o,
  output logic [TL_DATA_W/8-1:0]            tl_rx_tkeep_o,
  output logic                              tl_rx_tlast_o,
  output logic                              tl_rx_tvalid_o,
  input  logic                              tl_rx_tready_i,
  output logic [11:0]                       tl_rx_seq_o,
  output logic                              tl_rx_abort_o
);

  import rivet_pkg::*;

  localparam int unsigned TL_KEEP_W = TL_DATA_W / 8;
  localparam int unsigned TX_KEEP_W = TX_DATA_W / 8;

`ifndef SYNTHESIS
  initial begin
    if (!rivet_lanes_legal(LANES))
      $error("rivet_dll LANES must be 1, 2, or 4");
  end
`endif

  rivet_dllp_req_t fc_req;
  logic            fc_req_valid;
  logic            fc_req_ready;

  rivet_dllp_dec_t dec;
  logic            dec_valid;
  logic            dec_ready;

  rivet_dll_tl_fc_sb_t fc_sb;
  rivet_dl_state_e     dl_state;
  logic                dl_up;
  logic                tlp_tx_en;
  logic                replay_en;
  logic                fc_en;
  logic                replay_req;
  logic                replay_done;

  rivet_dllp_req_t ack_req;
  logic            ack_valid;
  logic            ack_ready;

  rivet_dllp_req_t dllp_req;
  logic            dllp_req_valid;
  logic            dllp_req_ready;

  logic        cap_v, cap_r, cap_last;
  logic [63:0] cap_data;
  logic [11:0] cap_seq;
  logic [15:0] cap_len;
  logic                           rep_start, rep_active, rep_v, rep_r;
  logic [11:0]                    rep_seq;
  logic [63:0]                    rep_word;
  logic [15:0]                    rep_word_idx;
  logic [15:0]                    rep_len;
  logic [15:0]                    tx_word_idx;
  logic [TX_DATA_W-1:0]           tx_word;
  logic                           cap_hi_v;
  logic [63:0]                    cap_hi_d;
  logic                           rep_full, rep_empty;
  logic [15:0]                    rep_occ;

  logic        ack_to_buf;
  logic [11:0] ack_seq_to_buf;
  logic        nak_pulse;
  logic        timer_fire;
  logic        clear_replay;

  logic [15:0] timer_q;
  logic [3:0]  replay_num_q;
  logic        timer_en_q;
  logic        nak_storm_q;
  logic        timer_exp_q;
  logic        replay_pend_q;
  logic        tx_idle;

  rivet_dll_mac_tx_beat_t dllp_beat, tlp_beat, mux_tx_beat;
  logic                   dllp_v, tlp_v, dllp_r, tlp_r;
  logic                   mux_tx_v, mux_tx_r;
  logic                   dllp_hold_ack_q;
  logic                   tlp_in_pkt_q;
  logic                   present_dllp;
  logic [11:0]            next_tx_seq;

  rivet_dll_mac_rx_beat_t rx_skid_beat;
  logic                   rx_skid_v, rx_skid_r;
  logic                   dllp_rx_v, tlp_rx_v, dllp_rx_r, tlp_rx_r;
  logic                   rx_is_dllp, rx_is_tlp;
  logic                   rx_enable_q;
  logic [11:0]            last_good;
  logic                   lcrc_err;

  logic        whole_tx_v, whole_tx_r, whole_tx_last;
  logic [15:0] whole_tx_len;

  // Skid wires for TL <-> DLL streams
  logic [TX_DATA_W-1:0]  tl_tx_s_tdata;
  logic [TX_KEEP_W-1:0]  tl_tx_s_tkeep;
  logic                  tl_tx_s_tlast, tl_tx_s_tvalid, tl_tx_s_tready;

  logic [TL_DATA_W-1:0]  tl_rx_u_tdata;
  logic [TL_KEEP_W-1:0]  tl_rx_u_tkeep;
  logic                  tl_rx_u_tlast, tl_rx_u_tvalid, tl_rx_u_tready;
  logic [11:0]           tl_rx_u_seq;

  assign clear_replay = !mac_to_dll_sb_i.accept_dll_tlp;
  assign dec_ready    = 1'b1;

  assign ack_to_buf     = dec_valid && dec.crc_ok && (dec.kind == RIVET_DLLP_KIND_ACK);
  assign ack_seq_to_buf = dec.ack_seq;
  assign nak_pulse      = dec_valid && dec.crc_ok && (dec.kind == RIVET_DLLP_KIND_NAK);

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      timer_q      <= '0;
      timer_en_q   <= 1'b0;
      replay_num_q <= '0;
      nak_storm_q  <= 1'b0;
      timer_exp_q    <= 1'b0;
      replay_pend_q  <= 1'b0;
      rx_enable_q    <= 1'b0;
    end else begin
      rx_enable_q <= mac_to_dll_sb_i.accept_dll_tlp && (dl_state == RIVET_DL_ACTIVE);

      if (clear_replay) begin
        timer_q       <= '0;
        timer_en_q    <= 1'b0;
        replay_num_q  <= '0;
        nak_storm_q   <= 1'b0;
        timer_exp_q   <= 1'b0;
        replay_pend_q <= 1'b0;
      end else begin
        timer_exp_q <= 1'b0;

        if (cap_v && cap_last && cap_r) begin
          timer_en_q <= 1'b1;
          timer_q    <= REPLAY_TIMER_CYC[15:0];
        end else if (ack_to_buf) begin
          replay_num_q <= '0;
          timer_en_q   <= 1'b1;
          timer_q      <= REPLAY_TIMER_CYC[15:0];
        end else if (rep_empty && timer_en_q) begin
          timer_en_q <= 1'b0;
          timer_q    <= '0;
        end else if (rep_active) begin
          timer_en_q <= 1'b0;
          timer_q    <= '0;
        end else if (timer_en_q && (timer_q != 16'd0)) begin
          timer_q <= timer_q - 16'd1;
          if (timer_q == 16'd1) begin
            timer_exp_q  <= 1'b1;
            timer_en_q   <= 1'b0;
            replay_num_q <= replay_num_q + 4'd1;
            if ((replay_num_q + 4'd1) >= REPLAY_NUM_LIMIT[3:0])
              nak_storm_q <= 1'b1;
          end
        end

        if (nak_pulse && !rep_empty) begin
          replay_num_q <= replay_num_q + 4'd1;
          if ((replay_num_q + 4'd1) >= REPLAY_NUM_LIMIT[3:0])
            nak_storm_q <= 1'b1;
        end

        // Latch across the transmitter's CRC/emit. Cleared once replay runs.
        if ((timer_exp_q || nak_pulse) && !rep_empty)
          replay_pend_q <= 1'b1;
        else if (replay_en || rep_empty)
          replay_pend_q <= 1'b0;
      end
    end
  end

  assign timer_fire = timer_exp_q;
  // Hold the request until the transmitter is idle. A one-cycle timer pulse
  // that lands during CRC or emit used to be dropped, and a replay that
  // started while a frame sat in ST_PUSH could never finish: push_ready
  // falls during replay, and replay_ready needs ST_IDLE.
  assign replay_req = replay_pend_q && !rep_empty && !rep_active &&
                      tx_idle && (dl_state == RIVET_DL_ACTIVE) && !replay_en;
  // replay_done is still high the cycle replay_active falls. Starting
  // again on that cycle re-enters replay after the SM has already left it.
  assign rep_start  = replay_en && !replay_done && !rep_active && !rep_empty;

  assign dll_to_mac_sb_o.dl_up                = dl_up;
  assign dll_to_mac_sb_o.replay_timer_expired = timer_fire;
  assign dll_to_mac_sb_o.nak_storm            = nak_storm_q;
  assign dll_to_mac_sb_o.tx_idle_req          = 1'b0;

  rivet_dll_sm u_sm (
    .pclk_i          (pclk_i),
    .rst_ni          (rst_ni),
    .mac_sb_i        (mac_to_dll_sb_i),
    .fc_init_done_i  (fc_sb.fc_init_done),
    .replay_req_i    (replay_req),
    .replay_done_i   (replay_done),
    .state_o         (dl_state),
    .dl_up_o         (dl_up),
    .tlp_tx_en_o     (tlp_tx_en),
    .replay_en_o     (replay_en),
    .fc_en_o         (fc_en)
  );

  rivet_dll_fc #(
    .INITFC_GAP_CYC   (INITFC_GAP_CYC),
    .UPDATEFC_GAP_CYC (UPDATEFC_GAP_CYC)
  ) u_fc (
    .pclk_i       (pclk_i),
    .rst_ni       (rst_ni),
    .mac_sb_i     (mac_to_dll_sb_i),
    .tl_fc_i      (tl_to_dll_fc_i),
    .req_o        (fc_req),
    .req_valid_o  (fc_req_valid),
    .req_ready_i  (fc_req_ready),
    .dec_i        (dec),
    .dec_valid_i  (dec_valid),
    .dec_ready_o  (),
    .dll_tl_fc_o  (fc_sb)
  );

  always_comb begin
    dll_to_tl_fc_o           = fc_sb;
    dll_to_tl_fc_o.dl_up     = dl_up;
    dll_to_tl_fc_o.dl_active = dl_up;
  end

  // -------------------------------------------------------------------------
  // 2-entry skid buffer on tl_tx -> u_tl_pack
  // -------------------------------------------------------------------------
  typedef struct packed {
    logic [TX_DATA_W-1:0] data;
    logic [TX_KEEP_W-1:0] keep;
    logic                 last;
  } tl_tx_beat_t;

  tl_tx_beat_t tl_tx_d0_q, tl_tx_d1_q;
  logic        tl_tx_v0_q, tl_tx_v1_q;

  assign tl_tx_tready_o  = !tl_tx_v1_q;
  assign tl_tx_s_tvalid  = tl_tx_v0_q;
  assign tl_tx_s_tdata   = tl_tx_d0_q.data;
  assign tl_tx_s_tkeep   = tl_tx_d0_q.keep;
  assign tl_tx_s_tlast   = tl_tx_d0_q.last;

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tl_tx_v0_q <= 1'b0;
      tl_tx_v1_q <= 1'b0;
      tl_tx_d0_q <= '0;
      tl_tx_d1_q <= '0;
    end else begin
      automatic logic        push = tl_tx_tvalid_i && !tl_tx_v1_q;
      automatic logic        pop  = tl_tx_v0_q && tl_tx_s_tready;
      automatic tl_tx_beat_t din  = {tl_tx_tdata_i, tl_tx_tkeep_i, tl_tx_tlast_i};
      unique case ({push, pop})
        2'b10: begin
          if (!tl_tx_v0_q) begin
            tl_tx_v0_q <= 1'b1;
            tl_tx_d0_q <= din;
          end else begin
            tl_tx_v1_q <= 1'b1;
            tl_tx_d1_q <= din;
          end
        end
        2'b01: begin
          if (tl_tx_v1_q) begin
            tl_tx_d0_q <= tl_tx_d1_q;
            tl_tx_v1_q <= 1'b0;
          end else begin
            tl_tx_v0_q <= 1'b0;
          end
        end
        2'b11: begin
          tl_tx_d0_q <= din;
        end
        default: ;
      endcase
    end
  end

  rivet_dll_tl_pack #(
    .DATA_W     (TX_DATA_W),
    .SLOT_BYTES (REPLAY_SLOT_BYTES),
    .STREAM     (TX_DATA_W == 128)
  ) u_tl_pack (
    .clk_i      (pclk_i),
    .rst_ni     (rst_ni),
    .s_tdata_i  (tl_tx_s_tdata),
    .s_tkeep_i  (tl_tx_s_tkeep),
    .s_tlast_i  (tl_tx_s_tlast),
    .s_tvalid_i (tl_tx_s_tvalid),
    .s_tready_o (tl_tx_s_tready),
    .m_valid_o  (whole_tx_v),
    .m_ready_i  (whole_tx_r),
    .m_len_o    (whole_tx_len),
    .m_last_o   (whole_tx_last),
    .rd_idx_i   (tx_word_idx),
    .rd_data_o  (tx_word)
  );

  // RX payload beats come straight from rivet_dll_tlp_rx. The old
  // whole-frame unpack is not in this path.

  // -------------------------------------------------------------------------
  // 2-entry skid buffer on u_tl_unpack -> tl_rx
  // -------------------------------------------------------------------------
  typedef struct packed {
    logic [TL_DATA_W-1:0] data;
    logic [TL_KEEP_W-1:0] keep;
    logic                 last;
    logic [11:0]          seq;
  } tl_rx_beat_t;

  tl_rx_beat_t tl_rx_d0_q, tl_rx_d1_q;
  logic        tl_rx_v0_q, tl_rx_v1_q;

  assign tl_rx_u_tready = !tl_rx_v1_q;
  assign tl_rx_tvalid_o = tl_rx_v0_q;
  assign tl_rx_tdata_o  = tl_rx_d0_q.data;
  assign tl_rx_tkeep_o  = tl_rx_d0_q.keep;
  assign tl_rx_tlast_o  = tl_rx_d0_q.last;
  assign tl_rx_seq_o    = tl_rx_d0_q.seq;

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tl_rx_v0_q <= 1'b0;
      tl_rx_v1_q <= 1'b0;
      tl_rx_d0_q <= '0;
      tl_rx_d1_q <= '0;
    end else begin
      automatic logic        push = tl_rx_u_tvalid && !tl_rx_v1_q;
      automatic logic        pop  = tl_rx_v0_q && tl_rx_tready_i;
      automatic tl_rx_beat_t din  = {tl_rx_u_tdata, tl_rx_u_tkeep,
                                     tl_rx_u_tlast, tl_rx_u_seq};
      unique case ({push, pop})
        2'b10: begin
          if (!tl_rx_v0_q) begin
            tl_rx_v0_q <= 1'b1;
            tl_rx_d0_q <= din;
          end else begin
            tl_rx_v1_q <= 1'b1;
            tl_rx_d1_q <= din;
          end
        end
        2'b01: begin
          if (tl_rx_v1_q) begin
            tl_rx_d0_q <= tl_rx_d1_q;
            tl_rx_v1_q <= 1'b0;
          end else begin
            tl_rx_v0_q <= 1'b0;
          end
        end
        2'b11: begin
          if (tl_rx_v1_q) begin
            tl_rx_d0_q <= tl_rx_d1_q;
            tl_rx_d1_q <= din;
          end else begin
            tl_rx_d0_q <= din;
          end
        end
        default: ;
      endcase
    end
  end

  rivet_dll_replay #(
    .TLP_SLOTS  (REPLAY_TLP_SLOTS),
    .SLOT_BYTES (REPLAY_SLOT_BYTES)
  ) u_replay (
    .clk_i           (pclk_i),
    .rst_ni          (rst_ni),
    .clear_i         (clear_replay),
    .cap_valid_i     (cap_v),
    .cap_ready_o     (cap_r),
    .cap_data_i      (cap_data),
    .cap_last_i      (cap_last),
    .cap_seq_i       (cap_seq),
    .cap_len_i       (cap_len),
    .cap_hi_valid_i  (cap_hi_v),
    .cap_hi_data_i   (cap_hi_d),
    .ack_valid_i     (ack_to_buf),
    .ack_seq_i       (ack_seq_to_buf),
    .replay_start_i  (rep_start),
    .replay_active_o (rep_active),
    .replay_done_o   (replay_done),
    .replay_valid_o  (rep_v),
    .replay_ready_i  (rep_r),
    .replay_seq_o    (rep_seq),
    .replay_word_idx_i(rep_word_idx),
    .replay_word_o   (rep_word),
    .replay_len_o    (rep_len),
    .full_o          (rep_full),
    .empty_o         (rep_empty),
    .occupancy_o     (rep_occ)
  );

  // DLLP req mux: ACK/NAK > TLP/replay silence > FC
  always_comb begin
    if (ack_valid) begin
      dllp_req       = ack_req;
      dllp_req_valid = 1'b1;
      ack_ready      = dllp_req_ready;
      fc_req_ready   = 1'b0;
    end else if (tlp_v || rep_active || replay_en) begin
      dllp_req       = '0;
      dllp_req_valid = 1'b0;
      ack_ready      = 1'b0;
      fc_req_ready   = 1'b0;
    end else begin
      dllp_req       = fc_req;
      dllp_req_valid = fc_req_valid && fc_en;
      fc_req_ready   = dllp_req_ready;
      ack_ready      = 1'b0;
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dllp_hold_ack_q <= 1'b0;
      tlp_in_pkt_q    <= 1'b0;
    end else if (clear_replay) begin
      dllp_hold_ack_q <= 1'b0;
      tlp_in_pkt_q    <= 1'b0;
    end else begin
      if (dllp_req_valid && dllp_req_ready) begin
        dllp_hold_ack_q <= (dllp_req.kind == RIVET_DLLP_KIND_ACK) ||
                           (dllp_req.kind == RIVET_DLLP_KIND_NAK);
      end else if (dllp_v && dllp_r) begin
        dllp_hold_ack_q <= 1'b0;
      end

      if (tlp_v && tlp_r) begin
        if (tlp_beat.eop)      tlp_in_pkt_q <= 1'b0;
        else if (tlp_beat.sop) tlp_in_pkt_q <= 1'b1;
      end
    end
  end

  // Pending FC yields to TLP; pending ACK/NAK waits only until an in-flight
  // multi-beat TLP finishes its EOP so the stream stays packet-atomic.
  assign present_dllp = dllp_v && !tlp_in_pkt_q && (dllp_hold_ack_q || !tlp_v);

  rivet_dllp_tx u_dllp_tx (
    .clk_i        (pclk_i),
    .rst_ni       (rst_ni),
    .req_i        (dllp_req),
    .req_valid_i  (dllp_req_valid),
    .req_ready_o  (dllp_req_ready),
    .beat_o       (dllp_beat),
    .beat_valid_o (dllp_v),
    .beat_ready_i (dllp_r)
  );

  generate
    if (TX_DATA_W == 128) begin : g_tx16
      rivet_dll_tlp_tx16 #(.SLOT_BYTES(REPLAY_SLOT_BYTES)) u_tlp_tx (
        .clk_i           (pclk_i),
        .rst_ni          (rst_ni),
        .enable_i        (tlp_tx_en && !rep_full && !rep_active && !replay_req),
        .replay_en_i     (rep_active),
        .tl_valid_i      (whole_tx_v),
        .tl_ready_o      (whole_tx_r),
        .tl_len_i        (whole_tx_len),
        .tl_last_i       (whole_tx_last),
        .tl_word_i       (tx_word),
        .tl_word_idx_o   (tx_word_idx),
        .replay_valid_i  (rep_v),
        .replay_ready_o  (rep_r),
        .replay_seq_i    (rep_seq),
        .replay_len_i    (rep_len),
        .replay_word_i   (rep_word),
        .replay_word_idx_o(rep_word_idx),
        .cap_valid_o     (cap_v),
        .cap_ready_i     (cap_r),
        .cap_data_o      (cap_data),
        .cap_last_o      (cap_last),
        .cap_seq_o       (cap_seq),
        .cap_len_o       (cap_len),
        .cap_hi_valid_o  (cap_hi_v),
        .cap_hi_data_o   (cap_hi_d),
        .beat_o          (tlp_beat),
        .beat_valid_o    (tlp_v),
        .beat_ready_i    (tlp_r),
        .idle_o          (tx_idle),
        .next_tx_seq_o   (next_tx_seq)
      );
    end else begin : g_tx8
      assign cap_hi_v = 1'b0;
      assign cap_hi_d = '0;
      rivet_dll_tlp_tx #(.SLOT_BYTES(REPLAY_SLOT_BYTES)) u_tlp_tx (
        .clk_i           (pclk_i),
        .rst_ni          (rst_ni),
        .enable_i        (tlp_tx_en && !rep_full && !rep_active && !replay_req),
        .replay_en_i     (rep_active),
        .tl_valid_i      (whole_tx_v),
        .tl_ready_o      (whole_tx_r),
        .tl_len_i        (whole_tx_len),
        .tl_word_i       (tx_word),
        .tl_word_idx_o   (tx_word_idx),
        .replay_valid_i  (rep_v),
        .replay_ready_o  (rep_r),
        .replay_seq_i    (rep_seq),
        .replay_len_i    (rep_len),
        .replay_word_i   (rep_word),
        .replay_word_idx_o(rep_word_idx),
        .cap_valid_o     (cap_v),
        .cap_ready_i     (cap_r),
        .cap_data_o      (cap_data),
        .cap_last_o      (cap_last),
        .cap_seq_o       (cap_seq),
        .cap_len_o       (cap_len),
        .beat_o          (tlp_beat),
        .beat_valid_o    (tlp_v),
        .beat_ready_i    (tlp_r),
        .idle_o          (tx_idle),
        .next_tx_seq_o   (next_tx_seq)
      );
    end
  endgenerate

  assign mux_tx_v    = present_dllp || tlp_v;
  assign mux_tx_beat = present_dllp ? dllp_beat : tlp_beat;
  assign dllp_r      = mux_tx_r && present_dllp;
  assign tlp_r       = mux_tx_r && !present_dllp && tlp_v;

  // -------------------------------------------------------------------------
  // 2-entry skid buffer on dll_tx (u_dll -> u_mac)
  // -------------------------------------------------------------------------
  rivet_dll_mac_tx_beat_t dll_tx_d0_q, dll_tx_d1_q;
  logic                   dll_tx_v0_q, dll_tx_v1_q;

  assign mux_tx_r       = !dll_tx_v1_q;
  assign dll_tx_valid_o = dll_tx_v0_q;
  assign dll_tx_beat_o  = dll_tx_d0_q;

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dll_tx_v0_q <= 1'b0;
      dll_tx_v1_q <= 1'b0;
      dll_tx_d0_q <= '0;
      dll_tx_d1_q <= '0;
    end else if (clear_replay) begin
      dll_tx_v0_q <= 1'b0;
      dll_tx_v1_q <= 1'b0;
    end else begin
      automatic logic push = mux_tx_v && !dll_tx_v1_q;
      automatic logic pop  = dll_tx_v0_q && dll_tx_ready_i;
      unique case ({push, pop})
        2'b10: begin
          if (!dll_tx_v0_q) begin
            dll_tx_v0_q <= 1'b1;
            dll_tx_d0_q <= mux_tx_beat;
          end else begin
            dll_tx_v1_q <= 1'b1;
            dll_tx_d1_q <= mux_tx_beat;
          end
        end
        2'b01: begin
          if (dll_tx_v1_q) begin
            dll_tx_d0_q <= dll_tx_d1_q;
            dll_tx_v1_q <= 1'b0;
          end else begin
            dll_tx_v0_q <= 1'b0;
          end
        end
        2'b11: begin
          dll_tx_d0_q <= mux_tx_beat;
        end
        default: ;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // 2-entry skid buffer on dll_rx (u_mac -> u_dll)
  // -------------------------------------------------------------------------
  rivet_dll_mac_rx_beat_t dll_rx_d0_q, dll_rx_d1_q;
  logic                   dll_rx_v0_q, dll_rx_v1_q;

  assign dll_rx_ready_o = !dll_rx_v1_q;
  assign rx_skid_v      = dll_rx_v0_q;
  assign rx_skid_beat   = dll_rx_d0_q;

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dll_rx_v0_q <= 1'b0;
      dll_rx_v1_q <= 1'b0;
      dll_rx_d0_q <= '0;
      dll_rx_d1_q <= '0;
    end else if (clear_replay) begin
      dll_rx_v0_q <= 1'b0;
      dll_rx_v1_q <= 1'b0;
    end else begin
      automatic logic push = dll_rx_valid_i && !dll_rx_v1_q;
      automatic logic pop  = dll_rx_v0_q && rx_skid_r;
      unique case ({push, pop})
        2'b10: begin
          if (!dll_rx_v0_q) begin
            dll_rx_v0_q <= 1'b1;
            dll_rx_d0_q <= dll_rx_beat_i;
          end else begin
            dll_rx_v1_q <= 1'b1;
            dll_rx_d1_q <= dll_rx_beat_i;
          end
        end
        2'b01: begin
          if (dll_rx_v1_q) begin
            dll_rx_d0_q <= dll_rx_d1_q;
            dll_rx_v1_q <= 1'b0;
          end else begin
            dll_rx_v0_q <= 1'b0;
          end
        end
        2'b11: begin
          dll_rx_d0_q <= dll_rx_beat_i;
        end
        default: ;
      endcase
    end
  end

  assign rx_is_dllp = rx_skid_v && (rx_skid_beat.pkt_type == RIVET_MAC_PKT_DLLP);
  assign rx_is_tlp  = rx_skid_v && (rx_skid_beat.pkt_type == RIVET_MAC_PKT_TLP);
  assign dllp_rx_v  = rx_is_dllp;
  assign tlp_rx_v   = rx_is_tlp;
  assign rx_skid_r  = rx_is_dllp ? dllp_rx_r :
                      rx_is_tlp  ? tlp_rx_r  : 1'b1;

  rivet_dllp_rx u_dllp_rx (
    .clk_i        (pclk_i),
    .rst_ni       (rst_ni),
    .beat_i       (rx_skid_beat),
    .beat_valid_i (dllp_rx_v),
    .beat_ready_o (dllp_rx_r),
    .dec_o        (dec),
    .dec_valid_o  (dec_valid),
    .dec_ready_i  (dec_ready)
  );

  generate
    if (TL_DATA_W == 128) begin : g_rx16
      rivet_dll_tlp_rx16 #(.SLOT_BYTES(RX_SLOT_BYTES)) u_tlp_rx (
        .clk_i           (pclk_i),
        .rst_ni          (rst_ni),
        .enable_i        (rx_enable_q),
        .beat_i          (rx_skid_beat),
        .beat_valid_i    (tlp_rx_v),
        .beat_ready_o    (tlp_rx_r),
        .tl_valid_o      (tl_rx_u_tvalid),
        .tl_ready_i      (tl_rx_u_tready),
        .tl_data_o       (tl_rx_u_tdata),
        .tl_keep_o       (tl_rx_u_tkeep),
        .tl_last_o       (tl_rx_u_tlast),
        .tl_seq_o        (tl_rx_u_seq),
        .ack_req_o       (ack_req),
        .ack_valid_o     (ack_valid),
        .ack_ready_i     (ack_ready),
        .last_good_seq_o (last_good),
        .lcrc_err_o      (lcrc_err),
        .tl_abort_o      (tl_rx_abort_o)
      );
    end else begin : g_rx8
      rivet_dll_tlp_rx #(.SLOT_BYTES(RX_SLOT_BYTES)) u_tlp_rx (
        .clk_i           (pclk_i),
        .rst_ni          (rst_ni),
        .enable_i        (rx_enable_q),
        .beat_i          (rx_skid_beat),
        .beat_valid_i    (tlp_rx_v),
        .beat_ready_o    (tlp_rx_r),
        .tl_valid_o      (tl_rx_u_tvalid),
        .tl_ready_i      (tl_rx_u_tready),
        .tl_data_o       (tl_rx_u_tdata),
        .tl_keep_o       (tl_rx_u_tkeep),
        .tl_last_o       (tl_rx_u_tlast),
        .tl_seq_o        (tl_rx_u_seq),
        .ack_req_o       (ack_req),
        .ack_valid_o     (ack_valid),
        .ack_ready_i     (ack_ready),
        .last_good_seq_o (last_good),
        .lcrc_err_o      (lcrc_err)
      );
      assign tl_rx_abort_o = 1'b0;
    end
  endgenerate

  logic _unused;
  assign _unused = |PIPE_DATA_WIDTH | (|next_tx_seq) | (|last_good) | lcrc_err |
                   replay_en | rep_full | (|rep_occ);

endmodule : rivet_dll
