// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Unpack PG213-style 64-bit AXI-ST Completer Completion (CC) into wire TLP bytes.

module rivet_tl_cc (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [63:0] s_axis_cc_tdata,
  input  logic [1:0]  s_axis_cc_tkeep,
  input  logic        s_axis_cc_tlast,
  input  logic        s_axis_cc_tvalid,
  output logic        s_axis_cc_tready,
  input  logic [32:0] s_axis_cc_tuser,

  output logic [63:0] tx_tdata_o,
  output logic [7:0]  tx_tkeep_o,
  output logic        tx_tlast_o,
  output logic        tx_tvalid_o,
  input  logic        tx_tready_i,

  output logic        tx_accept_o,
  output logic [7:0]  tx_hdr0_o,
  output logic [9:0]  tx_len_dw_o
);

  import rivet_pkg::*;

  typedef enum logic [2:0] {
    ST_D0  = 3'd0,
    ST_D1  = 3'd1,
    ST_DAT = 3'd2,
    ST_TX0 = 3'd3,
    ST_TX1 = 3'd4
  } st_e;

  st_e          st_q;
  logic [127:0] tx_q;
  logic         has_data_q;
  logic [9:0]   len_q;

  // Captured CC descriptor fields
  logic [6:0]  lower_addr_q;
  logic [11:0] byte_cnt_q;
  logic [2:0]  status_q;
  logic [15:0] req_id_q;
  logic [7:0]  tag_q;
  logic [31:0] data_q;

  assign s_axis_cc_tready = (st_q == ST_D0) || (st_q == ST_D1) || (st_q == ST_DAT);

  assign tx_tdata_o  = (st_q == ST_TX1) ? tx_q[127:64] : tx_q[63:0];
  assign tx_tkeep_o  = (st_q == ST_TX1) ? (has_data_q ? 8'hFF : 8'h0F) : 8'hFF;
  assign tx_tlast_o  = (st_q == ST_TX1);
  assign tx_tvalid_o = (st_q == ST_TX0) || (st_q == ST_TX1);
  assign tx_hdr0_o   = tx_q[7:0];
  assign tx_len_dw_o = len_q;
  assign tx_accept_o = tx_tvalid_o && tx_tready_i && tx_tlast_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q         <= ST_D0;
      tx_q         <= '0;
      has_data_q   <= 1'b0;
      len_q        <= '0;
      lower_addr_q <= '0;
      byte_cnt_q   <= '0;
      status_q     <= '0;
      req_id_q     <= '0;
      tag_q        <= '0;
      data_q       <= '0;
    end else begin
      unique case (st_q)
        ST_D0: begin
          // Beat0: DW0 = {Force_ECRC, Attr, TC, Completer ID_en, Completer ID,
          //               Tag, Req ID?} — use PG213 CC layout for 64b:
          // tdata[6:0]   lower address
          // tdata[9:8]   AT
          // tdata[28:16] byte count
          // tdata[42:32] dword count
          // tdata[45:43] completion status
          if (s_axis_cc_tvalid && s_axis_cc_tready) begin
            lower_addr_q <= s_axis_cc_tdata[6:0];
            byte_cnt_q   <= s_axis_cc_tdata[27:16];
            len_q        <= s_axis_cc_tdata[41:32];
            status_q     <= s_axis_cc_tdata[45:43];
            st_q <= ST_D1;
          end
        end
        ST_D1: begin
          // Beat1: requester ID [31:16], tag [7:0], completer ID [63:48]
          if (s_axis_cc_tvalid && s_axis_cc_tready) begin
            req_id_q <= s_axis_cc_tdata[31:16];
            tag_q    <= s_axis_cc_tdata[7:0];
            if (s_axis_cc_tlast) begin
              has_data_q <= 1'b0;
              // Build Cpl (no data)
              tx_q[7:0]   <= RIVET_TLP_B0_CPL;
              tx_q[15:8]  <= 8'h00;
              tx_q[23:16] <= 8'h00;
              tx_q[31:24] <= 8'h00;
              tx_q[39:32] <= 8'h00;
              tx_q[47:40] <= 8'h01;
              tx_q[55:48] <= {status_q, 1'b0, byte_cnt_q[11:8]};
              tx_q[63:56] <= byte_cnt_q[7:0];
              tx_q[71:64] <= s_axis_cc_tdata[23:16];
              tx_q[79:72] <= s_axis_cc_tdata[31:24];
              tx_q[87:80] <= s_axis_cc_tdata[7:0];
              tx_q[95:88] <= {1'b0, lower_addr_q};
              st_q <= ST_TX0;
            end else begin
              has_data_q <= 1'b1;
              st_q <= ST_DAT;
            end
          end
        end
        ST_DAT: begin
          if (s_axis_cc_tvalid && s_axis_cc_tready) begin
            data_q <= s_axis_cc_tdata[31:0];
            // Build CplD
            tx_q[7:0]   <= RIVET_TLP_B0_CPLD;
            tx_q[15:8]  <= 8'h00;
            tx_q[23:16] <= 8'h00;
            tx_q[31:24] <= len_q[7:0];
            tx_q[39:32] <= 8'h00;
            tx_q[47:40] <= 8'h01;
            tx_q[55:48] <= {status_q, 1'b0, byte_cnt_q[11:8]};
            tx_q[63:56] <= byte_cnt_q[7:0];
            tx_q[71:64] <= req_id_q[7:0];
            tx_q[79:72] <= req_id_q[15:8];
            tx_q[87:80] <= tag_q;
            tx_q[95:88] <= {1'b0, lower_addr_q};
            tx_q[103:96]  <= s_axis_cc_tdata[7:0];
            tx_q[111:104] <= s_axis_cc_tdata[15:8];
            tx_q[119:112] <= s_axis_cc_tdata[23:16];
            tx_q[127:120] <= s_axis_cc_tdata[31:24];
            st_q <= ST_TX0;
          end
        end
        ST_TX0: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        end
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_D0;
        end
        default: st_q <= ST_D0;
      endcase
    end
  end

  wire unused_keep = |s_axis_cc_tkeep;
  wire unused_usr  = |s_axis_cc_tuser;
  wire unused_data = |data_q;

endmodule : rivet_tl_cc
