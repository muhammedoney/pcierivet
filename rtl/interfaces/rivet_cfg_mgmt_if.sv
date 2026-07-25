// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PG213-style Configuration Management interface (Table 26).
// Replaces AXI-Lite for config-space R/W on the Rivet user boundary.

interface rivet_cfg_mgmt_if (
  input logic aclk,
  input logic aresetn
);

  logic [9:0]  addr;
  logic [7:0]  function_number;
  logic        write;
  logic [31:0] write_data;
  logic [3:0]  byte_enable;
  logic        read;
  logic [31:0] read_data;
  logic        read_write_done;
  logic        debug_access; // RP Type-1 RO force-write; no-op in EP

  modport master (
    input  aclk, aresetn,
    output addr, function_number, write, write_data, byte_enable, read, debug_access,
    input  read_data, read_write_done
  );

  modport slave (
    input  aclk, aresetn,
    input  addr, function_number, write, write_data, byte_enable, read, debug_access,
    output read_data, read_write_done
  );

  modport monitor (
    input aclk, aresetn,
          addr, function_number, write, write_data, byte_enable, read,
          read_data, read_write_done, debug_access
  );

endinterface : rivet_cfg_mgmt_if
