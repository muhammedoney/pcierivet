// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack a PG213-style 256-bit AXI-ST Requester Request into 32-byte DLL
// beats. The descriptor stays in tdata[127:0]. Bytes 16..31 of that beat
// are payload when tkeep says so. A 64-byte residue lets the last beat of
// one TLP move to the DLL on the cycle it is accepted, and the next
// descriptor can be accepted on that same handoff.
//
// tuser[RIVET_RQ_TUSER_NEXT_SOP] with tlast means this beat ends the open
// TLP at byte 16 and bytes 16..31 are the next descriptor.

module rivet_tl_rq_g4 #(
  parameter int unsigned MODE = 0
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic         bus_master_en_i,
  input  logic [7:0]   primary_bus_i = 8'h00,

  input  logic [255:0] s_axis_rq_tdata,
  input  logic [7:0]   s_axis_rq_tkeep,
  input  logic         s_axis_rq_tlast,
  input  logic         s_axis_rq_tvalid,
  output logic         s_axis_rq_tready,
  input  logic [84:0]  s_axis_rq_tuser,

  output logic [255:0] tx_tdata_o,
  output logic [31:0]  tx_tkeep_o,
  output logic         tx_tlast_o,
  output logic         tx_tvalid_o,
  input  logic         tx_tready_i,

  output logic         tx_accept_o,
  output logic [7:0]   tx_hdr0_o,
  output logic [9:0]   tx_len_dw_o,

  output logic [5:0]   rq_seq_num_o,
  output logic         rq_seq_num_vld_o,
  output logic [9:0]   rq_tag_o,
  output logic         rq_tag_vld_o,
  output logic [3:0]   rq_tag_av_o,
  input  logic         tag_free_i
);

  import rivet_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_PAY  = 2'd1,
    ST_TAIL = 2'd2
  } st_e;

  st_e          st_q;
  logic [255:0] tx_d_q;
  logic [31:0]  tx_k_q;
  logic         tx_l_q, tx_v_q;
  logic         is_wr_q;
  logic [9:0]   len_q;
  logic [7:0]   tag_q, hdr0_q;
  logic [5:0]   seq_q;
  logic [3:0]   tag_av_q;
  logic [511:0] res_q;
  logic [6:0]   res_n_q;
  logic         pkt_q;
  logic         res_last_q;
  // Header of the TLP whose tlast is in tx_*. Updated with that beat, so a
  // descriptor accepted on the same cycle cannot overwrite the credit sample.
  logic [7:0]   acc_hdr_q;
  logic         acc_wr_q;
  logic [9:0]   acc_len_q;
  logic [7:0]   acc_tag_q;

  logic         slot_free;
  logic         accept;
  logic         split_beat;

  assign tx_tvalid_o      = tx_v_q;
  assign tx_tdata_o       = tx_d_q;
  assign tx_tkeep_o       = tx_k_q;
  assign tx_tlast_o       = tx_l_q;
  assign tx_accept_o      = tx_v_q && tx_tready_i && tx_l_q;
  assign tx_hdr0_o        = acc_hdr_q;
  assign tx_len_dw_o      = acc_wr_q ? acc_len_q : 10'd0;
  assign rq_seq_num_o     = seq_q;
  assign rq_seq_num_vld_o = tx_accept_o;
  assign rq_tag_o         = {2'b00, acc_tag_q};
  assign rq_tag_vld_o     = tx_accept_o && !acc_wr_q;
  assign rq_tag_av_o      = tag_av_q;

  assign slot_free = !tx_v_q || tx_tready_i;
  // A split beat ends the open TLP at byte 16. That tail has to leave in
  // this cycle, before the next descriptor joins the residue.
  assign split_beat = s_axis_rq_tvalid && s_axis_rq_tlast &&
                      s_axis_rq_tuser[RIVET_RQ_TUSER_NEXT_SOP];
  // PAY can take another 32 bytes after one drain. TAIL can take the next
  // descriptor only when the whole tail leaves in this cycle.
  assign s_axis_rq_tready = bus_master_en_i &&
                            ((st_q == ST_IDLE) ||
                             ((st_q == ST_PAY) && !split_beat &&
                              ((res_n_q <= 7'd32) || slot_free)) ||
                             ((st_q == ST_PAY) && split_beat && slot_free &&
                              (res_n_q <= 7'd16)) ||
                             ((st_q == ST_TAIL) && slot_free &&
                              (res_n_q <= 7'd32)));
  assign accept = s_axis_rq_tvalid && s_axis_rq_tready;

  function automatic logic [31:0] keep32(input logic [5:0] n);
    logic [31:0] k;
    k = '0;
    for (int unsigned i = 0; i < 32; i++)
      if (6'(i) < n)
        k[i] = 1'b1;
    return k;
  endfunction

  // Payload on a descriptor beat starts at byte 16 (dword 4).
  function automatic logic [5:0] hi_pay_bytes(input logic [7:0] k);
    logic [5:0] n;
    n = '0;
    for (int unsigned i = 4; i < 8; i++)
      if (k[i])
        n = n + 6'd4;
    return n;
  endfunction

  // AXI-ST tkeep is one bit per dword.
  function automatic logic [5:0] keep_nbytes8(input logic [7:0] k);
    logic [5:0] n;
    n = '0;
    for (int unsigned i = 0; i < 8; i++)
      if (k[i])
        n = n + 6'd4;
    return n;
  endfunction

  function automatic logic is_cfg_req(input logic [3:0] req);
    return (req == RIVET_RQ_REQ_CFGRD0) || (req == RIVET_RQ_REQ_CFGRD1) ||
           (req == RIVET_RQ_REQ_CFGWR0) || (req == RIVET_RQ_REQ_CFGWR1);
  endfunction

  function automatic logic [7:0] cfg_fmt(input logic [3:0] req);
    unique case (req)
      RIVET_RQ_REQ_CFGRD0: return RIVET_TLP_B0_CFGRD0;
      RIVET_RQ_REQ_CFGRD1: return RIVET_TLP_B0_CFGRD1;
      RIVET_RQ_REQ_CFGWR0: return RIVET_TLP_B0_CFGWR0;
      default:             return RIVET_TLP_B0_CFGWR1;
    endcase
  endfunction

  function automatic logic [127:0] build_cfg_hdr(
      input logic [7:0]  b0,
      input logic [7:0]  tag,
      input logic [3:0]  fbe,
      input logic [15:0] completer,
      input logic [31:0] addr,
      input logic [7:0]  bus);
    logic [127:0] h;
    h          = '0;
    h[7:0]     = b0;
    h[31:24]   = 8'h01;
    h[47:40]   = bus;
    h[55:48]   = tag;
    h[59:56]   = fbe;
    h[71:64]   = completer[15:8];
    h[79:72]   = completer[7:0];
    h[87:80]   = {4'h0, addr[11:8]};
    h[95:88]   = {addr[7:2], 2'b00};
    return h;
  endfunction

  function automatic logic [127:0] build_hdr(
      input logic [7:0]  b0,
      input logic [9:0]  len,
      input logic [7:0]  tag,
      input logic [3:0]  fbe,
      input logic [3:0]  lbe,
      input logic [31:0] addr,
      input logic [31:0] addr_hi,
      input logic        is64);
    logic [127:0] h;
    h          = '0;
    h[7:0]     = b0;
    h[23:16]   = {6'h0, len[9:8]};
    h[31:24]   = len[7:0];
    h[39:32]   = 8'h00;
    h[47:40]   = 8'h01;
    h[55:48]   = tag;
    h[59:56]   = fbe;
    h[63:60]   = lbe;
    if (is64) begin
      h[71:64]   = addr_hi[31:24];
      h[79:72]   = addr_hi[23:16];
      h[87:80]   = addr_hi[15:8];
      h[95:88]   = addr_hi[7:0];
      h[103:96]  = addr[31:24];
      h[111:104] = addr[23:16];
      h[119:112] = addr[15:8];
      h[127:120] = addr[7:0];
    end else begin
      h[71:64] = addr[31:24];
      h[79:72] = addr[23:16];
      h[87:80] = addr[15:8];
      h[95:88] = addr[7:0];
    end
    return h;
  endfunction

  task automatic push_bytes(
      inout logic [511:0] res,
      inout logic [6:0]   rn,
      input logic [255:0] data,
      input logic [5:0]   off,
      input logic [5:0]   nb
  );
    // Destination-byte-first select keeps each output byte independent
    // instead of building a 32-deep sequential write mux cascade.
    logic [7:0] sb [32];
    logic [7:0] db [64];
    for (int unsigned i = 0; i < 32; i++)
      sb[5'(i)] = data[8*5'(i) +: 8];
    for (int unsigned k = 0; k < 64; k++) begin
      automatic logic [6:0] diff;
      automatic logic [4:0] si;
      db[6'(k)] = res[8*6'(k) +: 8];
      diff      = 7'(k) - rn;
      if ((7'(k) >= rn) && (diff < {1'b0, nb})) begin
        si        = off[4:0] + diff[4:0];
        db[6'(k)] = sb[si];
      end
    end
    for (int unsigned k = 0; k < 64; k++)
      res[8*6'(k) +: 8] = db[6'(k)];
    rn = rn + 7'(nb);
  endtask

  // Peel 32 bytes into the DLL beat. A short finished packet peels whatever
  // is left and marks tlast. Returns 1 when the output slot was used.
  task automatic peel(
      inout logic [511:0] res,
      inout logic [6:0]   rn,
      inout logic         rlast,
      inout logic         pkt,
      input logic         want_short,
      output logic        did,
      output logic [255:0] ed,
      output logic [31:0]  ek,
      output logic         el
  );
    did = 1'b0;
    ed  = '0;
    ek  = '0;
    el  = 1'b0;
    if ((rn >= 7'd32) && !want_short) begin
      did   = 1'b1;
      ed    = res[255:0];
      ek    = 32'hFFFF_FFFF;
      el    = rlast && (rn == 7'd32);
      res   = res >> 256;
      rn    = rn - 7'd32;
      if (el) begin
        rlast = 1'b0;
        pkt   = 1'b0;
      end
    end else if (want_short && rlast && (rn != 7'd0) && (rn <= 7'd32)) begin
      did   = 1'b1;
      ed    = res[255:0];
      ek    = keep32(rn[5:0]);
      el    = 1'b1;
      res   = '0;
      rn    = '0;
      rlast = 1'b0;
      pkt   = 1'b0;
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q       <= ST_IDLE;
      tx_d_q     <= '0;
      tx_k_q     <= '0;
      tx_l_q     <= 1'b0;
      tx_v_q     <= 1'b0;
      is_wr_q    <= 1'b0;
      len_q      <= '0;
      tag_q      <= '0;
      hdr0_q     <= '0;
      seq_q      <= '0;
      tag_av_q   <= 4'd8;
      res_q      <= '0;
      res_n_q    <= '0;
      pkt_q      <= 1'b0;
      res_last_q <= 1'b0;
      acc_hdr_q  <= '0;
      acc_wr_q   <= 1'b0;
      acc_len_q  <= '0;
      acc_tag_q  <= '0;
    end else begin
      logic [511:0] res;
      logic [6:0]   rn;
      logic         rlast;
      logic         pkt;
      logic         emitted;
      logic [255:0] ed;
      logic [31:0]  ek;
      logic         el;
      logic [7:0]   hdr_hold, tag_hold, cap_hdr, cap_tag;
      logic         wr_hold, cap_wr, do_cap;
      logic [9:0]   len_hold, cap_len;
      res      = res_q;
      rn       = res_n_q;
      rlast    = res_last_q;
      pkt      = pkt_q;
      emitted  = 1'b0;
      ed       = '0;
      ek       = '0;
      el       = 1'b0;
      hdr_hold = hdr0_q;
      wr_hold  = is_wr_q;
      len_hold = len_q;
      tag_hold = tag_q;
      cap_hdr  = '0;
      cap_wr   = 1'b0;
      cap_len  = '0;
      cap_tag  = '0;
      do_cap   = 1'b0;

      if (tx_accept_o) begin
        seq_q <= seq_q + 6'd1;
        if (!acc_wr_q && (tag_av_q != 4'd0))
          tag_av_q <= tag_av_q - 4'd1;
      end else if (tag_free_i && (tag_av_q < 4'd8)) begin
        tag_av_q <= tag_av_q + 4'd1;
      end

      // Drain a full beat before accepting more, so the residue stays <= 64.
      if (slot_free && (rn >= 7'd32))
        peel(res, rn, rlast, pkt, 1'b0, emitted, ed, ek, el);
      else if (slot_free && rlast && !accept && (rn != 7'd0))
        peel(res, rn, rlast, pkt, 1'b1, emitted, ed, ek, el);

      if (accept && rlast && slot_free && !emitted && (rn != 7'd0))
        peel(res, rn, rlast, pkt, 1'b1, emitted, ed, ek, el);

      // Snapshot before a new descriptor can replace the holds.
      if (emitted && el) begin
        cap_hdr = hdr_hold;
        cap_wr  = wr_hold;
        cap_len = len_hold;
        cap_tag = tag_hold;
        do_cap  = 1'b1;
      end

      if (accept && !rlast) begin
        if (pkt && split_beat) begin
          logic [63:0]  b0, b1;
          logic [31:0]  addr, addr_hi;
          logic [9:0]   len;
          logic [7:0]   tag;
          logic [3:0]   req, fbe, lbe;
          logic         is64, is_wr;
          logic [7:0]   b0t;
          logic [127:0] hdr;
          logic [5:0]   hlen;
          // Bytes 0..15 finish the open TLP. Peel that tail before the
          // descriptor in bytes 16..31 becomes the next packet.
          push_bytes(res, rn, s_axis_rq_tdata, 6'd0, 6'd16);
          rlast = 1'b1;
          if (slot_free && !emitted && (rn >= 7'd32))
            peel(res, rn, rlast, pkt, 1'b0, emitted, ed, ek, el);
          if (slot_free && !emitted && rlast && (rn != 7'd0))
            peel(res, rn, rlast, pkt, 1'b1, emitted, ed, ek, el);
          if (emitted && el && !do_cap) begin
            cap_hdr = hdr_hold;
            cap_wr  = wr_hold;
            cap_len = len_hold;
            cap_tag = tag_hold;
            do_cap  = 1'b1;
          end
          b0      = s_axis_rq_tdata[191:128];
          b1      = s_axis_rq_tdata[255:192];
          addr    = {b0[31:2], 2'b00};
          addr_hi = b0[63:32];
          len     = b1[9:0];
          req     = b1[14:11];
          tag     = b1[39:32];
          fbe     = s_axis_rq_tuser[3:0];
          lbe     = s_axis_rq_tuser[7:4];
          is64    = (addr_hi != 32'h0);
          if ((MODE == RIVET_MODE_RC) && is_cfg_req(req)) begin
            is_wr = (req == RIVET_RQ_REQ_CFGWR0) || (req == RIVET_RQ_REQ_CFGWR1);
            b0t   = cfg_fmt(req);
            hdr   = build_cfg_hdr(b0t, tag, fbe, b1[55:40], addr, primary_bus_i);
            hlen  = 6'd12;
          end else begin
            is_wr = (req == RIVET_CQ_REQ_MEMWR);
            b0t   = is_wr ? (is64 ? RIVET_TLP_B0_MEMWR64 : RIVET_TLP_B0_MEMWR32)
                          : (is64 ? RIVET_TLP_B0_MEMRD64 : RIVET_TLP_B0_MEMRD32);
            hdr   = build_hdr(b0t, len, tag, fbe, lbe, addr, addr_hi, is64);
            hlen  = is64 ? 6'd16 : 6'd12;
          end
          hdr_hold = b0t;
          wr_hold  = is_wr;
          len_hold = len;
          tag_hold = tag;
          is_wr_q <= is_wr;
          len_q   <= len;
          tag_q   <= tag;
          hdr0_q  <= b0t;
          push_bytes(res, rn, {128'h0, hdr}, 6'd0, hlen);
          pkt   = 1'b1;
          rlast = 1'b0;
        end else if (!pkt) begin
          logic [63:0]  b0, b1;
          logic [31:0]  addr, addr_hi;
          logic [9:0]   len;
          logic [7:0]   tag;
          logic [3:0]   req, fbe, lbe;
          logic         is64, is_wr;
          logic [7:0]   b0t;
          logic [127:0] hdr;
          logic [5:0]   hlen, pay_n;
          b0      = s_axis_rq_tdata[63:0];
          b1      = s_axis_rq_tdata[127:64];
          addr    = {b0[31:2], 2'b00};
          addr_hi = b0[63:32];
          len     = b1[9:0];
          req     = b1[14:11];
          tag     = b1[39:32];
          fbe     = s_axis_rq_tuser[3:0];
          lbe     = s_axis_rq_tuser[7:4];
          is64    = (addr_hi != 32'h0);
          if ((MODE == RIVET_MODE_RC) && is_cfg_req(req)) begin
            is_wr = (req == RIVET_RQ_REQ_CFGWR0) || (req == RIVET_RQ_REQ_CFGWR1);
            b0t   = cfg_fmt(req);
            hdr   = build_cfg_hdr(b0t, tag, fbe, b1[55:40], addr, primary_bus_i);
            hlen  = 6'd12;
          end else begin
            is_wr = (req == RIVET_CQ_REQ_MEMWR);
            b0t   = is_wr ? (is64 ? RIVET_TLP_B0_MEMWR64 : RIVET_TLP_B0_MEMWR32)
                          : (is64 ? RIVET_TLP_B0_MEMRD64 : RIVET_TLP_B0_MEMRD32);
            hdr   = build_hdr(b0t, len, tag, fbe, lbe, addr, addr_hi, is64);
            hlen  = is64 ? 6'd16 : 6'd12;
          end
          pay_n   = hi_pay_bytes(s_axis_rq_tkeep);
          hdr_hold = b0t;
          wr_hold  = is_wr;
          len_hold = len;
          tag_hold = tag;
          is_wr_q <= is_wr;
          len_q   <= len;
          tag_q   <= tag;
          hdr0_q  <= b0t;
          push_bytes(res, rn, {128'h0, hdr}, 6'd0, hlen);
          if (is_wr && (pay_n != 6'd0))
            push_bytes(res, rn, s_axis_rq_tdata, 6'd16, pay_n);
          pkt = 1'b1;
          if (!is_wr || s_axis_rq_tlast)
            rlast = 1'b1;
        end else begin
          push_bytes(res, rn, s_axis_rq_tdata, 6'd0, keep_nbytes8(s_axis_rq_tkeep));
          if (s_axis_rq_tlast)
            rlast = 1'b1;
        end
        if (slot_free && !emitted && (rn >= 7'd32))
          peel(res, rn, rlast, pkt, 1'b0, emitted, ed, ek, el);
        if (slot_free && !emitted && rlast && (rn != 7'd0))
          peel(res, rn, rlast, pkt, 1'b1, emitted, ed, ek, el);
        if (emitted && el && !do_cap) begin
          cap_hdr = hdr_hold;
          cap_wr  = wr_hold;
          cap_len = len_hold;
          cap_tag = tag_hold;
          do_cap  = 1'b1;
        end
      end

      if (do_cap) begin
        acc_hdr_q <= cap_hdr;
        acc_wr_q  <= cap_wr;
        acc_len_q <= cap_len;
        acc_tag_q <= cap_tag;
      end

      if (emitted) begin
        tx_d_q <= ed;
        tx_k_q <= ek;
        tx_l_q <= el;
        tx_v_q <= 1'b1;
      end else if (tx_v_q && tx_tready_i) begin
        tx_v_q <= 1'b0;
      end

      res_q      <= res;
      res_n_q    <= rn;
      res_last_q <= rlast;
      pkt_q      <= pkt;
      if (!pkt)
        st_q <= ST_IDLE;
      else if (rlast)
        st_q <= ST_TAIL;
      else
        st_q <= ST_PAY;
    end
  end

endmodule : rivet_tl_rq_g4
