// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rivet PCIe PHY — UltraScale+ family (wraps Xilinx PCIe PHY / PG239).
// PIPE <-> serial. Phase 0: behavioral stub (no vendor netlist in-repo).

module rivet_pcie_phy_usplus #(
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

`ifndef SYNTHESIS
  initial begin
    if (!(LANES == 1 || LANES == 2 || LANES == 4))
      $error("rivet_pcie_phy_usplus LANES must be 1, 2, or 4");
  end
`endif

  assign pipe_rxdata     = '0;
  assign pipe_rxdatak    = '0;
  assign pipe_rxvalid    = 1'b0;
  assign pipe_rxelecidle = 1'b1;
  assign pipe_rxstatus   = 3'b000;
  assign pipe_phystatus  = 1'b0;

  assign pci_exp_txp = '0;
  assign pci_exp_txn = '1;

  wire _unused = pclk ^ preset_n ^ pipe_txdetectrx ^ pipe_txelecidle ^
                 pipe_txdatavalid ^ (|pipe_txdata) ^ (|pipe_txdatak) ^
                 (|pipe_txcompliance) ^ (|pipe_powerdown) ^ (|pipe_rate) ^
                 pipe_rxpolarity ^ sys_clk ^ sys_reset_n ^
                 (|pci_exp_rxp) ^ (|pci_exp_rxn);

endmodule : rivet_pcie_phy_usplus
