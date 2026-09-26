// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Type 0 Cfg completer: 1-deep slot, Cpl/CplD toward DLL, credit accept pulses.

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

  output logic        rx_accept_o,
  output logic [7:0]  rx_hdr0_o,
  output logic [9:0]  rx_len_dw_o,
  output logic        tx_accept_o,
  output logic [7:0]  tx_hdr0_o,
  output logic [9:0]  tx_len_dw_o
);

  import rivet_pkg::*;

  typedef enum logic [1:0] {
    ST_RX  = 2'd0,
    ST_TX0 = 2'd1,
    ST_TX1 = 2'd2
  } st_e;

  st_e          st_q;
  logic [127:0] rx_q;
  logic         have_lo_q;
  logic [7:0]   hdr0_q;
  logic [127:0] tx_q;
  logic         tx_has_data_q;
  logic [31:0]  cfg_q [0:15];

  logic [3:0]  reg_dw;
  logic [15:0] req_id;
  logic [7:0]  tag;
  logic [3:0]  fbe;
  logic [31:0] cfg_rd, cfg_wr, cfg_nxt;
  logic        is_rd, is_wr;

  assign is_rd   = (hdr0_q == RIVET_TLP_B0_CFGRD0);
  assign is_wr   = (hdr0_q == RIVET_TLP_B0_CFGWR0);
  assign req_id  = {rx_q[39:32], rx_q[47:40]};
  assign tag     = rx_q[55:48];
  assign fbe     = rx_q[59:56];
  assign reg_dw  = rx_q[93:90];
  assign cfg_rd  = cfg_q[reg_dw];
  assign cfg_wr  = rx_q[127:96];

  always_comb begin
    cfg_nxt = cfg_rd;
    if (fbe[0]) cfg_nxt[7:0]   = cfg_wr[7:0];
    if (fbe[1]) cfg_nxt[15:8]  = cfg_wr[15:8];
    if (fbe[2]) cfg_nxt[23:16] = cfg_wr[23:16];
    if (fbe[3]) cfg_nxt[31:24] = cfg_wr[31:24];
    if (reg_dw == 4'd4)
      cfg_nxt = cfg_nxt & RIVET_CFG_BAR0_MASK;
  end

  assign rx_tready_o = (st_q == ST_RX);

  assign tx_tdata_o  = (st_q == ST_TX1) ? tx_q[127:64] : tx_q[63:0];
  assign tx_tkeep_o  = (st_q == ST_TX1) ? (tx_has_data_q ? 8'hFF : 8'h0F) : 8'hFF;
  assign tx_tlast_o  = (st_q == ST_TX1);
  assign tx_tvalid_o = (st_q == ST_TX0) || (st_q == ST_TX1);

  assign rx_hdr0_o   = hdr0_q;
  assign rx_len_dw_o = is_wr ? 10'd1 : 10'd0;
  assign tx_hdr0_o   = tx_q[7:0];
  assign tx_len_dw_o = is_rd ? 10'd1 : 10'd0;
  assign rx_accept_o = rx_tvalid_i && rx_tready_o && rx_tlast_i &&
                       ((have_lo_q ? hdr0_q : rx_tdata_i[7:0]) == RIVET_TLP_B0_CFGRD0 ||
                        (have_lo_q ? hdr0_q : rx_tdata_i[7:0]) == RIVET_TLP_B0_CFGWR0);
  assign tx_accept_o = tx_tvalid_o && tx_tready_i && tx_tlast_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q          <= ST_RX;
      rx_q          <= '0;
      have_lo_q     <= 1'b0;
      hdr0_q        <= '0;
      tx_q          <= '0;
      tx_has_data_q <= 1'b0;
      for (int unsigned i = 0; i < 16; i++) cfg_q[i] <= '0;
      cfg_q[0] <= {RIVET_CFG_DEVICE_ID, RIVET_CFG_VENDOR_ID};
      cfg_q[2] <= {RIVET_CFG_CLASS, RIVET_CFG_REV_ID};
    end else begin
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
              have_lo_q     <= 1'b0;
              tx_has_data_q <= (hdr0_q == RIVET_TLP_B0_CFGRD0) ||
                               (!have_lo_q && (rx_tdata_i[7:0] == RIVET_TLP_B0_CFGRD0));
              tx_q[7:0]   <= ((have_lo_q ? hdr0_q : rx_tdata_i[7:0]) == RIVET_TLP_B0_CFGRD0)
                             ? RIVET_TLP_B0_CPLD : RIVET_TLP_B0_CPL;
              tx_q[15:8]  <= 8'h00;
              tx_q[23:16] <= ((have_lo_q ? hdr0_q : rx_tdata_i[7:0]) == RIVET_TLP_B0_CFGRD0)
                             ? 8'h01 : 8'h00;
              tx_q[31:24] <= 8'h00;
              tx_q[39:32] <= 8'h00;
              tx_q[47:40] <= 8'h00;
              tx_q[55:48] <= 8'h00;
              tx_q[63:56] <= 8'h04;
              tx_q[71:64] <= have_lo_q ? rx_q[39:32] : 8'h00;
              tx_q[79:72] <= have_lo_q ? rx_q[47:40] : 8'h00;
              tx_q[87:80] <= have_lo_q ? rx_q[55:48] : 8'h00;
              tx_q[95:88] <= 8'h00;
              if ((have_lo_q ? hdr0_q : rx_tdata_i[7:0]) == RIVET_TLP_B0_CFGRD0) begin
                tx_q[103:96]  <= cfg_q[rx_tdata_i[29:26]][7:0];
                tx_q[111:104] <= cfg_q[rx_tdata_i[29:26]][15:8];
                tx_q[119:112] <= cfg_q[rx_tdata_i[29:26]][23:16];
                tx_q[127:120] <= cfg_q[rx_tdata_i[29:26]][31:24];
              end
              st_q <= ST_TX0;
            end
          end
        end
        ST_TX0: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        end
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) begin
            if (is_wr && ((reg_dw == 4'd1) || (reg_dw == 4'd4)))
              cfg_q[reg_dw] <= cfg_nxt;
            st_q <= ST_RX;
          end
        end
        default: st_q <= ST_RX;
      endcase
    end
  end

endmodule : rivet_tl_cfg
