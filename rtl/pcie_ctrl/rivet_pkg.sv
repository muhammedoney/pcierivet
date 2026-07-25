// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Common parameters and types for Rivet soft PCIe controller.

package rivet_pkg;

  typedef enum int unsigned {
    RIVET_MODE_EP  = 0, // Endpoint
    RIVET_MODE_RC  = 1, // Root Complex / Root Port
    RIVET_MODE_USP = 2, // Switch Upstream Port
    RIVET_MODE_DSP = 3  // Switch Downstream Port
  } rivet_mode_e;

  typedef enum int unsigned {
    RIVET_GEN2 = 2,
    RIVET_GEN4 = 4,
    RIVET_GEN5 = 5
  } rivet_gen_e;

  function automatic bit rivet_lanes_legal(int unsigned lanes);
    return (lanes == 1) || (lanes == 2) || (lanes == 4);
  endfunction

  // Default AXI-ST data width for Gen2 stub (widens with gen/lanes later).
  localparam int unsigned RIVET_AXI_DATA_WIDTH_DEFAULT = 64;
  localparam int unsigned RIVET_AXI_KEEP_WIDTH_DEFAULT = RIVET_AXI_DATA_WIDTH_DEFAULT / 8;

  // PIPE per-lane data width (bits). Gen2 default 16; US+ PHY pins up to 64.
  localparam int unsigned RIVET_PIPE_DATA_WIDTH_DEFAULT = 16;
  localparam int unsigned RIVET_PIPE_DATAK_WIDTH_PER_LANE = 2;
  localparam int unsigned RIVET_PIPE_RXSTATUS_WIDTH_PER_LANE = 3;

endpackage : rivet_pkg
