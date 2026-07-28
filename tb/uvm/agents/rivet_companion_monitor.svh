// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Passive companion sampler (user drives cq_np_req from TB top / later sequences).

class rivet_companion_monitor extends uvm_monitor;
  `uvm_component_utils(rivet_companion_monitor)

  rivet_companion_vif vif;
  uvm_analysis_port #(rivet_companion_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(rivet_companion_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_companion_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    rivet_companion_item item;
    wait (vif.aresetn === 1'b1);
    forever begin
      @(posedge vif.aclk);
      item = rivet_companion_item::type_id::create("comp_mon");
      item.cq_np_req        = vif.cq_np_req;
      item.cq_np_req_count  = vif.cq_np_req_count;
      item.rq_seq_num0      = vif.rq_seq_num0;
      item.rq_seq_num_vld0  = vif.rq_seq_num_vld0;
      item.rq_tag0          = vif.rq_tag0;
      item.rq_tag_vld0      = vif.rq_tag_vld0;
      item.rq_tag1          = vif.rq_tag1;
      item.rq_tag_vld1      = vif.rq_tag_vld1;
      item.rq_tag_av        = vif.rq_tag_av;
      item.tfc_nph_av       = vif.tfc_nph_av;
      item.tfc_npd_av       = vif.tfc_npd_av;
      ap.write(item);
    end
  endtask
endclass : rivet_companion_monitor
