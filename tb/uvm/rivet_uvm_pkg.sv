// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

package rivet_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Virtual PIPE IF for the lane width under test (set via +define+RIVET_TB_LANES=N).
`ifndef RIVET_TB_LANES
  `define RIVET_TB_LANES 1
`endif
  typedef virtual rivet_pipe_if #(.LANES(`RIVET_TB_LANES), .PIPE_DATA_WIDTH(16)) rivet_pipe_vif;

  `include "seq/rivet_pipe_item.svh"
  `include "seq/rivet_axi_st_item.svh"
  `include "seq/rivet_pipe_idle_seq.svh"
  `include "agents/rivet_pipe_sequencer.svh"
  `include "agents/rivet_pipe_driver.svh"
  `include "agents/rivet_pipe_monitor.svh"
  `include "agents/rivet_pipe_agent.svh"
  `include "agents/rivet_axi_st_agent.svh"
  `include "env/rivet_scoreboard.svh"
  `include "env/rivet_coverage.svh"
  `include "env/rivet_env.svh"
  `include "tests/rivet_base_test.svh"
  `include "tests/smoke_gen2_x1.svh"
  `include "tests/smoke_gen2_x2_x4.svh"
endpackage : rivet_uvm_pkg
