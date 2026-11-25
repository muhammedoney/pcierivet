// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// CQ MemWr is translated onto RQ at 64, 128, and 256 bits. A config
// request is dropped on every width.

module rivet_sw_fwd_tb;
  logic clk = 0;
  logic rst_n = 0;
  int unsigned errors;

  always #5 clk = ~clk;

  localparam logic [63:0] B0    = 64'h0000_0000_0000_1000;
  localparam logic [63:0] CQ_B1 = 64'h0011_0100_0000_0801;
  localparam logic [63:0] DATA  = 64'h0000_0000_A5A5_5A5A;
  localparam logic [63:0] RQ_B1 = 64'h0001_0011_0000_0801;
  localparam logic [63:0] CFG_B1 = 64'h0022_0200_0000_580B;

  task automatic check(input int unsigned n, input logic got_ok, input string what);
    if (!got_ok) begin
      $display("FAIL %s beat %0d", what, n);
      errors = errors + 1;
    end
  endtask

  // 64-bit: three beats, tag moved to [39:32].
  logic [63:0] s64, m64;
  logic [1:0]  sk64, mk64;
  logic [87:0] su64, mu64;
  logic        sl64, sv64, sr64, ml64, mv64, mr64;
  int unsigned n64;
  rivet_sw_posted_fwd #(.DATA_W(64)) u64 (
    .clk_i(clk), .rst_ni(rst_n),
    .s_tdata_i(s64), .s_tkeep_i(sk64), .s_tlast_i(sl64),
    .s_tvalid_i(sv64), .s_tready_o(sr64), .s_tuser_i(su64),
    .m_tdata_o(m64), .m_tkeep_o(mk64), .m_tlast_o(ml64),
    .m_tvalid_o(mv64), .m_tready_i(mr64), .m_tuser_o(mu64)
  );

  task automatic send64(input logic [63:0] data, input logic last);
    @(posedge clk);
    while (!sr64) @(posedge clk);
    s64 <= data; sk64 <= 2'b11; sl64 <= last; sv64 <= 1'b1; su64 <= 88'h5A;
    @(posedge clk);
    sv64 <= 1'b0;
  endtask

  // 128-bit: descriptor beat then dword beat.
  logic [127:0] s128, m128;
  logic [3:0]   sk128, mk128;
  logic [87:0]  su128, mu128;
  logic         sl128, sv128, sr128, ml128, mv128, mr128;
  int unsigned  n128;
  rivet_sw_posted_fwd #(.DATA_W(128)) u128 (
    .clk_i(clk), .rst_ni(rst_n),
    .s_tdata_i(s128), .s_tkeep_i(sk128), .s_tlast_i(sl128),
    .s_tvalid_i(sv128), .s_tready_o(sr128), .s_tuser_i(su128),
    .m_tdata_o(m128), .m_tkeep_o(mk128), .m_tlast_o(ml128),
    .m_tvalid_o(mv128), .m_tready_i(mr128), .m_tuser_o(mu128)
  );

  task automatic send128(input logic [63:0] data, input logic last);
    @(posedge clk);
    while (!sr128) @(posedge clk);
    s128 <= {64'h0, data}; sk128 <= 4'h3; sl128 <= last;
    sv128 <= 1'b1; su128 <= 88'hA5;
    @(posedge clk);
    sv128 <= 1'b0;
  endtask

  // 256-bit: one beat, dword above the descriptor.
  logic [255:0] s256, m256;
  logic [7:0]   sk256, mk256;
  logic [87:0]  su256, mu256;
  logic         sl256, sv256, sr256, ml256, mv256, mr256;
  int unsigned  n256;
  rivet_sw_posted_fwd #(.DATA_W(256)) u256 (
    .clk_i(clk), .rst_ni(rst_n),
    .s_tdata_i(s256), .s_tkeep_i(sk256), .s_tlast_i(sl256),
    .s_tvalid_i(sv256), .s_tready_o(sr256), .s_tuser_i(su256),
    .m_tdata_o(m256), .m_tkeep_o(mk256), .m_tlast_o(ml256),
    .m_tvalid_o(mv256), .m_tready_i(mr256), .m_tuser_o(mu256)
  );

  task automatic send256(input logic [63:0] data, input logic last);
    @(posedge clk);
    while (!sr256) @(posedge clk);
    s256 <= {192'h0, data}; sk256 <= 8'h03; sl256 <= last;
    sv256 <= 1'b1; su256 <= 88'h3C;
    @(posedge clk);
    sv256 <= 1'b0;
  endtask

  always @(posedge clk) begin
    if (rst_n && mv64 && mr64) begin
      if (n64 == 0) check(0, m64 == B0, "w64");
      else if (n64 == 1) check(1, m64 == RQ_B1, "w64");
      else if (n64 == 2) check(2, m64 == DATA && ml64, "w64");
      else check(n64, 1'b0, "w64 extra");
      n64 = n64 + 1;
    end
    if (rst_n && mv128 && mr128) begin
      if (n128 == 0)
        check(0, m128 == {RQ_B1, B0} && mk128 == 4'hF && mu128 == 88'hA5, "w128");
      else if (n128 == 1)
        check(1, m128[31:0] == DATA[31:0] && ml128 && mk128 == 4'h1, "w128");
      else
        check(n128, 1'b0, "w128 extra");
      n128 = n128 + 1;
    end
    if (rst_n && mv256 && mr256) begin
      if (n256 == 0)
        check(0, m256[127:0] == {RQ_B1, B0} && m256[159:128] == DATA[31:0] &&
               ml256 && mk256[4:0] == 5'b1_1111 && mu256 == 88'h3C, "w256");
      else
        check(n256, 1'b0, "w256 extra");
      n256 = n256 + 1;
    end
  end

  initial begin
    s64 = '0; sk64 = '0; sl64 = 0; sv64 = 0; su64 = '0; mr64 = 1; n64 = 0;
    s128 = '0; sk128 = '0; sl128 = 0; sv128 = 0; su128 = '0; mr128 = 1; n128 = 0;
    s256 = '0; sk256 = '0; sl256 = 0; sv256 = 0; su256 = '0; mr256 = 1; n256 = 0;
    errors = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    send64(B0, 0); send64(CQ_B1, 0); send64(DATA, 1);
    send64(64'h1, 0); send64(CFG_B1, 0); send64(DATA, 1);

    send128(B0, 0); send128(CQ_B1, 0); send128(DATA, 1);
    send128(64'h1, 0); send128(CFG_B1, 0); send128(DATA, 1);

    send256(B0, 0); send256(CQ_B1, 0); send256(DATA, 1);
    send256(64'h1, 0); send256(CFG_B1, 0); send256(DATA, 1);

    repeat (10) @(posedge clk);
    if (n64 != 3) begin $display("FAIL w64 count %0d", n64); errors++; end
    if (n128 != 2) begin $display("FAIL w128 count %0d", n128); errors++; end
    if (n256 != 1) begin $display("FAIL w256 count %0d", n256); errors++; end
    if (errors == 0)
      $display("PASS: switch posted MemWr forwarded at 64/128/256, config dropped");
    else
      $display("FAIL: switch forwarder errors=%0d", errors);
    $finish;
  end
endmodule
