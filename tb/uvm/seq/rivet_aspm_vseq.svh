// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// L0 → ASPM request (forced via status_if → rivet_tb_top) → Tx_L0s / L1.Idle →
// release → L0 (L0s: FTS exit; L1: Detect retrain).

class rivet_aspm_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_aspm_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  bit          l1_mode          = 0; // 0: L0s, 1: L1
  int unsigned watchdog_cycles  = 200_000;
  int unsigned hold_l0_cycles   = 400;
  int unsigned hold_aspm_cycles = 300;
  int unsigned aspm_watch       = 20_000;
  int unsigned exit_watch       = 200_000;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_aspm_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    logic [5:0]  aspm_state;
    bit          reached;
    bit          saw_aspm;
    bit          back_l0;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")

    aspm_state = l1_mode ? 6'h18 : 6'h15;

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

    // Request ASPM entry.
    if (l1_mode) status_vif.aspm_l1_req  = 1'b1;
    else         status_vif.aspm_l0s_req = 1'b1;

    saw_aspm = 1'b0;
    for (cyc = 0; cyc < aspm_watch; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h @%0d",
                            prev, status_vif.cfg_ltssm_state, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if (status_vif.cfg_ltssm_state == aspm_state) begin
        saw_aspm = 1'b1; break;
      end
    end
    if (!saw_aspm)
      `uvm_fatal(get_type_name(),
                 $sformatf("Did not enter ASPM state 0x%02h", aspm_state))

    // Settle in the low-power state; TX must be in Electrical Idle.
    repeat (hold_aspm_cycles) @(posedge status_vif.pclk);
    if (status_vif.cfg_ltssm_state !== aspm_state)
      `uvm_fatal(get_type_name(),
                 $sformatf("Left ASPM state early: 0x%02h", status_vif.cfg_ltssm_state))
    if (status_vif.negotiated_width !== 3'd0)
      `uvm_fatal(get_type_name(),
                 $sformatf("TX not in EI during ASPM (active lanes=%0d)",
                           status_vif.negotiated_width))

    // Release the request and wait for L0.
    if (l1_mode) status_vif.aspm_l1_req  = 1'b0;
    else         status_vif.aspm_l0s_req = 1'b0;

    back_l0 = 1'b0;
    for (cyc = 0; cyc < exit_watch; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h @%0d",
                            prev, status_vif.cfg_ltssm_state, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        back_l0 = 1'b1; break;
      end
    end
    if (!back_l0)
      `uvm_fatal(get_type_name(), "Did not return to L0 after ASPM exit")

    `uvm_info(get_type_name(),
              l1_mode ? "ASPM L1 → Detect → L0 OK" : "ASPM Tx_L0s → FTS → L0 OK",
              UVM_LOW)
  endtask
endclass : rivet_aspm_vseq
