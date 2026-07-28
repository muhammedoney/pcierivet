// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Drive idle (tvalid=0) or beats on CC/RQ; hold tready on CQ/RC.

class rivet_axi_st_idle_seq extends uvm_sequence #(rivet_axi_st_item);
  `uvm_object_utils(rivet_axi_st_idle_seq)

  int unsigned cycles = 20;

  function new(string name = "rivet_axi_st_idle_seq");
    super.new(name);
  endfunction

  task body();
    rivet_axi_st_item item;
    repeat (cycles) begin
      item = rivet_axi_st_item::type_id::create("idle");
      start_item(item);
      item.set_idle();
      finish_item(item);
    end
  endtask
endclass : rivet_axi_st_idle_seq
