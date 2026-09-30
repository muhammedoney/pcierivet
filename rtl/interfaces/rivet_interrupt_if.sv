// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// PG213 MSI / MSI-X / AER user sideband.

interface rivet_interrupt_if (
  input logic aclk,
  input logic aresetn
);
  logic [31:0] msi_int;
  logic        msi_enable;
  logic        msi_sent;
  logic        msi_fail;
  logic [63:0] msix_address;
  logic [31:0] msix_data;
  logic        msix_int;
  logic        msix_enable;
  logic        msix_sent;
  logic        msix_fail;
  logic        err_cor_in;
  logic        err_uncor_in;
  logic        err_cor_out;
  logic        err_nonfatal_out;
  logic        err_fatal_out;

  modport user (
    input  aclk, aresetn,
    output msi_int, msix_address, msix_data, msix_int,
           err_cor_in, err_uncor_in,
    input  msi_enable, msi_sent, msi_fail,
           msix_enable, msix_sent, msix_fail,
           err_cor_out, err_nonfatal_out, err_fatal_out
  );

  modport monitor (
    input aclk, aresetn,
          msi_int, msi_enable, msi_sent, msi_fail,
          msix_address, msix_data, msix_int, msix_enable, msix_sent, msix_fail,
          err_cor_in, err_uncor_in, err_cor_out, err_nonfatal_out, err_fatal_out
  );
endinterface : rivet_interrupt_if
