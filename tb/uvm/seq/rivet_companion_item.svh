// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0

class rivet_companion_item extends uvm_sequence_item;
  `uvm_object_utils(rivet_companion_item)

  bit [1:0] cq_np_req;
  bit [5:0] cq_np_req_count;
  bit [5:0] rq_seq_num0;
  bit       rq_seq_num_vld0;
  bit [9:0] rq_tag0, rq_tag1;
  bit       rq_tag_vld0, rq_tag_vld1;
  bit [3:0] rq_tag_av;
  bit [3:0] tfc_nph_av, tfc_npd_av;

  function new(string name = "rivet_companion_item");
    super.new(name);
  endfunction
endclass : rivet_companion_item
