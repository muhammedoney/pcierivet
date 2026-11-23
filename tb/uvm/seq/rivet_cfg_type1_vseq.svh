// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Read the Type 1 bridge header through cfg_mgmt. No link partner: the image
// is the reset value of the local config file.

class rivet_cfg_type1_seq extends uvm_sequence #(rivet_cfg_mgmt_item);
  `uvm_object_utils(rivet_cfg_type1_seq)

  function new(string name = "rivet_cfg_type1_seq");
    super.new(name);
  endfunction

  task do_read(bit [9:0] a, output bit [31:0] data);
    rivet_cfg_mgmt_item item;
    item = rivet_cfg_mgmt_item::type_id::create("cfg_rd");
    start_item(item);
    item.set_read(a);
    finish_item(item);
    if (!item.read_write_done)
      `uvm_error(get_type_name(), $sformatf("Read addr=0x%0h missing done", a))
    data = item.read_data;
  endtask

  task do_write(bit [9:0] a, bit [31:0] data, bit [3:0] be);
    rivet_cfg_mgmt_item item;
    item = rivet_cfg_mgmt_item::type_id::create("cfg_wr");
    start_item(item);
    item.set_write(a, data, be);
    finish_item(item);
    if (!item.read_write_done)
      `uvm_error(get_type_name(), $sformatf("Write addr=0x%0h missing done", a))
  endtask

  task body();
    bit [31:0] dw2, dw3, dw6;
    do_read(10'd2, dw2);
    if (dw2[31:8] !== 24'h060400)
      `uvm_error(get_type_name(),
        $sformatf("class/rev 0x%06h, expected 060400", dw2[31:8]))
    do_read(10'd3, dw3);
    if (dw3[23:16] !== 8'h01)
      `uvm_error(get_type_name(),
        $sformatf("header type 0x%02h, expected 01", dw3[23:16]))
    do_write(10'd6, 32'h0000_0500, 4'hF);
    do_read(10'd6, dw6);
    if (dw6[15:8] !== 8'h05)
      `uvm_error(get_type_name(),
        $sformatf("secondary bus 0x%02h, expected 05", dw6[15:8]))
    `uvm_info(get_type_name(), "Type 1 header and secondary bus OK", UVM_LOW)
  endtask
endclass : rivet_cfg_type1_seq

class rivet_cfg_type1_vseq extends uvm_sequence;
  `uvm_object_utils(rivet_cfg_type1_vseq)
  `uvm_declare_p_sequencer(rivet_virtual_sequencer)

  function new(string name = "rivet_cfg_type1_vseq");
    super.new(name);
  endfunction

  task body();
    rivet_pipe_idle_seq     pipe_idle;
    rivet_axi_st_idle_seq   cc_idle, rq_idle, cq_rdy, rc_rdy;
    rivet_cfg_type1_seq     cfg;
    rivet_companion_grant_seq comp_grant;

    pipe_idle  = rivet_pipe_idle_seq::type_id::create("pipe_idle");
    cc_idle    = rivet_axi_st_idle_seq::type_id::create("cc_idle");
    rq_idle    = rivet_axi_st_idle_seq::type_id::create("rq_idle");
    cq_rdy     = rivet_axi_st_idle_seq::type_id::create("cq_rdy");
    rc_rdy     = rivet_axi_st_idle_seq::type_id::create("rc_rdy");
    cfg        = rivet_cfg_type1_seq::type_id::create("cfg_type1");
    comp_grant = rivet_companion_grant_seq::type_id::create("comp_grant");
    pipe_idle.cycles  = 200;
    cc_idle.cycles    = 200;
    rq_idle.cycles    = 200;
    cq_rdy.cycles     = 200;
    rc_rdy.cycles     = 200;
    comp_grant.cycles = 200;

    fork
      pipe_idle.start(p_sequencer.pipe_sqr);
      cc_idle.start(p_sequencer.cc_sqr);
      rq_idle.start(p_sequencer.rq_sqr);
      cq_rdy.start(p_sequencer.cq_sqr);
      rc_rdy.start(p_sequencer.rc_sqr);
      comp_grant.start(p_sequencer.comp_sqr);
      cfg.start(p_sequencer.cfg_sqr);
    join
  endtask
endclass : rivet_cfg_type1_vseq
