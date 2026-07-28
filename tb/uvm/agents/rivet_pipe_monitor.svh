// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Samples Gen2-relevant PIPE fields each pclk after reset.

class rivet_pipe_monitor extends uvm_monitor;
  `uvm_component_utils(rivet_pipe_monitor)

  rivet_pipe_vif vif;
  uvm_analysis_port #(rivet_pipe_item) ap;
  int unsigned lanes = 1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(rivet_pipe_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_pipe_vif not set")
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
  endfunction

  task run_phase(uvm_phase phase);
    rivet_pipe_item item;
    wait (vif.preset_n === 1'b1);
    forever begin
      @(posedge vif.pclk);
      item = rivet_pipe_item::type_id::create("pipe_mon_item");
      // Lane 0 sample (sufficient for Gen2 stub smoke; widen later)
      item.rxdata           = vif.rxdata[15:0];
      item.rxdatak          = vif.rxdatak[1:0];
      item.rxvalid          = vif.rxvalid[0];
      item.rxelecidle       = vif.rxelecidle[0];
      item.rxstatus         = vif.rxstatus[2:0];
      item.phystatus        = vif.phystatus[0];
      item.phystatus_rst    = vif.phystatus_rst[0];
      item.txdata           = vif.txdata[15:0];
      item.txdatak          = vif.txdatak[1:0];
      item.txdetectrx       = vif.txdetectrx;
      item.txelecidle       = vif.txelecidle[0];
      item.powerdown        = vif.powerdown;
      item.rate             = vif.rate;
      item.as_mac_in_detect = vif.as_mac_in_detect;
      item.as_mac_in_L0     = vif.as_mac_in_L0;
      ap.write(item);
    end
  endtask
endclass : rivet_pipe_monitor
