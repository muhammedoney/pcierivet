// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Fabric Type 0 CfgRd0/CfgWr0 completer. Config file is rivet_tl_cfg_space.

module rivet_tl_cfg (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [63:0] rx_tdata_i,
  input  logic [7:0]  rx_tkeep_i,
  input  logic        rx_tlast_i,
  input  logic        rx_tvalid_i,
  output logic        rx_tready_o,

  output logic [63:0] tx_tdata_o,
  output logic [7:0]  tx_tkeep_o,
  output logic        tx_tlast_o,
  output logic        tx_tvalid_o,
  input  logic        tx_tready_i,

  // Config-space access
  output logic        fab_req_o,
  output logic        fab_write_o,
  output logic [9:0]  fab_addr_o,
  output logic [3:0]  fab_be_o,
  output logic [31:0] fab_wdata_o,
  input  logic [31:0] fab_rdata_i,
  input  logic        fab_ack_i,
  input  logic        fab_busy_i,

  output logic        rx_accept_o,
  output logic [7:0]  rx_hdr0_o,
  output logic [9:0]  rx_len_dw_o,
  output logic        tx_accept_o,
  output logic [7:0]  tx_hdr0_o,
  output logic [9:0]  tx_len_dw_o
);

  import rivet_pkg::*;

  typedef enum logic [2:0] {
    ST_RX    = 3'd0,
    ST_SPACE = 3'd1,
    ST_TX0   = 3'd2,
    ST_TX1   = 3'd3
  } st_e;

  st_e          st_q;
  logic [127:0] rx_q;
  logic         have_lo_q;
  logic [7:0]   hdr0_q;
  logic [127:0] tx_q;
  logic         tx_has_data_q;
  logic [9:0]   tx_len_q;
  logic [9:0]   reg_dw_q;
  logic [3:0]   fbe_q;
  logic [31:0]  wdata_q;
  logic         is_wr_q;
  logic         fab_req_q;

  logic is_cfgrd, is_cfgwr;
  logic [9:0] req_len;

  function automatic logic is_cfg_b0(input logic [7:0] b0);
    return (b0 == RIVET_TLP_B0_CFGRD0) || (b0 == RIVET_TLP_B0_CFGWR0);
  endfunction

  assign is_cfgrd = (hdr0_q == RIVET_TLP_B0_CFGRD0);
  assign is_cfgwr = (hdr0_q == RIVET_TLP_B0_CFGWR0);
  assign req_len  = rivet_tlp_len_dw(rx_q[23:16], rx_q[31:24]);

  assign rx_tready_o = (st_q == ST_RX) && !fab_busy_i;

  assign tx_tdata_o  = (st_q == ST_TX1) ? tx_q[127:64] : tx_q[63:0];
  assign tx_tkeep_o  = (st_q == ST_TX1) ? (tx_has_data_q ? 8'hFF : 8'h0F) : 8'hFF;
  assign tx_tlast_o  = (st_q == ST_TX1);
  assign tx_tvalid_o = (st_q == ST_TX0) || (st_q == ST_TX1);

  assign rx_hdr0_o   = hdr0_q;
  assign rx_len_dw_o = is_cfgwr ? ((req_len == 10'd0) ? 10'd1 : req_len) : 10'd0;
  assign tx_hdr0_o   = tx_q[7:0];
  assign tx_len_dw_o = tx_len_q;
  assign rx_accept_o = rx_tvalid_i && rx_tready_o && rx_tlast_i &&
                       is_cfg_b0(have_lo_q ? hdr0_q : rx_tdata_i[7:0]);
  assign tx_accept_o = tx_tvalid_o && tx_tready_i && tx_tlast_o;

  assign fab_req_o   = fab_req_q;
  assign fab_write_o = is_wr_q;
  assign fab_addr_o  = reg_dw_q;
  assign fab_be_o    = fbe_q;
  assign fab_wdata_o = wdata_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q          <= ST_RX;
      rx_q          <= '0;
      have_lo_q     <= 1'b0;
      hdr0_q        <= '0;
      tx_q          <= '0;
      tx_has_data_q <= 1'b0;
      tx_len_q      <= '0;
      reg_dw_q      <= '0;
      fbe_q         <= '0;
      wdata_q       <= '0;
      is_wr_q       <= 1'b0;
      fab_req_q     <= 1'b0;
    end else begin
      fab_req_q <= 1'b0;

      unique case (st_q)
        ST_RX: begin
          if (rx_tvalid_i && rx_tready_o) begin
            if (!have_lo_q) begin
              rx_q[63:0] <= rx_tdata_i;
              hdr0_q     <= rx_tdata_i[7:0];
              have_lo_q  <= 1'b1;
            end else begin
              rx_q[127:64] <= rx_tdata_i;
            end
            if (rx_tlast_i) begin
              automatic logic [7:0] b0;
              b0 = have_lo_q ? hdr0_q : rx_tdata_i[7:0];
              have_lo_q <= 1'b0;
              if (is_cfg_b0(b0)) begin
                reg_dw_q  <= {4'h0, rx_tdata_i[31:26]};
                fbe_q     <= have_lo_q ? rx_q[59:56] : 4'hF;
                wdata_q   <= rx_tdata_i[63:32];
                is_wr_q   <= (b0 == RIVET_TLP_B0_CFGWR0);
                fab_req_q <= 1'b1;
                // Stash requester ID / tag for Cpl
                tx_q[71:64] <= have_lo_q ? rx_q[39:32] : 8'h00;
                tx_q[79:72] <= have_lo_q ? rx_q[47:40] : 8'h00;
                tx_q[87:80] <= have_lo_q ? rx_q[55:48] : 8'h00;
                st_q <= ST_SPACE;
              end
            end
          end
        end
        ST_SPACE: begin
          if (fab_ack_i) begin
            tx_has_data_q <= !is_wr_q;
            tx_len_q      <= is_wr_q ? 10'd0 : 10'd1;
            tx_q[7:0]   <= is_wr_q ? RIVET_TLP_B0_CPL : RIVET_TLP_B0_CPLD;
            tx_q[15:8]  <= 8'h00;
            tx_q[23:16] <= 8'h00;
            tx_q[31:24] <= is_wr_q ? 8'h00 : 8'h01;
            tx_q[39:32] <= 8'h00;
            tx_q[47:40] <= 8'h01; // Completer ID bus=1
            tx_q[55:48] <= 8'h00;
            tx_q[63:56] <= 8'h04; // byte count
            tx_q[95:88] <= 8'h00;
            if (!is_wr_q) begin
              tx_q[103:96]  <= fab_rdata_i[7:0];
              tx_q[111:104] <= fab_rdata_i[15:8];
              tx_q[119:112] <= fab_rdata_i[23:16];
              tx_q[127:120] <= fab_rdata_i[31:24];
            end
            st_q <= ST_TX0;
          end
        end
        ST_TX0: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        end
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_RX;
        end
        default: st_q <= ST_RX;
      endcase
    end
  end

  wire unused_keep = |rx_tkeep_i;
  wire unused_rd   = is_cfgrd;

endmodule : rivet_tl_cfg
