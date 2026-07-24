// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// AXI-Lite config/status skeleton (CSR logic lands in Phase 1+).

interface rivet_axil_if #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32
) (
  input logic aclk,
  input logic aresetn
);

  logic [ADDR_WIDTH-1:0] awaddr;
  logic                  awvalid;
  logic                  awready;
  logic [DATA_WIDTH-1:0] wdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic                  wvalid;
  logic                  wready;
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;
  logic [ADDR_WIDTH-1:0] araddr;
  logic                  arvalid;
  logic                  arready;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid;
  logic                  rready;

  modport slave (
    input  aclk, aresetn,
    input  awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready,
    output awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
  );

  modport master (
    input  aclk, aresetn,
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready,
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
  );

  modport monitor (
    input aclk, aresetn,
          awaddr, awvalid, awready, wdata, wstrb, wvalid, wready,
          bresp, bvalid, bready, araddr, arvalid, arready,
          rdata, rresp, rvalid, rready
  );

endinterface : rivet_axil_if
