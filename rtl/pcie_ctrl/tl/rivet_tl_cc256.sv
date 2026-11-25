// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Unpack one 256-bit CC beat into the two 64-bit DLL beats rivet_tl_cc emits.

module rivet_tl_cc256 (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic [255:0] s_axis_cc_tdata,
  input  logic [7:0]   s_axis_cc_tkeep,
  input  logic         s_axis_cc_tlast,
  input  logic         s_axis_cc_tvalid,
  output logic         s_axis_cc_tready,
  input  logic [32:0]  s_axis_cc_tuser,

  output logic [63:0]  tx_tdata_o,
  output logic [7:0]   tx_tkeep_o,
  output logic         tx_tlast_o,
  output logic         tx_tvalid_o,
  input  logic         tx_tready_i,

  output logic         tx_accept_o,
  output logic [7:0]   tx_hdr0_o,
  output logic [9:0]   tx_len_dw_o
);

  import rivet_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_TX0  = 2'd1,
    ST_TX1  = 2'd2
  } st_e;

  st_e          st_q;
  logic [127:0] tx_q;
  logic         has_data_q;
  logic [9:0]   len_q;

  assign s_axis_cc_tready = (st_q == ST_IDLE);
  assign tx_tdata_o  = (st_q == ST_TX1) ? tx_q[127:64] : tx_q[63:0];
  assign tx_tkeep_o  = (st_q == ST_TX1) ? (has_data_q ? 8'hFF : 8'h0F) : 8'hFF;
  assign tx_tlast_o  = (st_q == ST_TX1);
  assign tx_tvalid_o = (st_q == ST_TX0) || (st_q == ST_TX1);
  assign tx_hdr0_o   = tx_q[7:0];
  assign tx_len_dw_o = len_q;
  assign tx_accept_o = tx_tvalid_o && tx_tready_i && tx_tlast_o;

  wire [6:0]  lower_addr = s_axis_cc_tdata[6:0];
  wire [11:0] byte_cnt   = s_axis_cc_tdata[27:16];
  wire [9:0]  dword_cnt  = s_axis_cc_tdata[41:32];
  wire [2:0]  status     = s_axis_cc_tdata[45:43];
  wire [7:0]  tag        = s_axis_cc_tdata[71:64];
  wire [15:0] req_id     = s_axis_cc_tdata[95:80];
  wire [31:0] data       = s_axis_cc_tdata[159:128];
  wire        has_data   = s_axis_cc_tkeep[4];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q       <= ST_IDLE;
      tx_q       <= '0;
      has_data_q <= 1'b0;
      len_q      <= '0;
    end else begin
      unique case (st_q)
        ST_IDLE: begin
          if (s_axis_cc_tvalid && s_axis_cc_tready) begin
            has_data_q <= has_data;
            len_q      <= dword_cnt;
            tx_q[7:0]   <= has_data ? RIVET_TLP_B0_CPLD : RIVET_TLP_B0_CPL;
            tx_q[15:8]  <= 8'h00;
            tx_q[23:16] <= 8'h00;
            tx_q[31:24] <= has_data ? dword_cnt[7:0] : 8'h00;
            tx_q[39:32] <= 8'h00;
            tx_q[47:40] <= 8'h01;
            tx_q[55:48] <= {status, 1'b0, byte_cnt[11:8]};
            tx_q[63:56] <= byte_cnt[7:0];
            tx_q[71:64] <= req_id[7:0];
            tx_q[79:72] <= req_id[15:8];
            tx_q[87:80] <= tag;
            tx_q[95:88] <= {1'b0, lower_addr};
            tx_q[103:96]  <= data[7:0];
            tx_q[111:104] <= data[15:8];
            tx_q[119:112] <= data[23:16];
            tx_q[127:120] <= data[31:24];
            st_q <= ST_TX0;
          end
        end
        ST_TX0: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        end
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_IDLE;
        end
        default: st_q <= ST_IDLE;
      endcase
    end
  end

  wire unused_last = s_axis_cc_tlast;
  wire unused_usr  = |s_axis_cc_tuser;

endmodule : rivet_tl_cc256
