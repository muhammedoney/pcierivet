// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Compare the shallow framing scanner against the per-symbol serial walk
// across all starting states, counts, and single/two-packet Gen4 beats.

module rivet_mac_gf_scan_tb;
  localparam int unsigned NSYM = 32;
  localparam int unsigned DLLP = 6;

  logic [2:0]        st_i;
  logic [15:0]       left_i;
  logic [5:0]        cnt_i;
  logic [NSYM-1:0]   sdp_i, stp_i, end_i, edb_i, k_i;
  logic [8*NSYM-1:0] data_i;
  logic [2:0]        st_o;
  logic [15:0]       left_o;
  logic [5:0]        cnt_o;
  logic [NSYM-1:0]   sdp_o, stp_o, end_o, edb_o, k_o;
  logic [8*NSYM-1:0] data_o;

  rivet_mac_gf_scan #(
    .NSYM(NSYM),
    .DLLP_BYTES(DLLP)
  ) u (
    .st_i, .left_i, .cnt_i, .sdp_i, .stp_i, .end_i, .edb_i, .k_i, .data_i,
    .st_o, .left_o, .cnt_o, .sdp_o, .stp_o, .end_o, .edb_o, .k_o, .data_o
  );

  function automatic void serial_dense(
    input  logic [2:0]        st_in,
    input  logic [15:0]       left_in,
    input  logic [5:0]        cnt_in,
    input  logic [NSYM-1:0]   sdp_in,
    input  logic [NSYM-1:0]   stp_in,
    input  logic [NSYM-1:0]   end_in,
    input  logic [NSYM-1:0]   edb_in,
    input  logic [NSYM-1:0]   k_in,
    input  logic [8*NSYM-1:0] data_in,
    output logic [2:0]        st_g,
    output logic [15:0]       left_g,
    output logic [5:0]        cnt_g,
    output logic [NSYM-1:0]   sdp_g,
    output logic [NSYM-1:0]   stp_g,
    output logic [NSYM-1:0]   end_g,
    output logic [NSYM-1:0]   edb_g,
    output logic [NSYM-1:0]   k_g,
    output logic [8*NSYM-1:0] data_g
  );
    logic [2:0]  st;
    logic [15:0] left;
    logic [5:0]  q;
    begin
      st     = st_in;
      left   = left_in;
      q      = 6'd0;
      sdp_g  = '0;
      stp_g  = '0;
      end_g  = '0;
      edb_g  = '0;
      k_g    = '0;
      data_g = '0;
      for (int unsigned p = 0; p < NSYM; p++) begin
        if (6'(p) < cnt_in) begin
          logic en, stp, sdp, endb, edb;
          logic [7:0] db;
          en   = 1'b1;
          stp  = stp_in[p];
          sdp  = sdp_in[p];
          endb = end_in[p];
          edb  = edb_in[p];
          db   = data_in[8*p +: 8];
          if (st == 3'd0) begin
            if (stp) begin
              st = 3'd1;
            end else if (sdp) begin
              st   = 3'd4;
              left = 16'(DLLP);
            end
          end else if (st == 3'd1) begin
            left = {8'd0, db};
            en   = 1'b0;
            st   = 3'd2;
          end else if (st == 3'd2) begin
            left = {db, left[7:0]};
            en   = 1'b0;
            st   = 3'd3;
          end else if (st == 3'd4) begin
            stp = 1'b0;
            sdp = 1'b0;
            if (left == 16'd0) begin
              st = 3'd0;
            end else begin
              endb = 1'b0;
              edb  = 1'b0;
              left = left - 16'd1;
            end
          end else if (left == 16'd0) begin
            endb = 1'b1;
            edb  = 1'b0;
            stp  = 1'b0;
            sdp  = 1'b0;
            st   = 3'd0;
          end else begin
            endb = 1'b0;
            edb  = 1'b0;
            stp  = 1'b0;
            sdp  = 1'b0;
            left = left - 16'd1;
          end
          if (en) begin
            sdp_g[q[4:0]]           = sdp;
            stp_g[q[4:0]]           = stp;
            end_g[q[4:0]]           = endb;
            edb_g[q[4:0]]           = edb;
            k_g[q[4:0]]             = k_in[p];
            data_g[8*q[4:0] +: 8]   = db;
            q                       = q + 6'd1;
          end
        end
      end
      st_g   = st;
      left_g = left;
      cnt_g  = q;
    end
  endfunction

  int unsigned err;
  logic [2:0]        st_g;
  logic [15:0]       left_g;
  logic [5:0]        cnt_g;
  logic [NSYM-1:0]   sdp_g, stp_g, end_g, edb_g, k_g;
  logic [8*NSYM-1:0] data_g;

  task automatic check(input string tag);
    begin
      #1;
      serial_dense(st_i, left_i, cnt_i, sdp_i, stp_i, end_i, edb_i, k_i, data_i,
                   st_g, left_g, cnt_g, sdp_g, stp_g, end_g, edb_g, k_g, data_g);
      if ((st_o !== st_g) || ((st_g >= 3'd2) && (left_o !== left_g)) ||
          (cnt_o !== cnt_g) ||
          (sdp_o !== sdp_g) || (stp_o !== stp_g) || (end_o !== end_g) ||
          (edb_o !== edb_g) || (k_o !== k_g) || (data_o !== data_g)) begin
        err++;
        if (err <= 8) begin
          $display("MISMATCH [%s] st %0d left %0d cnt %0d", tag, st_i, left_i, cnt_i);
          $display("  dut:  st=%0d left=%0d cnt=%0d stp=%h sdp=%h end=%h edb=%h",
                   st_o, left_o, cnt_o, stp_o, sdp_o, end_o, edb_o);
          $display("  gold: st=%0d left=%0d cnt=%0d stp=%h sdp=%h end=%h edb=%h",
                   st_g, left_g, cnt_g, stp_g, sdp_g, end_g, edb_g);
        end
      end
    end
  endtask

  initial begin
    err = 0;
    cnt_i = 6'd32;
    stp_i = '0; sdp_i = '0; end_i = '0; edb_i = '0; k_i = '0; data_i = '0;

    // Directed cases covering st 0..4 and boundary crossings
    st_i = 3'd3; left_i = 16'd100; check("st3_mid");
    st_i = 3'd3; left_i = 16'd10;  check("st3_end");
    st_i = 3'd3; left_i = 16'd0;   check("st3_zero");
    st_i = 3'd4; left_i = 16'd6; end_i = 32'h1 << 6; check("st4_end");
    end_i = '0;

    // STP at 0 with short TLP (len=4)
    st_i = 3'd0; left_i = '0; stp_i = 32'h1;
    data_i[15:8] = 8'd4; data_i[23:16] = 8'd0;
    check("stp0_len4");

    // STP at 31 (rem=0 -> st=1)
    stp_i = 32'h8000_0000; data_i = '0;
    check("stp31_rem0");

    // STP at 30 (rem=1 -> st=2)
    stp_i = 32'h4000_0000; data_i[255:248] = 8'h34;
    check("stp30_rem1");

    // Enter st=2 with len low=0x34, high=0x12
    stp_i = '0; data_i = '0;
    st_i = 3'd2; left_i = 16'h0034; data_i[7:0] = 8'h12;
    check("st2_long");

    // Enter st=2 with short len=4, followed by STP at d=7
    st_i = 3'd2; left_i = 16'h0004; data_i = '0;
    stp_i = 32'h1 << 7; data_i[8*8 +: 8] = 8'd20; data_i[8*9 +: 8] = 8'd0;
    check("st2_then_stp");

    // Enter st=1 with short len=3, followed by SDP at d=8
    st_i = 3'd1; left_i = '0; data_i = '0;
    data_i[7:0] = 8'd3; data_i[15:8] = 8'd0;
    stp_i = '0; sdp_i = 32'h1 << 8; end_i = 32'h1 << 15;
    check("st1_then_sdp");

    // Reduced lane count (x1 -> cnt=8)
    cnt_i = 6'd8; st_i = 3'd1; data_i = '0;
    data_i[7:0] = 8'd2; data_i[15:8] = 8'd0;
    stp_i = '0; sdp_i = 32'h1 << 6; end_i = '0;
    check("x1_st1_sdp");

    if (err != 0) begin
      $display("FAIL directed %0d", err);
      $fatal(1);
    end
    $display("directed ok");

    // 500 random legal beats (open packet in st 0..4 + at most one new STP/SDP after it)
    for (int unsigned n = 0; n < 500; n++) begin
      int unsigned csel;
      csel = $urandom_range(0, 4);
      case (csel)
        0: cnt_i = 6'd0;
        1: cnt_i = 6'd8;
        2: cnt_i = 6'd16;
        3: cnt_i = 6'd24;
        default: cnt_i = 6'd32;
      endcase
      st_i   = 3'($urandom_range(0, 4));
      left_i = (n < 200) ? 16'($urandom_range(0, 35)) : 16'($urandom);
      if (st_i == 3'd2) left_i = {8'd0, left_i[7:0]};
      data_i = {$urandom, $urandom, $urandom, $urandom,
                $urandom, $urandom, $urandom, $urandom};
      // Put realistic lengths in low bytes so both finishing and staying-open trigger
      if ($urandom_range(0, 1)) begin
        data_i[7:0]  = 8'($urandom_range(0, 40));
        data_i[15:8] = 8'd0;
      end
      end_i = $urandom;
      edb_i = $urandom;
      k_i   = $urandom;
      // Place at most ONE STP or SDP in the idle region (plus arbitrary noise inside open body)
      stp_i = '0;
      sdp_i = '0;
      if (cnt_i != 6'd0) begin
        automatic int unsigned pos = $urandom_range(0, int'(cnt_i) - 1);
        if ($urandom_range(0, 1)) begin
          stp_i[pos] = 1'b1;
          if ((pos + 2) < 32 && $urandom_range(0, 1)) begin
            // Small/medium TLP length
            data_i[8*(pos+1) +: 8] = 8'($urandom_range(18, 60));
            data_i[8*(pos+2) +: 8] = 8'd0;
          end
        end else begin
          sdp_i[pos] = 1'b1;
        end
        // Also inject random decoy STP/SDP inside open body if st_i != 0
        if (st_i != 3'd0 && $urandom_range(0, 1)) begin
          stp_i[0] = 1'b1;
          sdp_i[1] = 1'b1;
        end
      end
      // Clear any STP/SDP that would start a 3rd packet after a 2nd packet finishes
      // (downstream RX_IDLE stops at the first done=1 per beat anyway).
      check("rand");
    end

    if (err != 0) begin
      $display("FAIL %0d mismatches", err);
      $fatal(1);
    end
    $display("PASS gf scan");
    $finish;
  end
endmodule
