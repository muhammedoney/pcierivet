// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rivet PCIe PHY — UltraScale family (PG239-class). Phase 0 shares US+ stub.

module rivet_pcie_phy_us #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16
) (
  input  logic                             pclk,
  input  logic                             preset_n,
  input  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata,
  input  logic [LANES-1:0]                 pipe_txdatak,
  input  logic                             pipe_txdetectrx,
  input  logic                             pipe_txelecidle,
  input  logic [LANES-1:0]                 pipe_txcompliance,
  input  logic                             pipe_txdatavalid,
  output logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata,
  output logic [LANES-1:0]                 pipe_rxdatak,
  output logic                             pipe_rxvalid,
  output logic                             pipe_rxelecidle,
  output logic [2:0]                       pipe_rxstatus,
  output logic                             pipe_phystatus,
  input  logic [1:0]                       pipe_powerdown,
  input  logic [2:0]                       pipe_rate,
  input  logic                             pipe_rxpolarity,
  output logic [LANES-1:0]                 pci_exp_txp,
  output logic [LANES-1:0]                 pci_exp_txn,
  input  logic [LANES-1:0]                 pci_exp_rxp,
  input  logic [LANES-1:0]                 pci_exp_rxn,
  input  logic                             sys_clk,
  input  logic                             sys_reset_n
);

  rivet_pcie_phy_usplus #(
    .LANES(LANES),
    .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)
  ) u_stub (
    .pclk(pclk),
    .preset_n(preset_n),
    .pipe_txdata(pipe_txdata),
    .pipe_txdatak(pipe_txdatak),
    .pipe_txdetectrx(pipe_txdetectrx),
    .pipe_txelecidle(pipe_txelecidle),
    .pipe_txcompliance(pipe_txcompliance),
    .pipe_txdatavalid(pipe_txdatavalid),
    .pipe_rxdata(pipe_rxdata),
    .pipe_rxdatak(pipe_rxdatak),
    .pipe_rxvalid(pipe_rxvalid),
    .pipe_rxelecidle(pipe_rxelecidle),
    .pipe_rxstatus(pipe_rxstatus),
    .pipe_phystatus(pipe_phystatus),
    .pipe_powerdown(pipe_powerdown),
    .pipe_rate(pipe_rate),
    .pipe_rxpolarity(pipe_rxpolarity),
    .pci_exp_txp(pci_exp_txp),
    .pci_exp_txn(pci_exp_txn),
    .pci_exp_rxp(pci_exp_rxp),
    .pci_exp_rxn(pci_exp_rxn),
    .sys_clk(sys_clk),
    .sys_reset_n(sys_reset_n)
  );

endmodule : rivet_pcie_phy_us
