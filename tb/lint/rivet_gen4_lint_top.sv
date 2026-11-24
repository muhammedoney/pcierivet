// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Elaboration check only. Default lint stays GEN=2, 16-bit PIPE.
// This top is GEN=4, x4, 64-bit PIPE. Ports stay open; PINMISSING is waived here.

module rivet_gen4_lint_top;
  // Pins stay open. This top only checks that GEN=4, x4, 64-bit PIPE elaborates.
  /* verilator lint_off PINMISSING */
  rivet_pcie_ctrl #(
    .MODE            (0),
    .GEN             (4),
    .LANES           (4),
    .PIPE_DATA_WIDTH (64),
    .AXI_DATA_WIDTH  (128)
  ) u ();
  /* verilator lint_on PINMISSING */
endmodule
