// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_axi_st_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_axi_st_item)

  rand bit [63:0] tdata;
  rand bit        tlast;
  string          channel; // "cq","cc","rq","rc"

  function new(string name = "rivet_axi_st_item");
    super.new(name);
    channel = "cq";
  endfunction
endclass : rivet_axi_st_item
