// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Four Gen3 TS1 blocks. No L0. The scoreboard checks the captured fields.

class rivet_gen3_ts_seq extends uvm_sequence;
  `uvm_object_utils(rivet_gen3_ts_seq)

  function new(string name = "rivet_gen3_ts_seq");
    super.new(name);
  endfunction

  task body();
    rivet_link_status_vif status_vif;
    rivet_pipe_ltssm_peer peer;
    uvm_component peer_c;
    int unsigned i;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "status_vif not set")
    peer_c = uvm_root::get().find("uvm_test_top.env.ltssm_peer");
    if (peer_c == null || !$cast(peer, peer_c))
      `uvm_fatal(get_type_name(), "ltssm peer not found")

    wait (status_vif.preset_n === 1'b1);
    status_vif.pipe_rate_value = rivet_pkg::RIVET_PIPE_RATE_GEN3;
    status_vif.pipe_rate_force = 1'b1;
    repeat (4) @(posedge status_vif.pclk);

    for (i = 0; i < 4; i++)
      peer.drive_gen3_ts1(8'h07, 8'h0E);

    repeat (8) @(posedge status_vif.pclk);
  endtask
endclass : rivet_gen3_ts_seq
