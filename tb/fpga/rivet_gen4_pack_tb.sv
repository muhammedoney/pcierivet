// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Gen4 256-bit DLL (tl_pack + tlp_tx16 + tlp_rx16) and TL (rq_g4 + rc_g4)
// byte-packing regression test.

`timescale 1ns/1ps

module rivet_gen4_pack_tb;
  import rivet_pkg::*;

  logic clk, rst_n;
  initial clk = 1'b0;
  always #2 clk = ~clk;

  // --- Dual 256-bit Gen4 DLL loopback ---
  rivet_mac_dll_sb_t      mac_a, mac_b;
  rivet_tl_dll_fc_sb_t    tl_a, tl_b;
  rivet_dll_tl_fc_sb_t    dll_tl_a, dll_tl_b;
  rivet_dll_mac_sb_t      dll_mac_a, dll_mac_b;
  rivet_dll_mac_tx_beat_t tx_a, tx_b;
  logic                   txv_a, txv_b, txr_a, txr_b;
  rivet_dll_mac_rx_beat_t rx_a, rx_b;
  logic                   rxv_a, rxv_b, rxr_a, rxr_b;

  always_comb begin
    rx_b = '{data: tx_a.data, keep: tx_a.keep, sop: tx_a.sop, eop: tx_a.eop,
             err: 1'b0, pkt_type: tx_a.pkt_type};
    rxv_b = txv_a; txr_a = rxr_b;
    rx_a = '{data: tx_b.data, keep: tx_b.keep, sop: tx_b.sop, eop: tx_b.eop,
             err: 1'b0, pkt_type: tx_b.pkt_type};
    rxv_a = txv_b; txr_b = rxr_a;
  end

  logic [255:0] txd, rxd;
  logic [31:0]  txk, rxk;
  logic         txl, txv, txr, rxl, rxv, rxr;
  logic [11:0]  rxseq;
  logic         unused_r;

  rivet_tl_fc_stub #(.PH_CRED(8'h20), .NPH_CRED(8'h10)) u_tl_a (
    .clk_i(clk), .rst_ni(rst_n),
    .free_ph_i(1'b0), .free_pd_i(1'b0), .free_nph_i(1'b0), .free_npd_i(1'b0),
    .free_cplh_i(1'b0), .free_cpld_i(1'b0),
    .free_ph_amt_i(8'd0), .free_pd_amt_i(12'd0), .free_nph_amt_i(8'd0),
    .free_npd_amt_i(12'd0), .free_cplh_amt_i(8'd0), .free_cpld_amt_i(12'd0),
    .consume_ph_i(1'b0), .consume_pd_i(1'b0), .consume_nph_i(1'b0),
    .consume_npd_i(1'b0), .consume_cplh_i(1'b0), .consume_cpld_i(1'b0),
    .consume_ph_amt_i(8'd0), .consume_pd_amt_i(12'd0), .consume_nph_amt_i(8'd0),
    .consume_npd_amt_i(12'd0), .consume_cplh_amt_i(8'd0), .consume_cpld_amt_i(12'd0),
    .tl_to_dll_fc_o(tl_a), .dll_to_tl_fc_i(dll_tl_a)
  );
  rivet_tl_fc_stub #(.PH_CRED(8'h20), .NPH_CRED(8'h10)) u_tl_b (
    .clk_i(clk), .rst_ni(rst_n),
    .free_ph_i(1'b0), .free_pd_i(1'b0), .free_nph_i(1'b0), .free_npd_i(1'b0),
    .free_cplh_i(1'b0), .free_cpld_i(1'b0),
    .free_ph_amt_i(8'd0), .free_pd_amt_i(12'd0), .free_nph_amt_i(8'd0),
    .free_npd_amt_i(12'd0), .free_cplh_amt_i(8'd0), .free_cpld_amt_i(12'd0),
    .consume_ph_i(1'b0), .consume_pd_i(1'b0), .consume_nph_i(1'b0),
    .consume_npd_i(1'b0), .consume_cplh_i(1'b0), .consume_cpld_i(1'b0),
    .consume_ph_amt_i(8'd0), .consume_pd_amt_i(12'd0), .consume_nph_amt_i(8'd0),
    .consume_npd_amt_i(12'd0), .consume_cplh_amt_i(8'd0), .consume_cpld_amt_i(12'd0),
    .tl_to_dll_fc_o(tl_b), .dll_to_tl_fc_i(dll_tl_b)
  );

  rivet_dll #(
    .LANES(4), .PIPE_DATA_WIDTH(64),
    .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000),
    .REPLAY_TLP_SLOTS(8), .REPLAY_SLOT_BYTES(256),
    .RX_SLOT_BYTES(256),
    .TL_DATA_W(256), .TX_DATA_W(256)
  ) u_a (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_a), .dll_tx_valid_o(txv_a), .dll_tx_ready_i(txr_a),
    .dll_rx_beat_i(rx_a), .dll_rx_valid_i(rxv_a), .dll_rx_ready_o(rxr_a),
    .mac_to_dll_sb_i(mac_a), .dll_to_mac_sb_o(dll_mac_a),
    .tl_to_dll_fc_i(tl_a), .dll_to_tl_fc_o(dll_tl_a),
    .tl_tx_tdata_i(txd), .tl_tx_tkeep_i(txk), .tl_tx_tlast_i(txl),
    .tl_tx_tvalid_i(txv), .tl_tx_tready_o(txr),
    .tl_rx_tdata_o(), .tl_rx_tkeep_o(), .tl_rx_tlast_o(),
    .tl_rx_tvalid_o(), .tl_rx_tready_i(1'b1), .tl_rx_seq_o(),
    .tl_rx_abort_o()
  );

  rivet_dll #(
    .LANES(4), .PIPE_DATA_WIDTH(64),
    .INITFC_GAP_CYC(2), .UPDATEFC_GAP_CYC(10000),
    .REPLAY_TLP_SLOTS(8), .REPLAY_SLOT_BYTES(256),
    .RX_SLOT_BYTES(256),
    .TL_DATA_W(256), .TX_DATA_W(256)
  ) u_b (
    .pclk_i(clk), .rst_ni(rst_n),
    .dll_tx_beat_o(tx_b), .dll_tx_valid_o(txv_b), .dll_tx_ready_i(txr_b),
    .dll_rx_beat_i(rx_b), .dll_rx_valid_i(rxv_b), .dll_rx_ready_o(rxr_b),
    .mac_to_dll_sb_i(mac_b), .dll_to_mac_sb_o(dll_mac_b),
    .tl_to_dll_fc_i(tl_b), .dll_to_tl_fc_o(dll_tl_b),
    .tl_tx_tdata_i(256'd0), .tl_tx_tkeep_i(32'd0), .tl_tx_tlast_i(1'b0),
    .tl_tx_tvalid_i(1'b0), .tl_tx_tready_o(unused_r),
    .tl_rx_tdata_o(rxd), .tl_rx_tkeep_o(rxk), .tl_rx_tlast_o(rxl),
    .tl_rx_tvalid_o(rxv), .tl_rx_tready_i(rxr), .tl_rx_seq_o(rxseq),
    .tl_rx_abort_o()
  );

  // --- RQ G4 and RC G4 ---
  logic [255:0] rq_d, rq_tx_d;
  logic [7:0]   rq_k;
  logic [31:0]  rq_tx_k;
  logic         rq_l, rq_v, rq_r, rq_tx_l, rq_tx_v;
  logic [84:0]  rq_u;

  rivet_tl_rq_g4 u_rq (
    .clk_i(clk), .rst_ni(rst_n), .bus_master_en_i(1'b1),
    .s_axis_rq_tdata(rq_d), .s_axis_rq_tkeep(rq_k),
    .s_axis_rq_tlast(rq_l), .s_axis_rq_tvalid(rq_v),
    .s_axis_rq_tready(rq_r), .s_axis_rq_tuser(rq_u),
    .tx_tdata_o(rq_tx_d), .tx_tkeep_o(rq_tx_k),
    .tx_tlast_o(rq_tx_l), .tx_tvalid_o(rq_tx_v), .tx_tready_i(1'b1),
    .tx_accept_o(), .tx_hdr0_o(), .tx_len_dw_o(),
    .rq_seq_num_o(), .rq_seq_num_vld_o(),
    .rq_tag_o(), .rq_tag_vld_o(), .rq_tag_av_o(), .tag_free_i(1'b0)
  );

  logic [255:0] rc_rx_d, rc_d;
  logic [31:0]  rc_rx_k;
  logic [7:0]   rc_k;
  logic         rc_rx_l, rc_rx_v, rc_rx_r, rc_l, rc_v;
  logic [74:0]  rc_u;

  rivet_tl_rc_g4 u_rc (
    .clk_i(clk), .rst_ni(rst_n),
    .rx_tdata_i(rc_rx_d), .rx_tkeep_i(rc_rx_k), .rx_tlast_i(rc_rx_l),
    .rx_tvalid_i(rc_rx_v), .rx_abort_i(1'b0), .rx_tready_o(rc_rx_r),
    .m_axis_rc_tdata(rc_d), .m_axis_rc_tkeep(rc_k),
    .m_axis_rc_tlast(rc_l), .m_axis_rc_tvalid(rc_v),
    .m_axis_rc_tready(1'b1), .m_axis_rc_tuser(rc_u),
    .rx_accept_o(), .rx_hdr0_o(), .rx_len_dw_o(), .tag_free_o()
  );

  function automatic logic [31:0] mk_keep(input int unsigned n);
    logic [31:0] k;
    k = '0;
    for (int unsigned i = 0; i < 32; i++)
      if (i < n) k[i] = 1'b1;
    return k;
  endfunction

  // Collect DLL RX beats concurrently so streaming playback is never missed
  logic [7:0]  dll_got [0:255];
  int unsigned dll_gn;
  logic        dll_done;
  logic        dll_clr;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dll_gn   <= 0;
      dll_done <= 1'b0;
    end else if (dll_clr) begin
      dll_gn   <= 0;
      dll_done <= 1'b0;
    end else if (rxv && rxr) begin
      int unsigned idx;
      idx = dll_gn;
      for (int unsigned i = 0; i < 32; i++) begin
        if (rxk[i]) begin
          dll_got[idx] <= rxd[8*i +: 8];
          idx++;
        end
      end
      dll_gn <= idx;
      if (rxl) dll_done <= 1'b1;
    end
  end

  task automatic send_check_dll(input int unsigned len, input logic [7:0] seed);
    logic [7:0] exp_b [0:127];
    int unsigned off, guard;
    for (int unsigned i = 0; i < len; i++)
      exp_b[i] = seed + 8'(i);
    // TLP header byte 0 = 0x40 (MemWr32) so FC/credit checks stay sane
    exp_b[0] = 8'h40;
    exp_b[1] = 8'h00;
    exp_b[2] = 8'h00;
    exp_b[3] = 8'((len - 12) / 4);

    @(negedge clk);
    dll_clr = 1'b1;
    @(posedge clk);
    @(negedge clk);
    dll_clr = 1'b0;

    off = 0;
    while (off < len) begin
      int unsigned nb;
      nb = ((len - off) >= 32) ? 32 : (len - off);
      @(negedge clk);
      txd = '0;
      for (int unsigned i = 0; i < nb; i++)
        txd[8*i +: 8] = exp_b[off + i];
      txk = mk_keep(nb);
      txl = ((off + nb) >= len);
      txv = 1'b1;
      @(posedge clk);
      while (!txr) @(posedge clk);
      off += nb;
    end
    @(negedge clk);
    txv = 1'b0;
    txl = 1'b0;

    guard = 0;
    while (!dll_done && guard < 400) begin
      @(posedge clk);
      guard++;
    end
    if (!dll_done || dll_gn != len) begin
      $display("FAIL DLL len=%0d done=%0b got=%0d", len, dll_done, dll_gn);
      $fatal(1);
    end
    for (int unsigned i = 0; i < len; i++) begin
      if (dll_got[i] !== exp_b[i]) begin
        $display("FAIL DLL len=%0d byte %0d exp=0x%02x got=0x%02x",
                 len, i, exp_b[i], dll_got[i]);
        $fatal(1);
      end
    end
  endtask

  // Collect RQ outputs asynchronously
  logic [7:0] rq_got [0:127];
  int unsigned rq_gn;
  logic        rq_done;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rq_gn   <= 0;
      rq_done <= 1'b0;
    end else if (rq_tx_v) begin
      int unsigned idx;
      idx = rq_gn;
      for (int unsigned i = 0; i < 32; i++) begin
        if (rq_tx_k[i]) begin
          rq_got[idx] <= rq_tx_d[8*i +: 8];
          idx++;
        end
      end
      rq_gn <= idx;
      if (rq_tx_l) rq_done <= 1'b1;
    end
  end

  // Collect RC payload outputs
  logic [7:0] rc_pay [0:127];
  int unsigned rc_pn;
  int unsigned rc_beats;
  logic        rc_done;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rc_pn    <= 0;
      rc_beats <= 0;
      rc_done  <= 1'b0;
    end else if (rc_v) begin
      if (rc_beats >= 2) begin
        int unsigned idx;
        idx = rc_pn;
        for (int unsigned d = 0; d < 8; d++) begin
          if (rc_k[d]) begin
            for (int unsigned b = 0; b < 4; b++) begin
              rc_pay[idx] <= rc_d[32*d + 8*b +: 8];
              idx++;
            end
          end
        end
        rc_pn <= idx;
      end
      rc_beats <= rc_beats + 1;
      if (rc_l) rc_done <= 1'b1;
    end
  end

  initial begin
    static int unsigned lens [7] = '{12, 16, 20, 32, 44, 68, 100};
    rst_n = 1'b0;
    dll_clr = 1'b0;
    mac_a = '0; mac_b = '0;
    txd = '0; txk = '0; txl = 1'b0; txv = 1'b0; rxr = 1'b1;
    rq_d = '0; rq_k = '0; rq_l = 1'b0; rq_v = 1'b0; rq_u = '0;
    rc_rx_d = '0; rc_rx_k = '0; rc_rx_l = 1'b0; rc_rx_v = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    mac_a.accept_dll_tlp = 1'b1; mac_a.link_up = 1'b1;
    mac_b.accept_dll_tlp = 1'b1; mac_b.link_up = 1'b1;
    wait (dll_tl_a.dl_up && dll_tl_b.dl_up);
    repeat (2) @(posedge clk);

    // 1. Test 256-bit DLL TX + RX across varied lengths
    for (int unsigned k = 0; k < 7; k++)
      send_check_dll(lens[k], 8'(8'h10 + k * 8'h21));
    $display("DLL 256-bit ok");

    // 2. Test RQ G4: 16 DW (64 B) MemWr32 -> 12 B hdr + 64 B pay = 76 B
    @(negedge clk);
    // Beat 0: 128b PG213 RQ descriptor + 16 B payload (0xA0..0xAF)
    rq_d = '0;
    rq_d[63:2]    = 62'h0000_0000_1234_5678 >> 2;
    rq_d[74:64]   = 11'd16; // 16 DW
    rq_d[78:75]   = 4'b0001; // MemWr
    rq_u          = '0;
    rq_u[3:0]     = 4'hF;
    rq_u[7:4]     = 4'hF;
    for (int unsigned i = 0; i < 16; i++)
      rq_d[128 + 8*i +: 8] = 8'(8'hA0 + i);
    rq_k = 8'hFF; rq_l = 1'b0; rq_v = 1'b1;
    @(posedge clk); while (!rq_r) @(posedge clk);
    // Beat 1: 32 B payload (0xB0..0xCF)
    @(negedge clk);
    for (int unsigned i = 0; i < 32; i++)
      rq_d[8*i +: 8] = 8'(8'hB0 + i);
    rq_k = 8'hFF; rq_l = 1'b0;
    @(posedge clk); while (!rq_r) @(posedge clk);
    // Beat 2: 16 B payload (0xD0..0xDF)
    @(negedge clk);
    rq_d = '0;
    for (int unsigned i = 0; i < 16; i++)
      rq_d[8*i +: 8] = 8'(8'hD0 + i);
    rq_k = 8'h0F; rq_l = 1'b1;
    @(posedge clk); while (!rq_r) @(posedge clk);
    @(negedge clk);
    rq_v = 1'b0; rq_l = 1'b0;

    repeat (20) @(posedge clk);
    if (!rq_done || rq_gn != 76) begin
      $display("FAIL RQ done=%0b gn=%0d (exp 76)", rq_done, rq_gn);
      $fatal(1);
    end
    for (int unsigned i = 0; i < 16; i++)
      if (rq_got[12 + i] !== 8'(8'hA0 + i)) $fatal(1, "FAIL RQ A[%0d]", i);
    for (int unsigned i = 0; i < 32; i++)
      if (rq_got[28 + i] !== 8'(8'hB0 + i)) $fatal(1, "FAIL RQ B[%0d]", i);
    for (int unsigned i = 0; i < 16; i++)
      if (rq_got[60 + i] !== 8'(8'hD0 + i)) $fatal(1, "FAIL RQ D[%0d]", i);
    $display("RQ G4 ok");

    // 3. Test RC G4: 16 DW (64 B) CplD = 12 B hdr + 64 B pay = 76 B
    @(negedge clk);
    rc_rx_d = '0;
    rc_rx_d[7:0]   = 8'h4A; // CplD
    rc_rx_d[25:24] = 2'b00;
    rc_rx_d[31:24] = 8'd16; // len = 16 DW (wire byte 3)
    for (int unsigned i = 0; i < 20; i++)
      rc_rx_d[96 + 8*i +: 8] = 8'(8'h30 + i);
    rc_rx_k = 32'hFFFF_FFFF; rc_rx_l = 1'b0; rc_rx_v = 1'b1;
    @(posedge clk); while (!rc_rx_r) @(posedge clk);
    @(negedge clk);
    for (int unsigned i = 0; i < 32; i++)
      rc_rx_d[8*i +: 8] = 8'(8'h30 + 20 + i);
    rc_rx_k = 32'hFFFF_FFFF; rc_rx_l = 1'b0;
    @(posedge clk); while (!rc_rx_r) @(posedge clk);
    @(negedge clk);
    rc_rx_d = '0;
    for (int unsigned i = 0; i < 12; i++)
      rc_rx_d[8*i +: 8] = 8'(8'h30 + 52 + i);
    rc_rx_k = mk_keep(12); rc_rx_l = 1'b1;
    @(posedge clk); while (!rc_rx_r) @(posedge clk);
    @(negedge clk);
    rc_rx_v = 1'b0; rc_rx_l = 1'b0;

    repeat (20) @(posedge clk);
    if (!rc_done || rc_pn != 64) begin
      $display("FAIL RC done=%0b pn=%0d (exp 64)", rc_done, rc_pn);
      $fatal(1);
    end
    for (int unsigned i = 0; i < 64; i++) begin
      if (rc_pay[i] !== 8'(8'h30 + i)) begin
        $display("FAIL RC byte %0d exp=0x%02x got=0x%02x", i, 8'(8'h30 + i), rc_pay[i]);
        $fatal(1);
      end
    end
    $display("PASS gen4 pack");
    $finish;
  end
endmodule
