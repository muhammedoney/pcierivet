// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// PG213 companion flow-control / tracking (CQ NP + RQ tags/seq/credits).

interface rivet_companion_if (
  input logic aclk,
  input logic aresetn
);
  logic [1:0]  cq_np_req;
  logic [5:0]  cq_np_req_count;
  logic [5:0]  rq_seq_num0;
  logic        rq_seq_num_vld0;
  logic [9:0]  rq_tag0, rq_tag1;
  logic        rq_tag_vld0, rq_tag_vld1;
  logic [3:0]  rq_tag_av;
  logic [3:0]  tfc_nph_av, tfc_npd_av;

  modport user (
    input  aclk, aresetn,
    output cq_np_req,
    input  cq_np_req_count, rq_seq_num0, rq_seq_num_vld0,
           rq_tag0, rq_tag_vld0, rq_tag1, rq_tag_vld1,
           rq_tag_av, tfc_nph_av, tfc_npd_av
  );

  modport monitor (
    input aclk, aresetn,
          cq_np_req, cq_np_req_count,
          rq_seq_num0, rq_seq_num_vld0,
          rq_tag0, rq_tag_vld0, rq_tag1, rq_tag_vld1,
          rq_tag_av, tfc_nph_av, tfc_npd_av
  );
endinterface : rivet_companion_if
