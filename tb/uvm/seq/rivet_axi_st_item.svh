// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_axi_st_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_axi_st_item)

  rand bit [63:0] tdata;
  rand bit [1:0]  tkeep;   // Dword-granular @ 64-bit
  rand bit        tlast;
  rand bit        tvalid;
  rand bit [3:0]  tready;
  rand bit [87:0] tuser;   // max PG213 CQ width; narrower channels use LSBs
  string          channel; // "cq","cc","rq","rc"

  function new(string name = "rivet_axi_st_item");
    super.new(name);
    channel = "cq";
  endfunction

  function void set_idle();
    tdata  = '0;
    tkeep  = '0;
    tlast  = 1'b0;
    tvalid = 1'b0;
    tuser  = '0;
    tready = 4'hF;
  endfunction

  function string convert2string();
    return $sformatf("%s v=%0b last=%0b data=0x%016h", channel, tvalid, tlast, tdata);
  endfunction
endclass : rivet_axi_st_item
