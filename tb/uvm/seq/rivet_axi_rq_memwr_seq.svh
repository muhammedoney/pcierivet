// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// One posted MemWr32 on RQ, payload_dw dwords, beats issued back to back.

class rivet_axi_rq_memwr_seq extends uvm_sequence #(rivet_axi_st_item);
  `uvm_object_utils(rivet_axi_rq_memwr_seq)

  int unsigned payload_dw = 1;
  bit [31:0]   addr = 32'h0000_1000;
  // Nonzero selects a 64-bit-address MemWr (TLP type 0x60).
  bit [31:0]   addr_hi = 32'h0;
  bit [7:0]    tag  = 8'h00;
  bit [15:0]   requester_id = 16'h0100;

  function new(string name = "rivet_axi_rq_memwr_seq");
    super.new(name);
  endfunction

  task body();
    rivet_axi_st_item item;
    logic [63:0] b0, b1;
    int unsigned sent;
    int unsigned axi_w;

    if (payload_dw == 0 || payload_dw > 1024)
      `uvm_fatal(get_type_name(),
        $sformatf("payload_dw %0d is outside 1..1024", payload_dw))

    if (!uvm_config_db#(int unsigned)::get(m_sequencer, "", "axi_data_width", axi_w))
      axi_w = 64;

    item = rivet_axi_st_item::type_id::create("rq_burst");
    start_item(item);
    item.channel    = "rq";
    item.use_burst  = 1'b1;
    item.burst_user = rivet_axi_tlp_util::rq_tuser(4'hF,
                          (payload_dw > 1) ? 4'hF : 4'h0);
    rivet_axi_tlp_util::pack_mem_desc_2beat(
      addr, payload_dw[10:0], rivet_pkg::RIVET_CQ_REQ_MEMWR, tag, requester_id,
      b0, b1, addr_hi);
    if (axi_w == 128) begin
      item.burst_data.push_back({b1, b0});
      item.burst_keep.push_back(4'hF);
      item.burst_last.push_back(1'b0);
      sent = 0;
      while (sent < payload_dw) begin
        logic [127:0] beat;
        logic [3:0]   keep;
        int unsigned  n;
        beat = '0;
        keep = '0;
        n    = 0;
        while ((n < 4) && ((sent + n) < payload_dw)) begin
          beat[32*n +: 32] = 32'hA500_0000 + sent + n;
          keep[n] = 1'b1;
          n++;
        end
        item.burst_data.push_back(beat);
        item.burst_keep.push_back(keep);
        sent += n;
        item.burst_last.push_back(sent >= payload_dw);
      end
    end else begin
      item.burst_data.push_back(b0);
      item.burst_keep.push_back(2'b11);
      item.burst_last.push_back(1'b0);
      item.burst_data.push_back(b1);
      item.burst_keep.push_back(2'b11);
      item.burst_last.push_back(1'b0);

      sent = 0;
      while (sent < payload_dw) begin
        bit          two;
        logic [31:0] d0, d1;
        two = (sent + 1) < payload_dw;
        d0  = 32'hA500_0000 + sent;
        d1  = 32'hA500_0000 + sent + 1;
        item.burst_data.push_back(two ? {d1, d0} : {32'h0, d0});
        item.burst_keep.push_back(two ? 2'b11 : 2'b01);
        sent += two ? 2 : 1;
        item.burst_last.push_back(sent >= payload_dw);
      end
    end
    finish_item(item);
  endtask
endclass : rivet_axi_rq_memwr_seq
