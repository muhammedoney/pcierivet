// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Drive Gen2 PHY idle into MAC for Detect-stub smoke.

class rivet_pipe_idle_seq extends uvm_sequence #(rivet_pipe_item);
  `uvm_object_utils(rivet_pipe_idle_seq)

  int unsigned cycles = 20;

  function new(string name = "rivet_pipe_idle_seq");
    super.new(name);
  endfunction

  task body();
    rivet_pipe_item item;
    repeat (cycles) begin
      item = rivet_pipe_item::type_id::create("idle");
      start_item(item);
      item.set_phy_idle();
      finish_item(item);
    end
  endtask
endclass : rivet_pipe_idle_seq
