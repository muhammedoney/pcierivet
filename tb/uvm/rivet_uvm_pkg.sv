// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

package rivet_uvm_pkg;
  import uvm_pkg::*;
  import rivet_pkg::*;
  `include "uvm_macros.svh"

`ifndef RIVET_TB_LANES
  `define RIVET_TB_LANES 1
`endif
  typedef virtual rivet_pipe_if #(.LANES(`RIVET_TB_LANES), .PIPE_DATA_WIDTH(16)) rivet_pipe_vif;
  typedef virtual rivet_link_status_if rivet_link_status_vif;
  typedef virtual rivet_axi_st_if #(
    .DATA_WIDTH(64), .KEEP_WIDTH(2), .USER_WIDTH(88), .READY_WIDTH(4)
  ) rivet_axi_st_vif;
  typedef virtual rivet_cfg_mgmt_if rivet_cfg_mgmt_vif;
  typedef virtual rivet_companion_if rivet_companion_vif;

  `uvm_analysis_imp_decl(_pipe)
  `uvm_analysis_imp_decl(_axi)
  `uvm_analysis_imp_decl(_cfg)
  `uvm_analysis_imp_decl(_comp)
  `uvm_analysis_imp_decl(_dllp)

  `include "seq/rivet_pipe_item.svh"
  `include "seq/rivet_axi_st_item.svh"
  `include "seq/rivet_cfg_mgmt_item.svh"
  `include "seq/rivet_companion_item.svh"
  `include "seq/rivet_dllp_item.svh"
  `include "seq/rivet_dllp_util.svh"
  `include "seq/rivet_axi_tlp_util.svh"
  `include "seq/rivet_pipe_idle_seq.svh"
  `include "seq/rivet_axi_st_idle_seq.svh"
  `include "seq/rivet_cfg_mgmt_idle_seq.svh"
  `include "seq/rivet_cfg_mgmt_rw_seq.svh"
  `include "seq/rivet_companion_grant_seq.svh"
  `include "seq/rivet_axi_rq_memwr32_seq.svh"
  `include "seq/rivet_axi_cc_cpld_seq.svh"
  `include "agents/rivet_pipe_sequencer.svh"
  `include "agents/rivet_pipe_driver.svh"
  `include "agents/rivet_pipe_monitor.svh"
  `include "agents/rivet_pipe_agent.svh"
  `include "agents/rivet_pipe_ltssm_peer.svh"
  `include "agents/rivet_pipe_dllp_monitor.svh"
  `include "agents/rivet_axi_st_sequencer.svh"
  `include "agents/rivet_axi_st_driver.svh"
  `include "agents/rivet_axi_st_monitor.svh"
  `include "agents/rivet_axi_st_agent.svh"
  `include "agents/rivet_cfg_mgmt_sequencer.svh"
  `include "agents/rivet_cfg_mgmt_driver.svh"
  `include "agents/rivet_cfg_mgmt_monitor.svh"
  `include "agents/rivet_cfg_mgmt_agent.svh"
  `include "agents/rivet_companion_sequencer.svh"
  `include "agents/rivet_companion_driver.svh"
  `include "agents/rivet_companion_monitor.svh"
  `include "agents/rivet_companion_agent.svh"
  `include "env/rivet_virtual_sequencer.svh"
  `include "seq/rivet_idle_smoke_vseq.svh"
  `include "seq/rivet_cfg_mgmt_vseq.svh"
  `include "seq/rivet_ltssm_l0_vseq.svh"
  `include "seq/rivet_dllp_fc_vseq.svh"
  `include "seq/rivet_tlp_rq_memwr_vseq.svh"
  `include "seq/rivet_cfg_mgmt_after_l0_vseq.svh"
  `include "env/rivet_scoreboard.svh"
  `include "env/rivet_coverage.svh"
  `include "env/rivet_env.svh"
  `include "tests/rivet_base_test.svh"
  `include "tests/smoke_gen2_x1.svh"
  `include "tests/smoke_gen2_x2_x4.svh"
  `include "tests/smoke_cfg_mgmt_gen2_x1.svh"
  `include "tests/smoke_cfg_mgmt_gen2_x4.svh"
  `include "tests/ltssm_l0_gen2.svh"
  `include "tests/smoke_dllp_fc_gen2_x1.svh"
  `include "tests/smoke_dllp_fc_gen2_x4.svh"
  `include "tests/smoke_tlp_rq_memwr_gen2_x1.svh"
  `include "tests/smoke_tlp_rq_memwr_gen2_x4.svh"
endpackage : rivet_uvm_pkg

