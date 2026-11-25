// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PIPE adapter: MAC symbol/command plane <-> flat PG239-aligned PIPE ports.
// Both TX and RX boundaries are registered on pclk so transceiver hard-macro
// routing does not combine with MAC/LTSSM logic at 250 MHz.

module rivet_mac_pipe_adapter #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  // From OS TX / LTSSM
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] sym_tx_data_i,
  input  logic [2*LANES-1:0]               sym_tx_datak_i,
  input  logic                             sym_tx_valid_i,
  input  logic                             sym_tx_os_i = 1'b0,
  input  logic                             sym_tx_start_i = 1'b0,
  input  logic                             txdetectrx_i,
  input  logic [LANES-1:0]                 txelecidle_i,
  input  logic [LANES-1:0]                 rxpolarity_i,
  input  logic [1:0]                       powerdown_i,
  input  logic [2:0]                       rate_i,
  input  logic                             as_mac_in_detect_i,
  input  logic                             as_cdr_hold_req_i,
  input  logic                             as_mac_in_L0_i,

  // To OS RX
  output logic [PIPE_DATA_WIDTH*LANES-1:0] sym_rx_data_o,
  output logic [2*LANES-1:0]               sym_rx_datak_o,
  output logic [LANES-1:0]                 sym_rx_valid_o,
  output logic [LANES-1:0]                 sym_rx_os_o,
  output logic [LANES-1:0]                 sym_rx_start_o,
  output logic [3*LANES-1:0]               rxstatus_o,

  // To LTSSM: PHY handshake and receiver detection
  output logic [LANES-1:0]                 phystatus_o,
  output logic [LANES-1:0]                 phystatus_rst_o,
  output logic [LANES-1:0]                 rxelecidle_o,
  output logic [LANES-1:0]                 rxvalid_o,
  output logic [LANES-1:0]                 rx_detected_o,

  // Flat PIPE (controller top / PG239)
  output logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata_o,
  output logic [2*LANES-1:0]               pipe_txdatak_o,
  output logic [LANES-1:0]                 pipe_txdata_valid_o,
  output logic [LANES-1:0]                 pipe_txstart_block_o,
  output logic [2*LANES-1:0]               pipe_txsync_header_o,
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata_i,
  input  logic [2*LANES-1:0]               pipe_rxdatak_i,
  input  logic [LANES-1:0]                 pipe_rxdata_valid_i,
  input  logic [2*LANES-1:0]               pipe_rxstart_block_i,
  input  logic [2*LANES-1:0]               pipe_rxsync_header_i,
  output logic                             pipe_txdetectrx_o,
  output logic [LANES-1:0]                 pipe_txelecidle_o,
  output logic [LANES-1:0]                 pipe_txcompliance_o,
  output logic [LANES-1:0]                 pipe_rxpolarity_o,
  output logic [1:0]                       pipe_powerdown_o,
  output logic [2:0]                       pipe_rate_o,
  input  logic [LANES-1:0]                 pipe_rxvalid_i,
  input  logic [LANES-1:0]                 pipe_phystatus_i,
  input  logic [LANES-1:0]                 pipe_phystatus_rst_i,
  input  logic [LANES-1:0]                 pipe_rxelecidle_i,
  input  logic [3*LANES-1:0]               pipe_rxstatus_i,
  output logic [2:0]                       pipe_txmargin_o,
  output logic                             pipe_txswing_o,
  output logic                             pipe_txdeemph_o,
  input  logic [1:0]                       txeq_ctrl_i = 2'b00,
  input  logic [3:0]                       txeq_preset_i = 4'h0,
  input  logic                             eq_search_i = 1'b0,
  input  logic [7:0]                       pipe_margin_msg_i = 8'h00,
  output logic [2*LANES-1:0]               pipe_txeq_ctrl_o,
  output logic [4*LANES-1:0]               pipe_txeq_preset_o,
  output logic [6*LANES-1:0]               pipe_txeq_coeff_o,
  input  logic [5:0]                       pipe_txeq_fs_i,
  input  logic [5:0]                       pipe_txeq_lf_i,
  input  logic [18*LANES-1:0]              pipe_txeq_new_coeff_i,
  input  logic [LANES-1:0]                 pipe_txeq_done_i,
  output logic [2*LANES-1:0]               pipe_rxeq_ctrl_o,
  output logic [4*LANES-1:0]               pipe_rxeq_txpreset_o,
  input  logic [LANES-1:0]                 pipe_rxeq_preset_sel_i,
  input  logic [18*LANES-1:0]              pipe_rxeq_new_txcoeff_i,
  input  logic [LANES-1:0]                 pipe_rxeq_adapt_done_i,
  input  logic [LANES-1:0]                 pipe_rxeq_done_i,
  output logic                             pipe_as_mac_in_detect_o,
  output logic                             pipe_as_cdr_hold_req_o,
  output logic                             pipe_as_mac_in_L0_o,
  output logic [1:0]                       pipe_cfg_rx_pm_state_o
);

  import rivet_pkg::*;

  logic [PIPE_DATA_WIDTH*LANES-1:0] txdata_q;
  logic [2*LANES-1:0]               txdatak_q;
  logic                             txdetectrx_q;
  logic [LANES-1:0]                 txelecidle_q;
  logic [LANES-1:0]                 rxpolarity_q;
  logic [1:0]                       powerdown_q;
  logic [2:0]                       rate_q;
  logic                             as_mac_in_detect_q;
  logic                             as_cdr_hold_req_q;
  logic                             as_mac_in_L0_q;

  logic [PIPE_DATA_WIDTH*LANES-1:0] rxdata_q;
  logic [2*LANES-1:0]               rxdatak_q;
  logic [LANES-1:0]                 rxvalid_q;
  logic [3*LANES-1:0]               rxstatus_q;
  logic [LANES-1:0]                 phystatus_q;
  logic [LANES-1:0]                 phystatus_rst_q;
  logic [LANES-1:0]                 rxelecidle_q;
  logic [LANES-1:0]                 rx_detected_d;
  logic [LANES-1:0]                 rx_detected_q;

  // Block pipe. rate_q is the registered PIPE rate, so Gen1/Gen2 keeps the
  // datak path. A low rxdata_valid does not advance a block. Start 2'b10 is
  // a Gen4 upper-half marker: accepted at Gen4, dropped at Gen3.
  logic                    gen3_q;
  logic                    gen4_q;
  logic                    block_q;
  logic [LANES-1:0]        rx_take_d;
  logic [LANES-1:0]        rx_in_q;
  logic [2*LANES-1:0]      rx_idx_q;
  logic [PIPE_DATA_WIDTH*LANES-1:0] rx_acc_q;
  logic [LANES-1:0]        rx_acc_v_q;
  logic [LANES-1:0]        rx_os_q;
  logic [LANES-1:0]        rx_start_q;
  logic [1:0]              hdr_mem [0:3];
  logic [1:0]              hdr_wr_q, hdr_rd_q;
  logic [2:0]              hdr_n_q;
  logic [1:0]              tx_word_q;
  logic                    tx_start_q;
  logic                    tx_dv_q;
  logic [1:0]              tx_hdr_q;

  // Gen3 on a 64-bit elaboration still uses four low symbols per word.
  // Start 2'b10 stays a Gen4-only accept in rx_take below.
  assign gen3_q  = (rate_q == RIVET_PIPE_RATE_GEN3) &&
                   ((PIPE_DATA_WIDTH == 32) || (PIPE_DATA_WIDTH == 64));
  assign gen4_q  = (rate_q == RIVET_PIPE_RATE_GEN4) && (PIPE_DATA_WIDTH == 64);
  assign block_q = gen3_q || gen4_q;

  // 16 bytes is four Gen3 words or two Gen4 words.
  wire [1:0] blk_last = gen4_q ? 2'd1 : 2'd3;

  function automatic logic block_start(input logic [1:0] sb);
    if (sb == 2'b01)
      return 1'b1;
    if ((PIPE_DATA_WIDTH == 64) && (sb == 2'b10))
      return 1'b1;
    return 1'b0;
  endfunction

  always_comb begin
    rx_take_d = '0;
    if (PIPE_DATA_WIDTH == 32) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        if (pipe_rxdata_valid_i[l] &&
            (pipe_rxstart_block_i[2*l +: 2] != 2'b10) &&
            ((pipe_rxstart_block_i[2*l +: 2] == 2'b01) || rx_in_q[l]))
          rx_take_d[l] = 1'b1;
      end
    end else if ((PIPE_DATA_WIDTH == 64) && (rate_i == RIVET_PIPE_RATE_GEN3)) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        if (pipe_rxdata_valid_i[l] &&
            (pipe_rxstart_block_i[2*l +: 2] != 2'b10) &&
            ((pipe_rxstart_block_i[2*l +: 2] == 2'b01) || rx_in_q[l]))
          rx_take_d[l] = 1'b1;
      end
    end else if ((PIPE_DATA_WIDTH == 64) && (rate_i == RIVET_PIPE_RATE_GEN4)) begin
      for (int unsigned l = 0; l < LANES; l++) begin
        if (pipe_rxdata_valid_i[l] &&
            (block_start(pipe_rxstart_block_i[2*l +: 2]) ||
             (rx_in_q[l] && (pipe_rxstart_block_i[2*l +: 2] == 2'b00))))
          rx_take_d[l] = 1'b1;
      end
    end
  end

  always_comb begin
    rx_detected_d = '0;
    for (int unsigned l = 0; l < LANES; l++) begin
      rx_detected_d[l] = pipe_phystatus_i[l] &&
                         (pipe_rxstatus_i[3*l +: 3] == RIVET_RXSTATUS_RX_DETECTED);
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      txdata_q           <= '0;
      txdatak_q          <= '0;
      txdetectrx_q       <= 1'b0;
      txelecidle_q       <= {LANES{1'b1}};
      rxpolarity_q       <= '0;
      powerdown_q        <= RIVET_PIPE_P1;
      rate_q             <= RIVET_PIPE_RATE_GEN1;
      as_mac_in_detect_q <= 1'b1;
      as_cdr_hold_req_q  <= 1'b0;
      as_mac_in_L0_q     <= 1'b0;

      rxdata_q           <= '0;
      rxdatak_q          <= '0;
      rxvalid_q          <= '0;
      rxstatus_q         <= '0;
      phystatus_q        <= '0;
      phystatus_rst_q    <= {LANES{1'b1}};
      rxelecidle_q       <= {LANES{1'b1}};
      rx_detected_q      <= '0;
      rx_in_q            <= '0;
      rx_idx_q           <= '0;
      rx_acc_q           <= '0;
      rx_acc_v_q         <= '0;
      rx_os_q            <= '0;
      rx_start_q         <= '0;
      hdr_wr_q           <= '0;
      hdr_rd_q           <= '0;
      hdr_n_q            <= '0;
      tx_word_q          <= '0;
      tx_start_q         <= 1'b0;
      tx_dv_q            <= 1'b0;
      tx_hdr_q           <= '0;
    end else begin
      txdata_q           <= sym_tx_data_i;
      txdatak_q          <= sym_tx_datak_i;
      txdetectrx_q       <= txdetectrx_i;
      txelecidle_q       <= txelecidle_i;
      rxpolarity_q       <= rxpolarity_i;
      powerdown_q        <= powerdown_i;
      rate_q             <= rate_i;
      as_mac_in_detect_q <= as_mac_in_detect_i;
      as_cdr_hold_req_q  <= as_cdr_hold_req_i;
      as_mac_in_L0_q     <= as_mac_in_L0_i;

      rxdata_q           <= pipe_rxdata_i;
      rxdatak_q          <= pipe_rxdatak_i;
      rxvalid_q          <= pipe_rxvalid_i;
      rxstatus_q         <= pipe_rxstatus_i;
      phystatus_q        <= pipe_phystatus_i;
      phystatus_rst_q    <= pipe_phystatus_rst_i;
      rxelecidle_q       <= pipe_rxelecidle_i;
      rx_detected_q      <= rx_detected_d;

      // 16-byte block. Headers accepted on RX come back on the next TX
      // block start. MAC symbol valid low does not consume a word.
      if (block_q) begin
        logic [1:0] wr_b, rd_b, hdr_b;
        logic [2:0] n_b;
        logic       push_b, pop_b;
        wr_b  = hdr_wr_q;
        rd_b  = hdr_rd_q;
        n_b   = hdr_n_q;
        hdr_b = 2'b01;
        push_b = rx_take_d[0] && block_start(pipe_rxstart_block_i[1:0]);
        pop_b  = sym_tx_valid_i && (tx_word_q == 2'd0) && (n_b != 3'd0);
        if (pop_b) begin
          hdr_b = hdr_mem[rd_b];
          rd_b  = rd_b + 2'd1;
          n_b   = n_b - 3'd1;
        end
        if (push_b && (n_b < 3'd4)) begin
          hdr_mem[wr_b] <= pipe_rxsync_header_i[1:0];
          wr_b = wr_b + 2'd1;
          n_b  = n_b + 3'd1;
        end
        hdr_wr_q <= wr_b;
        hdr_rd_q <= rd_b;
        hdr_n_q  <= n_b;

        rx_acc_v_q <= rx_take_d;
        for (int unsigned l = 0; l < LANES; l++) begin
          if (rx_take_d[l]) begin
            logic [1:0] sb;
            sb = pipe_rxstart_block_i[2*l +: 2];
            rx_acc_q[PIPE_DATA_WIDTH*l +: PIPE_DATA_WIDTH] <=
              pipe_rxdata_i[PIPE_DATA_WIDTH*l +: PIPE_DATA_WIDTH];
            rx_start_q[l] <= block_start(sb);
            if (block_start(sb))
              rx_os_q[l] <= (pipe_rxsync_header_i[2*l +: 2] == 2'b10);
            if (block_start(sb)) begin
              rx_in_q[l] <= 1'b1;
              rx_idx_q[2*l +: 2] <= 2'd1;
            end else if (rx_idx_q[2*l +: 2] == blk_last) begin
              rx_in_q[l] <= 1'b0;
              rx_idx_q[2*l +: 2] <= 2'd0;
            end else begin
              rx_idx_q[2*l +: 2] <= rx_idx_q[2*l +: 2] + 2'd1;
            end
          end
        end

        if (sym_tx_valid_i) begin
          tx_dv_q <= 1'b1;
          if (as_mac_in_detect_i) begin
            if (tx_word_q == 2'd0) begin
              tx_start_q <= 1'b1;
              tx_hdr_q   <= hdr_b;
              tx_word_q  <= 2'd1;
            end else begin
              tx_start_q <= 1'b0;
              tx_hdr_q   <= 2'b00;
              tx_word_q  <= (tx_word_q == blk_last) ? 2'd0 : (tx_word_q + 2'd1);
            end
          end else begin
            // Outside Detect, os_tx marks word 0 and OS vs Data directly so
            // block starts stay aligned with the scrambler reseed and SKP.
            tx_start_q <= sym_tx_start_i;
            tx_hdr_q   <= sym_tx_start_i ? (sym_tx_os_i ? 2'b10 : 2'b01) : 2'b00;
            tx_word_q  <= sym_tx_start_i ? 2'd1 :
                          ((tx_word_q == blk_last) ? 2'd0 : (tx_word_q + 2'd1));
          end
        end else begin
          tx_dv_q    <= 1'b0;
          tx_start_q <= 1'b0;
        end
      end else begin
        rx_in_q    <= '0;
        rx_idx_q   <= '0;
        rx_acc_v_q <= '0;
        rx_os_q    <= '0;
        rx_start_q <= '0;
        tx_word_q  <= '0;
        tx_start_q <= 1'b0;
        tx_dv_q    <= 1'b0;
        tx_hdr_q   <= '0;
        hdr_wr_q   <= '0;
        hdr_rd_q   <= '0;
        hdr_n_q    <= '0;
      end
    end
  end

  // Gen2 keeps datak. Gen3/Gen4 drive the full lane word and block sideband.
  assign pipe_txdata_o        = txdata_q;
  assign pipe_txdatak_o       = block_q ? '0 : txdatak_q;
  assign pipe_txdata_valid_o  = block_q ? {LANES{tx_dv_q}} : '0;
  assign pipe_txstart_block_o = block_q ? {LANES{tx_start_q}} : '0;
  assign pipe_txsync_header_o = block_q ? {LANES{tx_hdr_q}} : '0;

  assign pipe_txdetectrx_o       = txdetectrx_q;
  assign pipe_txelecidle_o       = txelecidle_q;
  assign pipe_txcompliance_o     = '0;
  assign pipe_rxpolarity_o       = rxpolarity_q;
  assign pipe_powerdown_o        = powerdown_q;
  logic [5:0] coeff_q;
  logic       coeff_arm_q;

  // Lane 0's new cursor becomes the transmitted coefficient once adaptation
  // finishes. eq_search_i is tied off unless a test forces the search.
  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni || !eq_search_i) begin
      coeff_q     <= '0;
      coeff_arm_q <= 1'b0;
    end else if (pipe_rxeq_adapt_done_i[0]) begin
      coeff_q     <= pipe_rxeq_new_txcoeff_i[5:0];
      coeff_arm_q <= 1'b1;
    end
  end

  assign pipe_rate_o             = rate_q;
  assign pipe_txmargin_o         = (pipe_margin_msg_i[7:4] == 4'h1) ?
                                   pipe_margin_msg_i[2:0] : 3'b000;
  assign pipe_txswing_o          = 1'b0;
  assign pipe_txdeemph_o         = 1'b1; // -3.5 dB default (PG239)
  assign pipe_txeq_ctrl_o        = (eq_search_i && coeff_arm_q) ?
                                   {LANES{2'b10}} : {LANES{txeq_ctrl_i}};
  assign pipe_txeq_preset_o      = {LANES{txeq_preset_i}};
  assign pipe_txeq_coeff_o       = (eq_search_i && coeff_arm_q) ?
                                   {LANES{coeff_q}} : '0;
  assign pipe_rxeq_ctrl_o        = '0;
  assign pipe_rxeq_txpreset_o    = '0;
  assign pipe_as_mac_in_detect_o = as_mac_in_detect_q;
  assign pipe_as_cdr_hold_req_o  = as_cdr_hold_req_q;
  assign pipe_as_mac_in_L0_o     = as_mac_in_L0_q;
  assign pipe_cfg_rx_pm_state_o  = 2'b00;

  // RX toward OS RX. A block rate presents only accepted block words.
  assign sym_rx_data_o  = block_q ? rx_acc_q : rxdata_q;
  assign sym_rx_datak_o = block_q ? '0 : rxdatak_q;
  assign sym_rx_valid_o = block_q ? rx_acc_v_q : rxvalid_q;
  assign sym_rx_os_o    = block_q ? rx_os_q : '0;
  assign sym_rx_start_o = block_q ? rx_start_q : '0;
  assign rxstatus_o     = rxstatus_q;

  // Status toward the LTSSM
  assign phystatus_o     = phystatus_q;
  assign phystatus_rst_o = phystatus_rst_q;
  assign rxelecidle_o    = rxelecidle_q;
  assign rxvalid_o       = rxvalid_q;
  assign rx_detected_o   = rx_detected_q;

  logic _unused_ok;
  assign _unused_ok = (|pipe_txeq_fs_i) ^ (|pipe_txeq_lf_i) ^
                      (|pipe_txeq_new_coeff_i) ^ (|pipe_txeq_done_i) ^
                      (|pipe_rxeq_preset_sel_i) ^ (|pipe_rxeq_new_txcoeff_i) ^
                      (|pipe_rxeq_adapt_done_i) ^ (|pipe_rxeq_done_i);

endmodule : rivet_mac_pipe_adapter
