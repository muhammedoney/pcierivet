// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Descramble DUT TX PIPE, reassemble SDP..END DLLPs, publish analysis items.

class rivet_pipe_dllp_monitor extends uvm_monitor;
  `uvm_component_utils(rivet_pipe_dllp_monitor)

  rivet_pipe_vif vif;
  uvm_analysis_port #(rivet_dllp_item) ap;
  int unsigned lanes = 1;
  bit          enable = 0;

  logic [15:0] lfsr[];

  // Reassembly buffer (max framed DLLP = 8 symbols).
  logic [7:0]  byte_q[$];
  bit          collecting;
  int unsigned collect_need; // remaining D-bytes after SDP (6) then END

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    void'(uvm_config_db#(bit)::get(this, "", "dllp_mon_enable", enable));
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
    if (!enable) return;
    if (!uvm_config_db#(rivet_pipe_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_pipe_vif not set")
  endfunction

  function automatic logic [23:0] lfsr_step(input logic [15:0] lfsr_in);
    return rivet_pkg::rivet_lfsr_step(lfsr_in);
  endfunction

  function automatic logic [7:0] descramble(
      input  logic [7:0]  din,
      input  logic        is_k,
      inout  logic [15:0] lfsr_v);
    logic [23:0] step;
    if (is_k && (din == rivet_pkg::RIVET_SYM_COM)) begin
      lfsr_v = 16'hFFFF;
      return din;
    end
    if (is_k && (din == rivet_pkg::RIVET_SYM_SKP))
      return din;
    step   = lfsr_step(lfsr_v);
    lfsr_v = step[23:8];
    if (!is_k)
      return din ^ step[7:0];
    return din;
  endfunction

  function void publish_wire6(logic [47:0] wire6);
    rivet_dllp_item item;
    rivet_pkg::rivet_dllp_fc_kind_e kind;
    logic [2:0]  vc;
    logic [7:0]  hdr;
    logic [11:0] data;
    bit          crc_ok;
    logic [7:0]  t;

    item = rivet_dllp_item::type_id::create("dllp_tx");
    item.from_dut = 1'b1;
    t = wire6[7:0];
    item.type_byte = t;
    void'(rivet_dllp_util::decode_fc(wire6, kind, vc, hdr, data, crc_ok));
    item.crc_ok = crc_ok;

    if (t == rivet_pkg::RIVET_DLLP_TYPE_ACK) begin
      item.is_ack  = 1'b1;
      item.ack_seq = {wire6[19:16], wire6[31:24]};
    end else if (t == rivet_pkg::RIVET_DLLP_TYPE_NAK) begin
      item.is_nak  = 1'b1;
      item.ack_seq = {wire6[19:16], wire6[31:24]};
    end else begin
      item.is_fc   = 1'b1;
      item.fc_kind = kind;
      item.vc      = vc;
      item.hdr_fc  = hdr;
      item.data_fc = data;
    end
    ap.write(item);
  endfunction

  function void push_sym(logic [7:0] sym, bit is_k);
    logic [47:0] wire6;
    if (!collecting) begin
      if (is_k && (sym == rivet_pkg::RIVET_SYM_SDP)) begin
        collecting   = 1'b1;
        collect_need = 6;
        byte_q.delete();
      end
      return;
    end

    if (collect_need > 0) begin
      if (is_k) begin
        // Unexpected K mid-payload — abort.
        collecting = 1'b0;
        byte_q.delete();
        return;
      end
      byte_q.push_back(sym);
      collect_need--;
      return;
    end

    // Expect END
    if (is_k && (sym == rivet_pkg::RIVET_SYM_END) && (byte_q.size() == 6)) begin
      wire6 = {byte_q[5], byte_q[4], byte_q[3], byte_q[2], byte_q[1], byte_q[0]};
      publish_wire6(wire6);
    end
    collecting = 1'b0;
    byte_q.delete();
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned l, s;
    logic [7:0]  raw, plain;
    bit          is_k;
    logic [15:0] lf;

    if (!enable) return;
    lfsr = new[lanes];
    for (l = 0; l < lanes; l++) lfsr[l] = 16'hFFFF;
    collecting = 1'b0;
    wait (vif.preset_n === 1'b1);

    forever begin
      @(posedge vif.pclk);
      if (vif.txelecidle != '0) begin
        for (l = 0; l < lanes; l++) lfsr[l] = 16'hFFFF;
        collecting = 1'b0;
        byte_q.delete();
        continue;
      end
      // Stripe order matches MAC: symbol-time s, then lanes 0..N-1.
      for (s = 0; s < 2; s++) begin
        for (l = 0; l < lanes; l++) begin
          raw  = vif.txdata[16*l + 8*s +: 8];
          is_k = vif.txdatak[2*l + s];
          lf   = lfsr[l];
          plain = descramble(raw, is_k, lf);
          lfsr[l] = lf;
          push_sym(plain, is_k);
        end
      end
    end
  endtask
endclass : rivet_pipe_dllp_monitor
