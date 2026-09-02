// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Data Link Layer top: FC + DL SM + streaming TL hook + TLP seq/LCRC +
// ACK/NAK + replay (D5).

module rivet_dll #(
  parameter int unsigned LANES             = 1,
  parameter int unsigned PIPE_DATA_WIDTH   = 16,
  parameter int unsigned INITFC_GAP_CYC    = 8,
  parameter int unsigned UPDATEFC_GAP_CYC  = 32,
  parameter int unsigned REPLAY_TLP_SLOTS  = 16,
  parameter int unsigned REPLAY_SLOT_BYTES = 160,
  parameter int unsigned REPLAY_TIMER_CYC  = 256,
  parameter int unsigned REPLAY_NUM_LIMIT  = 3,
  parameter int unsigned TL_DATA_W         = rivet_pkg::RIVET_TL_DLL_DATA_W
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

  // TL ↔ DLL TLP stream (payload only; seq/LCRC added/stripped in DLL)
  input  logic [TL_DATA_W-1:0]              tl_tx_tdata_i,
  input  logic [TL_DATA_W/8-1:0]            tl_tx_tkeep_i,
  input  logic                              tl_tx_tlast_i,
  input  logic                              tl_tx_tvalid_i,
  output logic                              tl_tx_tready_o,

  output logic [TL_DATA_W-1:0]              tl_rx_tdata_o,
  output logic [TL_DATA_W/8-1:0]            tl_rx_tkeep_o,
  output logic                              tl_rx_tlast_o,
  output logic                              tl_rx_tvalid_o,
  input  logic                              tl_rx_tready_i,
  output logic [11:0]                       tl_rx_seq_o
);

  import rivet_pkg::*;

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

  logic                       push_v, push_r;
  logic [11:0]                push_seq;
  logic [REPLAY_SLOT_BYTES*8-1:0] push_data;
  logic [15:0]                push_len;
  logic                       rep_start, rep_active, rep_v, rep_r;
  logic [11:0]                rep_seq;
  logic [REPLAY_SLOT_BYTES*8-1:0] rep_data;
  logic [15:0]                rep_len;
  logic                       rep_full, rep_empty;
  logic [15:0]                rep_occ;

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

  rivet_dll_mac_tx_beat_t dllp_beat, tlp_beat;
  logic                   dllp_v, tlp_v, dllp_r, tlp_r;
  logic                   dllp_hold_ack_q;
  logic                   present_dllp;
  logic [11:0]            next_tx_seq;

  logic dllp_rx_v, tlp_rx_v, dllp_rx_r, tlp_rx_r;
  logic rx_is_dllp, rx_is_tlp;
  logic rx_enable;
  logic [11:0] last_good;
  logic        lcrc_err;

  logic                              whole_tx_v, whole_tx_r;
  logic [REPLAY_SLOT_BYTES*8-1:0]    whole_tx_d;
  logic [15:0]                       whole_tx_len;
  logic                              whole_rx_v, whole_rx_r;
  logic [REPLAY_SLOT_BYTES*8-1:0]    whole_rx_d;
  logic [15:0]                       whole_rx_len;
  logic [11:0]                       whole_rx_seq;

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
      timer_exp_q  <= 1'b0;
    end else if (clear_replay) begin
      timer_q      <= '0;
      timer_en_q   <= 1'b0;
      replay_num_q <= '0;
      nak_storm_q  <= 1'b0;
      timer_exp_q  <= 1'b0;
    end else begin
      timer_exp_q <= 1'b0;

      if (push_v && push_r) begin
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
    end
  end

  assign timer_fire = timer_exp_q;
  assign replay_req = ((nak_pulse || timer_fire) && !rep_empty && !rep_active &&
                       (dl_state == RIVET_DL_ACTIVE));
  assign rep_start  = (dl_state == RIVET_DL_REPLAY) && !rep_active && !rep_empty;

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

  rivet_dll_tl_pack #(
    .DATA_W     (TL_DATA_W),
    .SLOT_BYTES (REPLAY_SLOT_BYTES)
  ) u_tl_pack (
    .clk_i      (pclk_i),
    .rst_ni     (rst_ni),
    .s_tdata_i  (tl_tx_tdata_i),
    .s_tkeep_i  (tl_tx_tkeep_i),
    .s_tlast_i  (tl_tx_tlast_i),
    .s_tvalid_i (tl_tx_tvalid_i),
    .s_tready_o (tl_tx_tready_o),
    .m_valid_o  (whole_tx_v),
    .m_ready_i  (whole_tx_r),
    .m_data_o   (whole_tx_d),
    .m_len_o    (whole_tx_len)
  );

  rivet_dll_tl_unpack #(
    .DATA_W     (TL_DATA_W),
    .SLOT_BYTES (REPLAY_SLOT_BYTES)
  ) u_tl_unpack (
    .clk_i      (pclk_i),
    .rst_ni     (rst_ni),
    .s_valid_i  (whole_rx_v),
    .s_ready_o  (whole_rx_r),
    .s_data_i   (whole_rx_d),
    .s_len_i    (whole_rx_len),
    .s_seq_i    (whole_rx_seq),
    .m_tdata_o  (tl_rx_tdata_o),
    .m_tkeep_o  (tl_rx_tkeep_o),
    .m_tlast_o  (tl_rx_tlast_o),
    .m_tvalid_o (tl_rx_tvalid_o),
    .m_tready_i (tl_rx_tready_i),
    .m_seq_o    (tl_rx_seq_o)
  );

  rivet_dll_replay #(
    .TLP_SLOTS  (REPLAY_TLP_SLOTS),
    .SLOT_BYTES (REPLAY_SLOT_BYTES)
  ) u_replay (
    .clk_i           (pclk_i),
    .rst_ni          (rst_ni),
    .clear_i         (clear_replay),
    .push_valid_i    (push_v),
    .push_ready_o    (push_r),
    .push_seq_i      (push_seq),
    .push_data_i     (push_data),
    .push_len_i      (push_len),
    .ack_valid_i     (ack_to_buf),
    .ack_seq_i       (ack_seq_to_buf),
    .replay_start_i  (rep_start),
    .replay_active_o (rep_active),
    .replay_done_o   (replay_done),
    .replay_valid_o  (rep_v),
    .replay_ready_i  (rep_r),
    .replay_seq_o    (rep_seq),
    .replay_data_o   (rep_data),
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
    end else if (tlp_v || rep_active || (dl_state == RIVET_DL_REPLAY)) begin
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
    if (!rst_ni) dllp_hold_ack_q <= 1'b0;
    else if (dllp_req_valid && dllp_req_ready) begin
      dllp_hold_ack_q <= (dllp_req.kind == RIVET_DLLP_KIND_ACK) ||
                         (dllp_req.kind == RIVET_DLLP_KIND_NAK);
    end else if (dllp_v && dllp_r) begin
      dllp_hold_ack_q <= 1'b0;
    end
  end

  // Pending FC yields to TLP; pending ACK/NAK keeps the wire.
  assign present_dllp = dllp_v && (dllp_hold_ack_q || !tlp_v);

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

  rivet_dll_tlp_tx #(.SLOT_BYTES(REPLAY_SLOT_BYTES)) u_tlp_tx (
    .clk_i           (pclk_i),
    .rst_ni          (rst_ni),
    .enable_i        (tlp_tx_en && !rep_full && !rep_active && !replay_req),
    .replay_en_i     (rep_active),
    .tl_valid_i      (whole_tx_v),
    .tl_ready_o      (whole_tx_r),
    .tl_data_i       (whole_tx_d),
    .tl_len_i        (whole_tx_len),
    .replay_valid_i  (rep_v),
    .replay_ready_o  (rep_r),
    .replay_seq_i    (rep_seq),
    .replay_data_i   (rep_data),
    .replay_len_i    (rep_len),
    .push_valid_o    (push_v),
    .push_ready_i    (push_r),
    .push_seq_o      (push_seq),
    .push_data_o     (push_data),
    .push_len_o      (push_len),
    .beat_o          (tlp_beat),
    .beat_valid_o    (tlp_v),
    .beat_ready_i    (tlp_r),
    .next_tx_seq_o   (next_tx_seq)
  );

  assign dll_tx_valid_o = present_dllp || tlp_v;
  assign dll_tx_beat_o  = present_dllp ? dllp_beat : tlp_beat;
  assign dllp_r         = dll_tx_ready_i && present_dllp;
  assign tlp_r          = dll_tx_ready_i && !present_dllp && tlp_v;

  assign rx_is_dllp = dll_rx_valid_i && (dll_rx_beat_i.pkt_type == RIVET_MAC_PKT_DLLP);
  assign rx_is_tlp  = dll_rx_valid_i && (dll_rx_beat_i.pkt_type == RIVET_MAC_PKT_TLP);
  assign dllp_rx_v  = rx_is_dllp;
  assign tlp_rx_v   = rx_is_tlp;
  assign dll_rx_ready_o = rx_is_dllp ? dllp_rx_r :
                          rx_is_tlp  ? tlp_rx_r  : 1'b1;

  rivet_dllp_rx u_dllp_rx (
    .clk_i        (pclk_i),
    .rst_ni       (rst_ni),
    .beat_i       (dll_rx_beat_i),
    .beat_valid_i (dllp_rx_v),
    .beat_ready_o (dllp_rx_r),
    .dec_o        (dec),
    .dec_valid_o  (dec_valid),
    .dec_ready_i  (dec_ready)
  );

  assign rx_enable = mac_to_dll_sb_i.accept_dll_tlp &&
                     ((dl_state == RIVET_DL_ACTIVE) || (dl_state == RIVET_DL_REPLAY));

  rivet_dll_tlp_rx #(.SLOT_BYTES(REPLAY_SLOT_BYTES)) u_tlp_rx (
    .clk_i           (pclk_i),
    .rst_ni          (rst_ni),
    .enable_i        (rx_enable),
    .beat_i          (dll_rx_beat_i),
    .beat_valid_i    (tlp_rx_v),
    .beat_ready_o    (tlp_rx_r),
    .tl_valid_o      (whole_rx_v),
    .tl_ready_i      (whole_rx_r),
    .tl_data_o       (whole_rx_d),
    .tl_len_o        (whole_rx_len),
    .tl_seq_o        (whole_rx_seq),
    .ack_req_o       (ack_req),
    .ack_valid_o     (ack_valid),
    .ack_ready_i     (ack_ready),
    .last_good_seq_o (last_good),
    .lcrc_err_o      (lcrc_err)
  );

  logic _unused;
  assign _unused = |PIPE_DATA_WIDTH | (|next_tx_seq) | (|last_good) | lcrc_err |
                   replay_en | rep_full | (|rep_occ);

endmodule : rivet_dll
