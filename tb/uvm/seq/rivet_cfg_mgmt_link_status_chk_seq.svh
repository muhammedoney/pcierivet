// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Read PCIe Cap Link Control/Status (DW32 @0x80) and check Negotiated Link Width.

class rivet_cfg_mgmt_link_status_chk_seq extends rivet_cfg_mgmt_rw_seq;
  `uvm_object_utils(rivet_cfg_mgmt_link_status_chk_seq)

  int unsigned expect_nlw = 4;
  bit [31:0]   link_dw;

  function new(string name = "rivet_cfg_mgmt_link_status_chk_seq");
    super.new(name);
  endfunction

  task body();
    bit [5:0] nlw;
    bit [3:0] cls;
    do_read(10'd32, link_dw);
    nlw = link_dw[25:20];
    cls = link_dw[19:16];
    if (nlw != 6'(expect_nlw))
      `uvm_error(get_type_name(),
                 $sformatf("Link Status NLW=%0d expected %0d (DW32=0x%08h)",
                           nlw, expect_nlw, link_dw))
    else
      `uvm_info(get_type_name(),
                $sformatf("Link Status NLW=%0d CLS=%0d OK", nlw, cls), UVM_LOW)
  endtask
endclass : rivet_cfg_mgmt_link_status_chk_seq
