// Compare the framing-scan tree with the original per-symbol walk.
module rivet_mac_gf_scan_tb;
  localparam int unsigned NSYM = 32;
  localparam int unsigned DLLP = 6;

  logic [2:0]        st_i;
  logic [15:0]       left_i;
  logic [NSYM-1:0]   en_i, sdp_i, stp_i, end_i, edb_i;
  logic [8*NSYM-1:0] data_i;
  logic [2:0]        st_o;
  logic [15:0]       left_o;
  logic [NSYM-1:0]   en_o, sdp_o, stp_o, end_o, edb_o;

  rivet_mac_gf_scan #(
    .NSYM(NSYM),
    .DLLP_BYTES(DLLP)
  ) u (
    .st_i, .left_i, .en_i, .sdp_i, .stp_i, .end_i, .edb_i, .data_i,
    .st_o, .left_o, .en_o, .sdp_o, .stp_o, .end_o, .edb_o
  );

  function automatic void serial(
    input  logic [2:0]        st_in,
    input  logic [15:0]       left_in,
    input  logic [NSYM-1:0]   en_in,
    input  logic [NSYM-1:0]   sdp_in,
    input  logic [NSYM-1:0]   stp_in,
    input  logic [NSYM-1:0]   end_in,
    input  logic [NSYM-1:0]   edb_in,
    input  logic [8*NSYM-1:0] data_in,
    output logic [2:0]        st_g,
    output logic [15:0]       left_g,
    output logic [NSYM-1:0]   en_g,
    output logic [NSYM-1:0]   sdp_g,
    output logic [NSYM-1:0]   stp_g,
    output logic [NSYM-1:0]   end_g,
    output logic [NSYM-1:0]   edb_g
  );
    logic [2:0]  st;
    logic [15:0] left;
    begin
      st    = st_in;
      left  = left_in;
      en_g  = en_in;
      sdp_g = sdp_in;
      stp_g = stp_in;
      end_g = end_in;
      edb_g = edb_in;
      for (int unsigned p = 0; p < NSYM; p++) begin
        if (en_g[p]) begin
          if (st == 3'd0) begin
            if (stp_g[p]) begin
              st = 3'd1;
            end else if (sdp_g[p]) begin
              st   = 3'd4;
              left = 16'(DLLP);
            end
          end else if (st == 3'd1) begin
            left      = {8'd0, data_in[8*p +: 8]};
            en_g[p]   = 1'b0;
            stp_g[p]  = 1'b0;
            sdp_g[p]  = 1'b0;
            end_g[p]  = 1'b0;
            edb_g[p]  = 1'b0;
            st        = 3'd2;
          end else if (st == 3'd2) begin
            left      = {data_in[8*p +: 8], left[7:0]};
            en_g[p]   = 1'b0;
            stp_g[p]  = 1'b0;
            sdp_g[p]  = 1'b0;
            end_g[p]  = 1'b0;
            edb_g[p]  = 1'b0;
            st        = 3'd3;
          end else if (st == 3'd4) begin
            stp_g[p] = 1'b0;
            sdp_g[p] = 1'b0;
            if (left == 16'd0) begin
              st = 3'd0;
            end else begin
              end_g[p] = 1'b0;
              edb_g[p] = 1'b0;
              left     = left - 16'd1;
            end
          end else if (left == 16'd0) begin
            end_g[p] = 1'b1;
            edb_g[p] = 1'b0;
            stp_g[p] = 1'b0;
            sdp_g[p] = 1'b0;
            st       = 3'd0;
          end else begin
            end_g[p] = 1'b0;
            edb_g[p] = 1'b0;
            stp_g[p] = 1'b0;
            sdp_g[p] = 1'b0;
            left     = left - 16'd1;
          end
        end
      end
      st_g   = st;
      left_g = left;
    end
  endfunction

  int unsigned n;
  int unsigned err;
  logic [2:0]  st_g;
  logic [15:0] left_g;
  logic [NSYM-1:0] en_g, sdp_g, stp_g, end_g, edb_g;

  task automatic check;
    begin
      #1;
      serial(st_i, left_i, en_i, sdp_i, stp_i, end_i, edb_i, data_i,
             st_g, left_g, en_g, sdp_g, stp_g, end_g, edb_g);
      if ((st_o !== st_g) || (left_o !== left_g) || (en_o !== en_g) ||
          (sdp_o !== sdp_g) || (stp_o !== stp_g) || (end_o !== end_g) ||
          (edb_o !== edb_g)) begin
        err++;
        $display("DIR st %0d left %0d -> tree st %0d left %0d gold st %0d left %0d",
                 st_i, left_i, st_o, left_o, st_g, left_g);
      end
    end
  endtask

  initial begin
    err = 0;
    en_i = {NSYM{1'b1}};
    stp_i = '0; sdp_i = '0; end_i = '0; edb_i = '0; data_i = '0;
    st_i = 3'd3; left_i = 16'd100; check;
    st_i = 3'd3; left_i = 16'd10; check;
    st_i = 3'd3; left_i = 16'd0; check;
    st_i = 3'd4; left_i = 16'd6; check;
    st_i = 3'd0; left_i = '0;
    stp_i = 32'h1; data_i[15:8] = 8'd4; data_i[23:16] = 8'd0; check;
    stp_i = '0; data_i = '0;
    st_i = 3'd2; left_i = 16'h0034; data_i[7:0] = 8'h12; check;
    en_i = 32'hffff_ff00; data_i = '0; data_i[71:64] = 8'h01;
    st_i = 3'd2; left_i = 16'h00aa; check;
    en_i = 32'h8000_0000; data_i = '0; data_i[255:248] = 8'h05;
    st_i = 3'd2; left_i = 16'h0010; check;
    en_i = {NSYM{1'b1}}; data_i = '0; stp_i = 32'h1 << 14;
    data_i[8*15 +: 8] = 8'd4; data_i[8*16 +: 8] = 8'd1;
    st_i = 3'd0; left_i = '0; check;
    stp_i = '0; data_i = '0;
    if (err != 0) begin
      $display("FAIL directed %0d", err);
      $finish(1);
    end
    $display("directed ok");
    for (n = 0; n < 300; n++) begin
      st_i   = $urandom_range(0, 4);
      left_i = (n < 40) ? 16'($urandom_range(0, 40)) : 16'($urandom);
      en_i   = (n % 5 == 0) ? {NSYM{1'b1}} : $urandom;
      stp_i  = en_i & $urandom;
      sdp_i  = en_i & $urandom & ~stp_i;
      end_i  = en_i & $urandom;
      edb_i  = en_i & $urandom;
      data_i = {$urandom, $urandom, $urandom, $urandom,
                $urandom, $urandom, $urandom, $urandom};
      #1;
      serial(st_i, left_i, en_i, sdp_i, stp_i, end_i, edb_i, data_i,
             st_g, left_g, en_g, sdp_g, stp_g, end_g, edb_g);
      if ((st_o !== st_g) || (left_o !== left_g) || (en_o !== en_g) ||
          (sdp_o !== sdp_g) || (stp_o !== stp_g) || (end_o !== end_g) ||
          (edb_o !== edb_g)) begin
        err++;
        if (err < 8) begin
          $display("MISMATCH n=%0d st %0d-> tree %0d gold %0d left %0d-> tree %0d gold %0d",
                   n, st_i, st_o, st_g, left_i, left_o, left_g);
          $display("  en  t=%h g=%h", en_o, en_g);
          $display("  stp t=%h g=%h", stp_o, stp_g);
          $display("  sdp t=%h g=%h", sdp_o, sdp_g);
          $display("  end t=%h g=%h", end_o, end_g);
          $display("  edb t=%h g=%h", edb_o, edb_g);
        end
      end
    end
    if (err != 0) begin
      $display("FAIL %0d mismatches", err);
      $finish(1);
    end
    $display("PASS gf scan");
    $finish(0);
  end
endmodule
