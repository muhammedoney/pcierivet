// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 PIPE transaction (PHY-side stimulus + sampled MAC/PHY snapshot).

class rivet_pipe_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_pipe_item)

  // PHY -> MAC (driven by pipe agent)
  rand bit [15:0] rxdata;       // one lane @ PIPE_DATA_WIDTH=16; pack in driver for multi-lane
  rand bit [1:0]  rxdatak;
  rand bit        rxvalid;
  rand bit        rxelecidle;
  rand bit [2:0]  rxstatus;
  rand bit        phystatus;
  rand bit        phystatus_rst;

  // MAC -> PHY (monitored)
  bit [15:0] txdata;
  bit [1:0]  txdatak;
  bit        txdetectrx;
  bit        txelecidle;
  bit [1:0]  powerdown;
  bit [2:0]  rate;
  bit        as_mac_in_detect;
  bit        as_mac_in_L0;

  // Optional: apply idle defaults for Gen2 Detect stub
  function void set_phy_idle();
    rxdata        = '0;
    rxdatak       = '0;
    rxvalid       = 1'b0;
    rxelecidle    = 1'b1;
    rxstatus      = 3'b000;
    phystatus     = 1'b0;
    phystatus_rst = 1'b0;
  endfunction

  function new(string name = "rivet_pipe_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf(
      "rx{valid=%0b idle=%0b} tx{idle=%0b pd=%0b rate=%0d detect=%0b}",
      rxvalid, rxelecidle, txelecidle, powerdown, rate, as_mac_in_detect);
  endfunction
endclass : rivet_pipe_item
