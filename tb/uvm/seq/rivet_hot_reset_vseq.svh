// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// L0 → Recovery (Hot Reset TS) → Hot_Reset → Detect → L0.

class rivet_hot_reset_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_hot_reset_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 400;
  int unsigned retrain_watch   = 200_000;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_hot_reset_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;
    bit          saw_hot;
    bit          back_l0;
    bit          fired;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")

    wait (status_vif.preset_n === 1'b1);
    prev = 6'h3F; reached = 1'b0;
    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h @%0d",
                            prev, status_vif.cfg_ltssm_state, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1; break;
      end
    end
    if (!reached)
      `uvm_fatal(get_type_name(), "Did not reach L0")

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);

    uvm_config_db#(bit)::set(null, "*", "peer_recovery_fired", 1'b0);
    uvm_config_db#(bit)::set(null, "*", "peer_hot_reset_go", 1'b1);

    saw_hot = 1'b0;
    back_l0 = 1'b0;
    for (cyc = 0; cyc < retrain_watch; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h @%0d",
                            prev, status_vif.cfg_ltssm_state, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if (status_vif.cfg_ltssm_state == 6'h27)
        saw_hot = 1'b1;
      if (saw_hot && (status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        back_l0 = 1'b1; break;
      end
    end

    void'(uvm_config_db#(bit)::get(null, "*", "peer_recovery_fired", fired));
    if (!fired)
      `uvm_fatal(get_type_name(), "Peer did not pulse Hot Reset inject")
    if (!saw_hot)
      `uvm_fatal(get_type_name(), "Did not enter Hot_Reset (0x27)")
    if (!back_l0)
      `uvm_fatal(get_type_name(), "Did not return to L0 after Hot Reset")

    `uvm_info(get_type_name(), "Hot Reset → Detect → L0 OK", UVM_LOW)
  endtask
endclass : rivet_hot_reset_vseq
