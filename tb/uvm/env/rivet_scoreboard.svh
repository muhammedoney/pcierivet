// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Checks Gen2 MAC stub: PIPE Detect/P1 idle + AXI CQ/RC quiet.

class rivet_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rivet_scoreboard)

  uvm_analysis_imp_pipe #(rivet_pipe_item, rivet_scoreboard) pipe_imp;
  uvm_analysis_imp_axi  #(rivet_axi_st_item, rivet_scoreboard) axi_imp;

  int unsigned pipe_sample_count;
  int unsigned mac_idle_ok;
  bit          pipe_checked;

  int unsigned axi_sample_count;
  int unsigned axi_idle_ok;
  int unsigned axi_unexpected;
  bit          axi_checked;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    pipe_imp = new("pipe_imp", this);
    axi_imp  = new("axi_imp", this);
  endfunction

  function void write_pipe(rivet_pipe_item t);
    pipe_sample_count++;
    if (pipe_sample_count < 5)
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
    pipe_checked = 1;
  endfunction

  function void write_axi(rivet_axi_st_item t);
    axi_sample_count++;
    if (axi_sample_count < 5)
      return;
    // Stub DUT must not emit CQ/RC traffic; CC/RQ stay idle from TB.
    if (t.tvalid) begin
      axi_unexpected++;
      `uvm_error(get_type_name(),
                 $sformatf("Unexpected AXI-ST beat on %s during idle smoke", t.channel))
    end else begin
      axi_idle_ok++;
    end
    axi_checked = 1;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!pipe_checked || mac_idle_ok == 0)
      `uvm_error(get_type_name(), "No successful Gen2 MAC idle PIPE samples observed")
    else
      `uvm_info(get_type_name(),
                $sformatf("PIPE stub idle OK (%0d samples)", mac_idle_ok), UVM_LOW)

    if (!axi_checked || axi_idle_ok == 0)
      `uvm_error(get_type_name(), "No successful AXI-ST idle samples observed")
    else if (axi_unexpected != 0)
      `uvm_error(get_type_name(),
                 $sformatf("AXI-ST idle smoke saw %0d unexpected beats", axi_unexpected))
    else
      `uvm_info(get_type_name(),
                $sformatf("AXI-ST stub idle OK (%0d samples)", axi_idle_ok), UVM_LOW)
  endfunction
endclass : rivet_scoreboard
