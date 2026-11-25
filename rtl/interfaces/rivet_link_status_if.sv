// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Link status snapshot for UVM (cfg_ltssm_state / link_up / PIPE rate).

interface rivet_link_status_if (
  input logic pclk,
  input logic preset_n
);
  logic       link_up;
  logic [5:0] cfg_ltssm_state;
  logic [2:0] pipe_rate;
  logic [2:0] negotiated_width;
  // TB-driven requests; rivet_tb_top forces them onto the MAC (default 0).
  logic       aspm_l0s_req;
  logic       aspm_l1_req;
  logic       hot_reset_req;
  logic       link_disable_req;
  // Directed inject of one config TLP into rivet_tl_cfg. rivet_tb_top owns the handshake.
  logic       cfg_inj_go;
  logic [7:0] cfg_inj_bus;
  logic       cfg_inj_done;
  logic [7:0] cfg_inj_b0;
  logic [2:0] cfg_inj_status;
  // Present one config RQ descriptor and record whether beat 1 is refused.
  logic       rq_stall_go;
  logic       rq_stall_done;
  logic       rq_stall_pass;
  // Arm a watch on the packed RQ header byte 0. rivet_tb_top samples it.
  logic       rq_watch_arm;
  logic [7:0] rq_watch_b0;
  logic       rq_watch_hit;
  // Opt-in preset search, coefficient apply, and margin message.
  logic       eq_search;
  logic [7:0] margin_msg;
  logic       coeff_go;
  logic [5:0] coeff_value;
  logic       eq_saw_preset0;
  logic       eq_saw_preset1;
  logic [2:0] txmargin;
  logic [5:0] txeq_coeff0;
  logic [1:0] txeq_ctrl0;
  // TB forces the PIPE adapter rate (rivet_tb_top owns the force).
  logic       pipe_rate_force;
  logic [2:0] pipe_rate_value;
  // Pulse to emit eight Gen3 TX words (two 16-byte blocks) from the adapter.
  logic       block_tx_go;
  logic       block_tx_done;
  // Accepted block word, lane 0. Valid low means the byte stream held.
  // rx_word64 is the full lane word when the pipe is 64 bits.
  logic        rx_word_vld;
  logic [31:0] rx_word;
  logic [63:0] rx_word64;
  // Captured Gen3 TS fields (lane 0 in [7:0]). Scoreboard reads these.
  logic [31:0] ts_lane_num;
  logic [7:0]  ts_rate_id;
  logic [7:0]  ts_link_num;
endinterface : rivet_link_status_if
