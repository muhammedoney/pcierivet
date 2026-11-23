// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Elaboration check only. Default lint stays GEN=2, 16-bit PIPE.
// This top is GEN=3, x4, 32-bit PIPE. Ports stay open; lint waives PINCONNECTEMPTY.

module rivet_gen3_lint_top;
  rivet_pcie_ctrl #(
    .MODE            (0),
    .GEN             (3),
    .LANES           (4),
    .PIPE_DATA_WIDTH (32)
  ) u ();
endmodule
