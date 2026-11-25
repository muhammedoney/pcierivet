// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_axi_st_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_axi_st_item)

  rand bit [255:0] tdata;
  rand bit [7:0]   tkeep;   // Dword keep. Gen2 uses 2, Gen3 uses 4, Gen4 uses 8.
  rand bit        tlast;
  rand bit        tvalid;
  rand bit [3:0]  tready;
  rand bit [87:0] tuser;   // max PG213 CQ width; narrower channels use LSBs
  string          channel; // "cq","cc","rq","rc"
  // One item, many beats, valid held across accepts. Default path is unchanged.
  bit             use_burst;
  bit [255:0]     burst_data[$];
  bit [7:0]       burst_keep[$];
  bit             burst_last[$];
  bit [87:0]      burst_user;
  // Per-beat tuser. Empty means every beat uses burst_user.
  bit [87:0]      burst_user_q[$];

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
