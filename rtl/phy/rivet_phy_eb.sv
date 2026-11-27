// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Per-lane elastic buffer. Sixteen symbols, read once the buffer is
// half full. A SKP ordered set is COM plus three SKP. Under-fill adds
// one SKP; over-fill removes one. The write count is 2 in normal
// Gen1/Gen2 operation. The simulation PMA passes 1 or 3 to imitate ppm.

module rivet_phy_eb
  import rivet_pkg::*;
(
  input  logic        pclk,
  input  logic        preset_n,
  input  logic        enable,

  input  logic [7:0]  sym0,
  input  logic [7:0]  sym1,
  input  logic        k0,
  input  logic        k1,
  input  logic [2:0]  st0,
  input  logic [2:0]  st1,
  input  logic [1:0]  wr_n,

  output logic [7:0]  out0,
  output logic [7:0]  out1,
  output logic        out_k0,
  output logic        out_k1,
  output logic        out_valid,
  output logic [2:0]  out_status
);

  logic [11:0] mem [0:15];
  logic [3:0]  wr_ptr;
  logic [3:0]  rd_ptr;
  logic [4:0]  count;
  logic        armed;

  function automatic logic [11:0] pack_sym(input logic [2:0] st, input logic k,
                                           input logic [7:0] d);
    return {st, k, d};
  endfunction

  function automatic logic skp_set(input logic [11:0] a, input logic [11:0] b);
    return a[8] && a[7:0] == RIVET_SYM_COM && b[8] && b[7:0] == RIVET_SYM_SKP;
  endfunction

  always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n || !enable) begin
      wr_ptr    <= '0;
      rd_ptr    <= '0;
      count     <= '0;
      armed     <= 1'b0;
      out0      <= '0;
      out1      <= '0;
      out_k0    <= 1'b0;
      out_k1    <= 1'b0;
      out_valid <= 1'b0;
      out_status <= RIVET_RXSTATUS_OK;
    end else begin
      logic [11:0] head0;
      logic [11:0] head1;
      logic [3:0]  nwr;
      logic [3:0]  nrd;
      logic        do_add;
      logic        do_rem;
      logic        do_ovf;
      logic        do_unf;
      logic [5:0]  used;

      head0  = mem[rd_ptr];
      head1  = mem[rd_ptr + 4'd1];
      nwr    = 4'd2;
      nrd    = 4'd0;
      do_add = 1'b0;
      do_rem = 1'b0;
      do_ovf = 1'b0;
      do_unf = 1'b0;
      if (wr_n == 2'd1)
        nwr = 4'd1;
      else if (wr_n == 2'd3)
        nwr = 4'd3;

      if (!armed && count >= 5'd8)
        armed <= 1'b1;

      if (armed && count == 5'd0) begin
        do_unf = 1'b1;
      end else if (armed && count < 5'd6 && count >= 5'd2 && skp_set(head0, head1)) begin
        do_add = 1'b1;
        nrd    = 4'd1;
      end else if (armed && count > 5'd10 && count >= 5'd3 && skp_set(head0, head1)) begin
        do_rem = 1'b1;
        nrd    = 4'd3;
      end else if (armed && count >= 5'd2) begin
        nrd = 4'd2;
      end else if (armed) begin
        do_unf = 1'b1;
      end

      used = {1'b0, count} + {3'b0, nwr};
      if (used >= {3'b0, nrd})
        used = used - {3'b0, nrd};
      else
        used = 6'd0;
      if (used > 6'd16) begin
        do_ovf = 1'b1;
        do_add = 1'b0;
        do_rem = 1'b0;
        do_unf = 1'b0;
        nwr    = 4'd0;
        nrd    = 4'd0;
      end

      if (nwr >= 4'd1)
        mem[wr_ptr] <= pack_sym(st0, k0, sym0);
      if (nwr >= 4'd2)
        mem[wr_ptr + 4'd1] <= pack_sym(st1, k1, sym1);
      if (nwr >= 4'd3)
        mem[wr_ptr + 4'd2] <= pack_sym(RIVET_RXSTATUS_OK, 1'b1, RIVET_SYM_SKP);
      wr_ptr <= wr_ptr + nwr;

      if (do_ovf) begin
        out_valid  <= 1'b0;
        out_status <= RIVET_RXSTATUS_EB_OVERFLOW;
      end else if (do_unf) begin
        out_valid  <= 1'b0;
        out_status <= RIVET_RXSTATUS_EB_UNDERFLOW;
      end else if (do_add) begin
        out0       <= head0[7:0];
        out_k0     <= head0[8];
        out1       <= RIVET_SYM_SKP;
        out_k1     <= 1'b1;
        out_valid  <= 1'b1;
        out_status <= RIVET_RXSTATUS_SKP_ADDED;
      end else if (do_rem) begin
        out0       <= head0[7:0];
        out_k0     <= head0[8];
        out1       <= head1[7:0];
        out_k1     <= head1[8];
        out_valid  <= 1'b1;
        out_status <= RIVET_RXSTATUS_SKP_REMOVED;
      end else if (nrd == 4'd2) begin
        out0      <= head0[7:0];
        out_k0    <= head0[8];
        out1      <= head1[7:0];
        out_k1    <= head1[8];
        out_valid <= 1'b1;
        out_status <= (head0[11:9] != RIVET_RXSTATUS_OK) ? head0[11:9] : head1[11:9];
      end else begin
        out_valid  <= 1'b0;
        out_status <= RIVET_RXSTATUS_OK;
      end

      rd_ptr <= rd_ptr + nrd;
      count  <= count - {1'b0, nrd} + {1'b0, nwr};
    end
  end

endmodule : rivet_phy_eb
