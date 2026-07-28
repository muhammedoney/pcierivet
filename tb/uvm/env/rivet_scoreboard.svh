// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Checks Phase 0/1 Gen2 MAC stub idle on PIPE (Detect / P1).

class rivet_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rivet_scoreboard)

  uvm_analysis_imp #(rivet_pipe_item, rivet_scoreboard) pipe_imp;

  int unsigned sample_count;
  int unsigned mac_idle_ok;
  bit          checked;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    pipe_imp = new("pipe_imp", this);
  endfunction

  function void write(rivet_pipe_item t);
    sample_count++;
    // After a few clocks of reset release, MAC stub must sit in Detect/P1 idle.
    if (sample_count < 5)
      return;
    if (t.txelecidle !== 1'b1)
      `uvm_error(get_type_name(), $sformatf("MAC txelecidle=%0b expected 1 (stub idle)", t.txelecidle))
    else if (t.powerdown !== 2'b10)
      `uvm_error(get_type_name(), $sformatf("MAC powerdown=%0b expected P1 (2'b10)", t.powerdown))
    else if (t.rate !== 3'd1)
      `uvm_error(get_type_name(), $sformatf("MAC rate=%0d expected Gen2 (1)", t.rate))
    else if (t.as_mac_in_detect !== 1'b1)
      `uvm_error(get_type_name(), $sformatf("as_mac_in_detect=%0b expected 1", t.as_mac_in_detect))
    else
      mac_idle_ok++;
    checked = 1;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!checked || mac_idle_ok == 0)
      `uvm_error(get_type_name(), "No successful Gen2 MAC idle PIPE samples observed")
    else
      `uvm_info(get_type_name(),
                $sformatf("PIPE stub idle OK (%0d samples)", mac_idle_ok), UVM_LOW)
  endfunction
endclass : rivet_scoreboard
