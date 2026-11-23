// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Must fail elaboration: GEN=3 with a 16-bit pipe. Not part of scripts/lint.ps1.

module rivet_gen3_bad_width;
  /* verilator lint_off PINMISSING */
  rivet_pcie_ctrl #(
    .MODE            (0),
    .GEN             (3),
    .LANES           (4),
    .PIPE_DATA_WIDTH (16)
  ) u ();
  /* verilator lint_on PINMISSING */
endmodule
