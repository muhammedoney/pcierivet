// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// PIPE PHY-side driver (drives RX/status into MAC).

class rivet_pipe_driver extends uvm_driver #(rivet_pipe_item);
  `uvm_component_utils(rivet_pipe_driver)

  rivet_pipe_vif vif;
  int unsigned lanes = 1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rivet_pipe_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_pipe_vif not set")
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
  endfunction

  task run_phase(uvm_phase phase);
    rivet_pipe_item req;
    drive_idle();
    wait (vif.preset_n === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_idle();
    vif.rxdata          <= '0;
    vif.rxdatak         <= '0;
    vif.rxdata_valid    <= '0;
    vif.rxstart_block   <= '0;
    vif.rxsync_header   <= '0;
    vif.rxvalid         <= '0;
    vif.rxelecidle      <= '1;
    vif.rxstatus        <= '0;
    vif.phystatus       <= '0;
    vif.phystatus_rst   <= '0;
    vif.txeq_fs         <= '0;
    vif.txeq_lf         <= '0;
    vif.txeq_new_coeff  <= '0;
    vif.txeq_done       <= '0;
    vif.rxeq_preset_sel <= '0;
    vif.rxeq_new_txcoeff<= '0;
    vif.rxeq_adapt_done <= '0;
    vif.rxeq_done       <= '0;
  endtask

  task drive_item(rivet_pipe_item req);
    int unsigned i;
    @(posedge vif.pclk);
    // Replicate lane-0 stimulus across active lanes for Gen2 smoke
    for (i = 0; i < lanes; i++) begin
      vif.rxdata[i*16 +: 16] <= req.rxdata;
      vif.rxdatak[i*2 +: 2]  <= req.rxdatak;
      vif.rxvalid[i]         <= req.rxvalid;
      vif.rxelecidle[i]      <= req.rxelecidle;
      vif.rxstatus[i*3 +: 3] <= req.rxstatus;
      vif.phystatus[i]       <= req.phystatus;
      vif.phystatus_rst[i]   <= req.phystatus_rst;
    end
  endtask
endclass : rivet_pipe_driver
