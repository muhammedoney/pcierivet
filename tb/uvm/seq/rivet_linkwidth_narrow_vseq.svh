// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// DUT LANES=4; peer configures only peer_lanes (default 2) → negotiated width.

class rivet_linkwidth_narrow_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_linkwidth_narrow_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 250_000;
  int unsigned hold_l0_cycles  = 200;
  int unsigned expect_width    = 2;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_linkwidth_narrow_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;

    void'(uvm_config_db#(int unsigned)::get(null, "*", "peer_lanes", expect_width));
    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")

    wait (status_vif.preset_n === 1'b1);
    prev = 6'h3F; reached = 1'b0;
    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h width~%0d @%0d",
                            prev, status_vif.cfg_ltssm_state,
                            status_vif.negotiated_width, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1; break;
      end
    end
    if (!reached)
      `uvm_fatal(get_type_name(),
                 $sformatf("Did not reach L0 (last=0x%02h) — narrow peer failed?",
                           status_vif.cfg_ltssm_state))

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);

    if (status_vif.negotiated_width != expect_width[2:0])
      `uvm_fatal(get_type_name(),
                 $sformatf("negotiated_width=%0d expected %0d",
                           status_vif.negotiated_width, expect_width))
    if (status_vif.cfg_ltssm_state != 6'h10 || !status_vif.link_up)
      `uvm_fatal(get_type_name(), "Left L0 after narrow-width train")

    `uvm_info(get_type_name(),
              $sformatf("Link-width narrow OK: L0 @ width=%0d", expect_width),
              UVM_LOW)
  endtask
endclass : rivet_linkwidth_narrow_vseq
