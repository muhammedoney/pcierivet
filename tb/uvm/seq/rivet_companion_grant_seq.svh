// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Drive pcie_cq_np_req grants (PG213 companion).

class rivet_companion_grant_seq extends uvm_sequence #(rivet_companion_item);
  `uvm_object_utils(rivet_companion_grant_seq)

  int unsigned cycles = 40;
  bit [1:0]    grant  = 2'b01;

  function new(string name = "rivet_companion_grant_seq");
    super.new(name);
  endfunction

  task body();
    rivet_companion_item item;
    repeat (cycles) begin
      item = rivet_companion_item::type_id::create("comp_grant");
      start_item(item);
      item.cq_np_req = grant;
      finish_item(item);
    end
  endtask
endclass : rivet_companion_grant_seq
