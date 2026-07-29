// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MAC ordered-set / TS transmitter (Gen2, 8b/10b symbol plane).
//
// Streams the ordered set the LTSSM asks for back to back and reports how many
// have completed, because most LTSSM exits are "N sent" conditions
// (1024 TS1 in Polling.Active, 16 TS2 after the first one received, ...).
// A type change is only honoured on an ordered-set boundary so a partial TS
// never reaches the wire. DLL payload is still refused; that lands with the DLL.

module rivet_mac_os_tx #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic pclk_i,
  input  logic rst_ni,

  input  rivet_pkg::rivet_mac_os_type_e os_req_i,
  input  logic                          os_req_valid_i,
  input  logic                          os_cnt_clr_i,
  input  logic [LANES-1:0]              lane_en_i,

  // TS payload fields (Base 2.1 Tables 4-2/4-3)
  input  logic [7:0]                    tx_link_num_i,
  input  logic [8*LANES-1:0]            tx_lane_num_i,
  input  logic                          tx_link_pad_i,
  input  logic                          tx_lane_pad_i,
  input  logic [7:0]                    tx_n_fts_i,
  input  logic [7:0]                    tx_rate_id_i,
  input  logic [7:0]                    tx_train_ctrl_i,

  // DLL payload (refused until the DLL slice)
  input  rivet_pkg::rivet_dll_mac_tx_beat_t dll_tx_beat_i,
  input  logic                              dll_tx_valid_i,
  output logic                              dll_tx_ready_o,

  // Symbol stream toward pipe adapter (per-link packed)
  output logic [PIPE_DATA_WIDTH*LANES-1:0] sym_data_o,
  output logic [2*LANES-1:0]               sym_datak_o,
  output logic                             sym_valid_o,

  // Ordered sets completed (Idle counts symbols) since os_cnt_clr_i
  output logic [11:0]                      os_sent_cnt_o
);

  import rivet_pkg::*;

  localparam int unsigned SYMS  = PIPE_DATA_WIDTH / 8;
  localparam int unsigned CNT_W = 12;

  localparam logic [CNT_W-1:0] SYMS_C  = CNT_W'(SYMS);
  localparam logic [CNT_W-1:0] CNT_MAX = {CNT_W{1'b1}};

`ifndef SYNTHESIS
  initial begin
    if (PIPE_DATA_WIDTH != 16)
      $error("rivet_mac_os_tx: only PIPE_DATA_WIDTH=16 is implemented (got %0d)",
             PIPE_DATA_WIDTH);
    if (!rivet_lanes_legal(LANES))
      $error("rivet_mac_os_tx LANES must be 1, 2, or 4");
  end
`endif

  // Symbol content of ordered set `os_type` at symbol index `idx` for a lane
  // transmitting Lane Number `lane_num`. Returns {is_k_symbol, symbol}.
  function automatic logic [8:0] os_symbol(input rivet_mac_os_type_e os_type,
                                           input logic [3:0]         idx,
                                           input logic [7:0]         lane_num);
    logic [8:0] sym;
    sym = {1'b0, 8'h00};
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
      default:           sym = {1'b0, 8'h00}; // logical Idle data
    endcase
    return sym;
  endfunction

  function automatic logic [4:0] os_length(input rivet_mac_os_type_e os_type);
    case (os_type)
      RIVET_MAC_OS_TS1,
      RIVET_MAC_OS_TS2:  return 5'(RIVET_TS_LEN);
      RIVET_MAC_OS_SKP,
      RIVET_MAC_OS_FTS,
      RIVET_MAC_OS_EIOS: return 5'(RIVET_SHORT_OS_LEN);
      default:           return 5'(SYMS); // Idle / parked: one cycle per "set"
    endcase
  endfunction

  rivet_mac_os_type_e cur;         // type driven this cycle
  rivet_mac_os_type_e cur_q;       // type of the set in flight
  logic [4:0]         ptr_q;       // symbol index inside the set
  logic [4:0]         len;
  logic [4:0]         ptr_next;
  logic               at_boundary;
  logic               transmitting;
  logic               set_done;
  logic [CNT_W-1:0]   sent_q;
  logic [8:0]         sym_tmp;

  assign at_boundary  = (ptr_q == 5'd0);
  assign transmitting = os_req_valid_i && (os_req_i != RIVET_MAC_OS_NONE);
  assign cur          = at_boundary ? (transmitting ? os_req_i : RIVET_MAC_OS_NONE) : cur_q;
  assign len          = os_length(cur);
  assign set_done     = (ptr_q + 5'(SYMS)) >= len;
  assign ptr_next     = set_done ? 5'd0 : (ptr_q + 5'(SYMS));

  always_comb begin
    sym_data_o  = '0;
    sym_datak_o = '0;
    sym_tmp     = '0;
    for (int unsigned l = 0; l < LANES; l++) begin
      for (int unsigned s = 0; s < SYMS; s++) begin
        sym_tmp = os_symbol(cur, 4'(ptr_q + 5'(s)), tx_lane_num_i[8*l +: 8]);
        if (lane_en_i[l]) begin
          sym_data_o[PIPE_DATA_WIDTH*l + 8*s +: 8] = sym_tmp[7:0];
          sym_datak_o[SYMS*l + s]                  = sym_tmp[8];
        end
      end
    end
  end

  assign sym_valid_o = (cur != RIVET_MAC_OS_NONE);

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cur_q  <= RIVET_MAC_OS_NONE;
      ptr_q  <= '0;
      sent_q <= '0;
    end else begin
      cur_q <= cur;
      ptr_q <= (cur == RIVET_MAC_OS_NONE) ? 5'd0 : ptr_next;

      if (os_cnt_clr_i) begin
        sent_q <= '0;
      end else if (cur == RIVET_MAC_OS_IDLE) begin
        // Config.Idle / Recovery.Idle count Idle Symbols, not sets.
        if (sent_q < (CNT_MAX - SYMS_C)) sent_q <= sent_q + SYMS_C;
      end else if (set_done && (cur != RIVET_MAC_OS_NONE)) begin
        if (sent_q != CNT_MAX) sent_q <= sent_q + 1'b1;
      end
    end
  end

  assign os_sent_cnt_o = sent_q;

  // DLL traffic is not forwarded yet.
  assign dll_tx_ready_o = 1'b0;

  logic _unused_ok;
  assign _unused_ok = dll_tx_valid_i ^ (|dll_tx_beat_i.data);

endmodule : rivet_mac_os_tx
