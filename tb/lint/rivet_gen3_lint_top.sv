// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Elaboration check only. Default lint stays GEN=2, 16-bit PIPE.
// This top is GEN=3, x4, 32-bit PIPE. Ports stay open; PINMISSING is waived here.

module rivet_gen3_lint_top;
  // Pins stay open. This top only checks that GEN=3, x4, 32-bit PIPE elaborates.
  /* verilator lint_off PINMISSING */
  rivet_pcie_ctrl #(
    .MODE            (0),
    .GEN             (3),
    .LANES           (4),
    .PIPE_DATA_WIDTH (32)
  ) u ();
  /* verilator lint_on PINMISSING */
endmodule
