// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_pipe_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_pipe_item)

  rand bit txelecidle;
  rand bit [1:0] powerdown;

  function new(string name = "rivet_pipe_item");
    super.new(name);
  endfunction
endclass : rivet_pipe_item
