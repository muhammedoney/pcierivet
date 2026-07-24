// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// AXI-Stream channel skeleton (PG213-style naming conventions).
// Used for CQ / CC / RQ / RC. Direction is set by modport at the DUT boundary.

interface rivet_axi_st_if #(
  parameter int unsigned DATA_WIDTH = 64,
  parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8,
  parameter int unsigned USER_WIDTH = 1
) (
  input logic aclk,
  input logic aresetn
);

  logic [DATA_WIDTH-1:0] tdata;
  logic [KEEP_WIDTH-1:0] tkeep;
  logic                  tlast;
  logic                  tvalid;
  logic                  tready;
  logic [USER_WIDTH-1:0] tuser;

  modport master (
    input  aclk, aresetn,
    output tdata, tkeep, tlast, tvalid, tuser,
    input  tready
  );

  modport slave (
    input  aclk, aresetn,
    input  tdata, tkeep, tlast, tvalid, tuser,
    output tready
  );

  modport monitor (
    input aclk, aresetn, tdata, tkeep, tlast, tvalid, tready, tuser
  );

endinterface : rivet_axi_st_if
