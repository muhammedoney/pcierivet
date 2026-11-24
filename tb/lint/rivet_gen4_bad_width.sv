// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Must fail elaboration: GEN=4 with a 32-bit pipe. Not part of scripts/lint.ps1.

module rivet_gen4_bad_width;
  /* verilator lint_off PINMISSING */
  rivet_pcie_ctrl #(
    .MODE            (0),
    .GEN             (4),
    .LANES           (4),
    .PIPE_DATA_WIDTH (32)
  ) u ();
  /* verilator lint_on PINMISSING */
endmodule
