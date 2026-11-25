// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Two 16-byte blocks on a 64-bit pipe. One block starts at rxstart_block 2'b10.
// The same stimulus at Gen3 rate must not enter the byte stream.

class rivet_gen4_block_seq extends uvm_sequence;
  `uvm_object_utils(rivet_gen4_block_seq)

  function new(string name = "rivet_gen4_block_seq");
    super.new(name);
  endfunction

  task automatic collect_words(
      rivet_link_status_vif status_vif,
      ref logic [63:0] got[$]
  );
    int unsigned guard;
    guard = 0;
    while ((got.size() < 4) && (guard < 400)) begin
      @(posedge status_vif.pclk);
      #1;
      if (status_vif.rx_word_vld === 1'b1)
        got.push_back(status_vif.rx_word64);
      guard++;
    end
  endtask

  task automatic drive_pair(rivet_pipe_ltssm_peer peer);
    // Header 10 starts on the Gen4 upper half. Header 01 starts on byte 0.
    peer.drive_gen3_block(2'b10, 1'b1, 8'h10, 2'b10);
    peer.drive_gen3_block(2'b01, 1'b0, 8'h50, 2'b01);
  endtask

  task body();
    rivet_link_status_vif status_vif;
    rivet_pipe_ltssm_peer peer;
    uvm_component peer_c;
    logic [63:0] got[$];
    logic [63:0] expw;
    int unsigned n, w, b, guard;
    localparam int unsigned PW = `RIVET_TB_PIPE_W;
    localparam int unsigned NW = 128 / PW;
    localparam logic [7:0] BASE0 = 8'h10;
    localparam logic [7:0] BASE1 = 8'h50;

    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", status_vif))
      `uvm_fatal(get_type_name(), "status_vif not set")
    peer_c = uvm_root::get().find("uvm_test_top.env.ltssm_peer");
    if (peer_c == null || !$cast(peer, peer_c))
      `uvm_fatal(get_type_name(), "ltssm peer not found")

    wait (status_vif.preset_n === 1'b1);
    status_vif.pipe_rate_value = rivet_pkg::RIVET_PIPE_RATE_GEN3;
    status_vif.pipe_rate_force = 1'b1;
    repeat (4) @(posedge status_vif.pclk);

    fork
      drive_pair(peer);
      collect_words(status_vif, got);
    join
    if (got.size() != 0)
      `uvm_error(get_type_name(),
        $sformatf("Gen3 rate accepted %0d words from a block that starts at 10",
                  got.size()))

    got.delete();
    status_vif.pipe_rate_value = rivet_pkg::RIVET_PIPE_RATE_GEN4;
    repeat (4) @(posedge status_vif.pclk);

    fork
      drive_pair(peer);
      collect_words(status_vif, got);
    join

    if (got.size() != (2*NW))
      `uvm_error(get_type_name(),
        $sformatf("Gen4 byte stream length %0d, expected %0d", got.size(), 2*NW))
    n = 0;
    for (int unsigned blk = 0; blk < 2; blk++) begin
      logic [7:0] base;
      base = (blk == 0) ? BASE0 : BASE1;
      for (w = 0; w < NW; w++) begin
        expw = '0;
        for (b = 0; b < (PW/8); b++)
          expw[8*b +: 8] = base + 8'(w*(PW/8) + b);
        if (n < got.size() && (got[n] !== expw))
          `uvm_error(get_type_name(),
            $sformatf("byte stream word %0d got %h exp %h", n, got[n], expw))
        n++;
      end
    end

    status_vif.block_tx_go = 1'b1;
    guard = 0;
    while ((status_vif.block_tx_done !== 1'b1) && (guard < 40)) begin
      @(posedge status_vif.pclk);
      guard++;
    end
    status_vif.block_tx_go = 1'b0;
    if (status_vif.block_tx_done !== 1'b1)
      `uvm_error(get_type_name(), "Gen4 TX block pulse did not finish")
    repeat (4) @(posedge status_vif.pclk);
  endtask
endclass : rivet_gen4_block_seq
