// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Read Device Status (DW30) and require CED/NFED sticky bits.

class rivet_cfg_mgmt_dev_status_chk_seq extends rivet_cfg_mgmt_rw_seq;
  `uvm_object_utils(rivet_cfg_mgmt_dev_status_chk_seq)

  bit expect_ced = 1'b1;
  bit expect_nfed = 1'b1;
  bit [31:0] dw30;

  function new(string name = "rivet_cfg_mgmt_dev_status_chk_seq");
    super.new(name);
  endfunction

  task body();
    do_read(10'd30, dw30);
    if (expect_ced && !dw30[16])
      `uvm_error(get_type_name(), $sformatf("Device Status CED clear: 0x%08h", dw30))
    if (expect_nfed && !dw30[17])
      `uvm_error(get_type_name(), $sformatf("Device Status NFED clear: 0x%08h", dw30))
    `uvm_info(get_type_name(), $sformatf("Device Status=0x%08h", dw30), UVM_LOW)
  endtask
endclass : rivet_cfg_mgmt_dev_status_chk_seq
