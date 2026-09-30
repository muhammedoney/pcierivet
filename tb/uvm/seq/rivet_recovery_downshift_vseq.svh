// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// L0 @ Gen1 → Recovery.Speed → L0 @ Gen2, then a second Recovery with peer
// speed-change → Recovery.Speed → L0 @ Gen1 (Gen2→Gen1 downshift).

class rivet_recovery_downshift_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_recovery_downshift_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  int unsigned watchdog_cycles = 200_000;
  int unsigned hold_l0_cycles  = 400;
  int unsigned recovery_watch  = 200_000;

  rivet_link_status_vif status_vif;

  function new(string name = "rivet_recovery_downshift_vseq");
    super.new(name);
  endfunction

  // Trigger one peer Recovery and wait for Recovery.Speed → L0 at exp_rate.
  task automatic recovery_to_rate(input string tag,
                                  input logic [2:0] exp_rate,
                                  inout logic [5:0] prev);
    int unsigned cyc;
    bit          saw_speed;
    bit          back_l0;
    bit          fired;

    uvm_config_db#(bit)::set(null, "*", "peer_recovery_fired", 1'b0);
    uvm_config_db#(bit)::set(null, "*", "peer_recovery_go", 1'b1);

    saw_speed = 1'b0;
    back_l0   = 1'b0;
    for (cyc = 0; cyc < recovery_watch; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("[%s] LTSSM 0x%02h -> 0x%02h rate=%0d @%0d",
                            tag, prev, status_vif.cfg_ltssm_state,
                            status_vif.pipe_rate, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if (status_vif.cfg_ltssm_state == 6'h0C)
        saw_speed = 1'b1;
      if (saw_speed && (status_vif.cfg_ltssm_state == 6'h10) &&
          status_vif.link_up && (status_vif.pipe_rate == exp_rate)) begin
        back_l0 = 1'b1; break;
      end
      if (status_vif.cfg_ltssm_state == 6'h00 && saw_speed)
        `uvm_fatal(get_type_name(),
                   $sformatf("[%s] Recovery.Speed timed out to Detect.Quiet", tag))
    end

    void'(uvm_config_db#(bit)::get(null, "*", "peer_recovery_fired", fired));
    if (!fired)
      `uvm_fatal(get_type_name(), $sformatf("[%s] Peer did not pulse RxValid drop", tag))
    if (!saw_speed)
      `uvm_fatal(get_type_name(), $sformatf("[%s] Did not enter Recovery.Speed", tag))
    if (!back_l0)
      `uvm_fatal(get_type_name(),
                 $sformatf("[%s] Did not return to L0 at rate %0d", tag, exp_rate))
  endtask

  task body();
    int unsigned cyc;
    logic [5:0]  prev;
    bit          reached;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")

    wait (status_vif.preset_n === 1'b1);
    prev = 6'h3F; reached = 1'b0;
    for (cyc = 0; cyc < watchdog_cycles; cyc++) begin
      @(posedge status_vif.pclk);
      if (status_vif.cfg_ltssm_state !== prev) begin
        `uvm_info(get_type_name(),
                  $sformatf("LTSSM 0x%02h -> 0x%02h rate=%0d @%0d",
                            prev, status_vif.cfg_ltssm_state,
                            status_vif.pipe_rate, cyc), UVM_LOW)
        prev = status_vif.cfg_ltssm_state;
      end
      if ((status_vif.cfg_ltssm_state == 6'h10) && status_vif.link_up) begin
        reached = 1'b1; break;
      end
    end
    if (!reached)
      `uvm_fatal(get_type_name(), "Did not reach L0")
    if (status_vif.pipe_rate !== 3'd0)
      `uvm_fatal(get_type_name(),
                 $sformatf("Expected Gen1 train rate at first L0, got %0d",
                           status_vif.pipe_rate))

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);

    // Gen1 → Gen2
    recovery_to_rate("up", 3'd1, prev);
    `uvm_info(get_type_name(), "Recovery.Speed Gen1→Gen2 OK", UVM_LOW)

    repeat (hold_l0_cycles) @(posedge status_vif.pclk);

    // Gen2 → Gen1 (second Recovery; peer still sets speed-change)
    recovery_to_rate("down", 3'd0, prev);
    `uvm_info(get_type_name(), "Recovery.Speed Gen2→Gen1 downshift OK", UVM_LOW)
  endtask
endclass : rivet_recovery_downshift_vseq
