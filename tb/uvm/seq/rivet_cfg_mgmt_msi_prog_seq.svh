// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// cfg_mgmt: BME/MSE + MSI Message Address/Data + MSI Enable.

class rivet_cfg_mgmt_msi_prog_seq extends rivet_cfg_mgmt_rw_seq;
  `uvm_object_utils(rivet_cfg_mgmt_msi_prog_seq)

  bit [31:0] msi_addr = 32'hFEE0_0000;
  bit [15:0] msi_data = 16'h00A5;

  function new(string name = "rivet_cfg_mgmt_msi_prog_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] dw20, dw20b, dw21, dw23;

    super.body(); // Vendor/Device + BME/MSE

    do_write(10'd21, msi_addr, 4'b1111);
    do_write(10'd23, {16'h0, msi_data}, 4'b0011);
    do_read(10'd20, dw20);
    do_write(10'd20, (dw20 | 32'h0001_0000), 4'b1100);

    do_read(10'd20, dw20b);
    do_read(10'd21, dw21);
    do_read(10'd23, dw23);

    if (!dw20b[16])
      `uvm_error(get_type_name(), $sformatf("MSI Enable not set: DW20=0x%08h", dw20b))
    if (dw21 !== msi_addr)
      `uvm_error(get_type_name(), $sformatf("MSI addr mismatch: 0x%08h", dw21))
    if (dw23[15:0] !== msi_data)
      `uvm_error(get_type_name(), $sformatf("MSI data mismatch: 0x%04h", dw23[15:0]))

    `uvm_info(get_type_name(),
              $sformatf("MSI programmed addr=0x%08h data=0x%04h", msi_addr, msi_data),
              UVM_LOW)
  endtask
endclass : rivet_cfg_mgmt_msi_prog_seq
