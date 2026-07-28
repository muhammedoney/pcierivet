// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_axi_st_sequencer extends uvm_sequencer #(rivet_axi_st_item);
  `uvm_component_utils(rivet_axi_st_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : rivet_axi_st_sequencer
