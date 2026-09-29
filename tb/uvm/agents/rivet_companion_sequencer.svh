// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_companion_sequencer extends uvm_sequencer #(rivet_companion_item);
  `uvm_component_utils(rivet_companion_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : rivet_companion_sequencer
