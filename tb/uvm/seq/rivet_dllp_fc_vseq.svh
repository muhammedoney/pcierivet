// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Reach L0 then hold while peer/DUT exchange InitFC / UpdateFC DLLPs.

class rivet_dllp_fc_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_dllp_fc_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned fc_hold_cycles  = 80_000;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_dllp_fc_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")

    wait (status_vif.preset_n === 1'b1);
    prev    = 6'h3F;
    reached = 1'b0;

    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h (link_up=%0b) @%0d",
                            prev, status_vif.cfg_ltssm_state, status_vif.link_up, cyc),
                  UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1;
        break;
      end
    end

    if (!reached)
      `uvm_fatal(get_type_name(),
                 $sformatf("Did not reach L0 with link_up in %0d cycles (state=0x%02h)",
                           watchdog_cycles, status_vif.cfg_ltssm_state))

    `uvm_info(get_type_name(),
              $sformatf("Reached L0 @%0d — holding then FC window (%0d)",
                        cyc, fc_hold_cycles), UVM_LOW)

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);
    repeat (fc_hold_cycles) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state != 6'h10)
        `uvm_fatal(get_type_name(),
                   $sformatf("Left L0 during FC window (state=0x%02h)",
                             status_vif.cfg_ltssm_state))
    end

    `uvm_info(get_type_name(), "DLLP FC hold complete", UVM_LOW)
  endtask
endclass : rivet_dllp_fc_vseq
