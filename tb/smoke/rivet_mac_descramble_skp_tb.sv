// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Odd-phase SKP (COM on 16-bit symbol 1) must not lock the descrambler into
// a 15-symbol TS window — the next Logical Idle 00h must descramble.

`timescale 1ns/1ps

module rivet_mac_descramble_skp_tb;
  import rivet_pkg::*;

  localparam int unsigned LANES = 1;
  localparam int unsigned PIPE_DATA_WIDTH = 16;

  logic pclk, rst_n;
  logic [15:0] data_i, data_o;
  logic [1:0]  k_i, k_o;
  logic        valid;

  rivet_mac_descrambler #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_d (
    .pclk_i    (pclk),
    .rst_ni    (rst_n),
    .data_i    (data_i),
    .datak_i   (k_i),
    .valid_i   (valid),
    .lane_en_i (1'b1),
    .data_o    (data_o),
    .datak_o   (k_o),
    .valid_o   ()
  );

  initial pclk = 1'b0;
  always #4 pclk = ~pclk;

  initial begin
    automatic logic [23:0] st;
    automatic logic [7:0]  scr0;

    rst_n  = 1'b0;
    data_i = '0;
    k_i    = 2'b00;
    valid  = 1'b0;
    repeat (4) @(posedge pclk);
    rst_n = 1'b1;
    repeat (2) @(posedge pclk);

    // Idle D, then COM (SKP starts on the odd Symbol).
    valid  = 1'b1;
    data_i = {RIVET_SYM_COM, 8'h00};
    k_i    = 2'b10;
    @(posedge pclk);
    #1;

    data_i = {RIVET_SYM_SKP, RIVET_SYM_SKP};
    k_i    = 2'b11;
    @(posedge pclk);
    #1;

    st   = rivet_lfsr_step(RIVET_LFSR_SEED);
    scr0 = 8'h00 ^ st[7:0];
    data_i = {scr0, RIVET_SYM_SKP};
    k_i    = 2'b01;
    #1;
    if (data_o[15:8] !== 8'h00) begin
      $error("odd-SKP: first Idle after SKP not descrambled (got %02h)", data_o[15:8]);
      $fatal(1);
    end

    $display("PASS: rivet_mac_descramble_skp_tb");
    $finish;
  end

  initial begin
    #2000;
    $error("timeout");
    $fatal(1);
  end
endmodule : rivet_mac_descramble_skp_tb
