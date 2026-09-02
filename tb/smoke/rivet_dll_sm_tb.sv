// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// DL SM: accept → Init; fc_done → Active; replay_req → Replay → done → Active.

`timescale 1ns/1ps

module rivet_dll_sm_tb;
  import rivet_pkg::*;

  logic clk, rst_n;
  rivet_mac_dll_sb_t mac;
  logic fc_done, replay_req, replay_done;
  rivet_dl_state_e state;
  logic dl_up, tlp_en, replay_en, fc_en;

  rivet_dll_sm u_dut (
    .pclk_i(clk), .rst_ni(rst_n),
    .mac_sb_i(mac),
    .fc_init_done_i(fc_done),
    .replay_req_i(replay_req),
    .replay_done_i(replay_done),
    .state_o(state),
    .dl_up_o(dl_up),
    .tlp_tx_en_o(tlp_en),
    .replay_en_o(replay_en),
    .fc_en_o(fc_en)
  );

  initial clk = 1'b0;
  always #4 clk = ~clk;

  initial begin
    rst_n = 1'b0;
    mac = '0;
    fc_done = 1'b0;
    replay_req = 1'b0;
    replay_done = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    if (state !== RIVET_DL_INACTIVE) $fatal(1, "expect Inactive");

    mac.accept_dll_tlp = 1'b1;
    mac.link_up = 1'b1;
    @(posedge clk);
    @(posedge clk);
    if (state !== RIVET_DL_INIT || !fc_en) $fatal(1, "expect Init");

    fc_done = 1'b1;
    @(posedge clk);
    @(posedge clk);
    if (state !== RIVET_DL_ACTIVE || !tlp_en || !dl_up) $fatal(1, "expect Active+dl_up");

    replay_req = 1'b1;
    @(posedge clk);
    replay_req = 1'b0;
    @(posedge clk);
    if (state !== RIVET_DL_REPLAY || !replay_en || !dl_up) $fatal(1, "expect Replay+dl_up");

    replay_done = 1'b1;
    @(posedge clk);
    replay_done = 1'b0;
    @(posedge clk);
    if (state !== RIVET_DL_ACTIVE || !dl_up) $fatal(1, "expect Active after replay");

    mac.accept_dll_tlp = 1'b0;
    @(posedge clk);
    @(posedge clk);
    if (state !== RIVET_DL_INACTIVE || dl_up) $fatal(1, "expect Inactive on drop");

    $display("PASS: rivet_dll_sm_tb");
    $finish;
  end
endmodule : rivet_dll_sm_tb
