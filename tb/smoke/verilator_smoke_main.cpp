// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Minimal C++ harness so Verilator can --build the controller stub.

#include "Vrivet_pcie_ctrl.h"
#include "verilated.h"

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vrivet_pcie_ctrl* top = new Vrivet_pcie_ctrl;
  top->user_clk = 0;
  top->user_resetn = 0;
  top->pclk = 0;
  top->preset_n = 0;
  top->eval();
  top->user_resetn = 1;
  top->preset_n = 1;
  for (int i = 0; i < 20; ++i) {
    top->user_clk = !top->user_clk;
    top->pclk = !top->pclk;
    top->eval();
  }
  delete top;
  return 0;
}
