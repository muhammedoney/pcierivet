// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Gen2 stub checks: PIPE Detect/P1, AXI quiet, cfg idle, companion zeros.

class rivet_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rivet_scoreboard)

  uvm_analysis_imp_pipe #(rivet_pipe_item, rivet_scoreboard)       pipe_imp;
  uvm_analysis_imp_axi  #(rivet_axi_st_item, rivet_scoreboard)     axi_imp;
  uvm_analysis_imp_cfg  #(rivet_cfg_mgmt_item, rivet_scoreboard)   cfg_imp;
  uvm_analysis_imp_comp #(rivet_companion_item, rivet_scoreboard)  comp_imp;

  int unsigned pipe_sample_count, mac_idle_ok;
  int unsigned axi_sample_count, axi_idle_ok, axi_unexpected;
  int unsigned cfg_sample_count, cfg_idle_ok, cfg_unexpected;
  int unsigned comp_sample_count, comp_idle_ok, comp_unexpected;
  bit pipe_checked, axi_checked, cfg_checked, comp_checked;
  bit ltssm_l0_mode;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(bit)::get(this, "", "ltssm_l0_mode", ltssm_l0_mode));
    pipe_imp = new("pipe_imp", this);
    axi_imp  = new("axi_imp", this);
    cfg_imp  = new("cfg_imp", this);
    comp_imp = new("comp_imp", this);
  endfunction

  function void write_pipe(rivet_pipe_item t);
    pipe_sample_count++;
    if (ltssm_l0_mode) begin
      pipe_checked = 1;
      return;
    end
    if (pipe_sample_count < 5) return;
    if (t.txelecidle !== 1'b1)
      `uvm_error(get_type_name(), $sformatf("MAC txelecidle=%0b expected 1", t.txelecidle))
    else if (t.powerdown !== 2'b10)
      `uvm_error(get_type_name(), $sformatf("MAC powerdown=%0b expected P1", t.powerdown))
    else if (t.rate !== 3'd0)
      `uvm_error(get_type_name(), $sformatf("MAC rate=%0d expected Gen1 (train rate)", t.rate))
    else if (t.as_mac_in_detect !== 1'b1)
      `uvm_error(get_type_name(), $sformatf("as_mac_in_detect=%0b expected 1", t.as_mac_in_detect))
    else
      mac_idle_ok++;
    pipe_checked = 1;
  endfunction

  function void write_axi(rivet_axi_st_item t);
    axi_sample_count++;
    if (axi_sample_count < 5) return;
    if (t.tvalid) begin
      axi_unexpected++;
      `uvm_error(get_type_name(), $sformatf("Unexpected AXI beat on %s", t.channel))
    end else
      axi_idle_ok++;
    axi_checked = 1;
  endfunction

  function void write_cfg(rivet_cfg_mgmt_item t);
    cfg_sample_count++;
    if (cfg_sample_count < 5) return;
    if (t.read || t.write) begin
      cfg_unexpected++;
      `uvm_error(get_type_name(), "Unexpected cfg_mgmt access during idle smoke")
    end else if (t.read_write_done) begin
      cfg_unexpected++;
      `uvm_error(get_type_name(), "cfg_mgmt done asserted without request")
    end else
      cfg_idle_ok++;
    cfg_checked = 1;
  endfunction

  function void write_comp(rivet_companion_item t);
    comp_sample_count++;
    if (comp_sample_count < 5) return;
    // LTSSM L0 loopback may complete InitFC and drive non-zero tfc_* — skip.
    if (ltssm_l0_mode) begin
      comp_checked = 1;
      return;
    end
    // Idle smoke (Detect/P1): RQ tag/seq stay quiet; CQ NP count is live (default
    // credits + TB cq_np_req grants) so it may be non-zero. tfc_* stay 0 until L0/FC.
    if (t.rq_seq_num_vld0 || t.rq_tag_vld0 || t.rq_tag_vld1 ||
        t.rq_tag_av !== '0 || t.tfc_nph_av !== '0 || t.tfc_npd_av !== '0) begin
      comp_unexpected++;
      `uvm_error(get_type_name(), "Companion RQ/tfc non-zero on idle smoke DUT")
    end else
      comp_idle_ok++;
    comp_checked = 1;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (ltssm_l0_mode) begin
      `uvm_info(get_type_name(), "LTSSM L0 mode — idle PIPE checks skipped (vseq owns L0)", UVM_LOW)
      return;
    end
    if (!pipe_checked || mac_idle_ok == 0)
      `uvm_error(get_type_name(), "No successful PIPE idle samples")
    else
      `uvm_info(get_type_name(), $sformatf("PIPE stub idle OK (%0d)", mac_idle_ok), UVM_LOW)

    if (!axi_checked || axi_idle_ok == 0 || axi_unexpected != 0)
      `uvm_error(get_type_name(), "AXI-ST idle check failed")
    else
      `uvm_info(get_type_name(), $sformatf("AXI-ST stub idle OK (%0d)", axi_idle_ok), UVM_LOW)

    if (!cfg_checked || cfg_idle_ok == 0 || cfg_unexpected != 0)
      `uvm_error(get_type_name(), "cfg_mgmt idle check failed")
    else
      `uvm_info(get_type_name(), $sformatf("cfg_mgmt idle OK (%0d)", cfg_idle_ok), UVM_LOW)

    if (!comp_checked || comp_idle_ok == 0 || comp_unexpected != 0)
      `uvm_error(get_type_name(), "Companion idle check failed")
    else
      `uvm_info(get_type_name(), $sformatf("Companion stub OK (%0d)", comp_idle_ok), UVM_LOW)
  endfunction
endclass : rivet_scoreboard
