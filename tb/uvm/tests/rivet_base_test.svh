// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_base_test extends uvm_test;
  `uvm_component_utils(rivet_base_test)

  rivet_env env;
  int unsigned lanes = 1;
  int unsigned gen   = 2;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
    void'(uvm_config_db#(int unsigned)::get(this, "", "gen", gen));
    env = rivet_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info(get_type_name(),
              $sformatf("Rivet base test Gen%0d x%0d", gen, lanes), UVM_LOW)
    #100ns;
    phase.drop_objection(this);
  endtask
endclass : rivet_base_test
