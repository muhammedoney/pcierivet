// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// EP completer smoke: Type 0 Cfg + Mem32 1/2 DW to BAR0 PIO.

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

  localparam int unsigned CFG_N = 64;
  localparam int unsigned PIO_N = 256;

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
  logic [9:0]   tx_len_q;
  logic [31:0]  cfg_q [0:CFG_N-1];
  logic [31:0]  pio_q [0:PIO_N-1];

  logic [5:0]  reg_dw;
  logic [15:0] req_id;
  logic [7:0]  tag;
  logic [3:0]  fbe;
  logic [31:0] cfg_rd, cfg_wr, cfg_nxt;
  logic        is_cfgrd, is_cfgwr, is_memrd, is_memwr;
  logic [31:0] mem_addr, mem_data0;
  logic [7:0]  pio_idx;
  logic [9:0]  req_len;

  function automatic logic is_cfg_b0(input logic [7:0] b0);
    return (b0 == RIVET_TLP_B0_CFGRD0) || (b0 == RIVET_TLP_B0_CFGWR0);
  endfunction

  function automatic logic is_mem_b0(input logic [7:0] b0);
    return (b0 == RIVET_TLP_B0_MEMRD32) || (b0 == RIVET_TLP_B0_MEMWR32);
  endfunction

  assign is_cfgrd = (hdr0_q == RIVET_TLP_B0_CFGRD0);
  assign is_cfgwr = (hdr0_q == RIVET_TLP_B0_CFGWR0);
  assign is_memrd = (hdr0_q == RIVET_TLP_B0_MEMRD32);
  assign is_memwr = (hdr0_q == RIVET_TLP_B0_MEMWR32);
  assign req_id   = {rx_q[39:32], rx_q[47:40]};
  assign tag      = rx_q[55:48];
  assign fbe      = rx_q[59:56];
  assign req_len  = rivet_tlp_len_dw(rx_q[23:16], rx_q[31:24]);
  assign reg_dw   = rx_q[95:90];
  assign cfg_rd   = cfg_q[reg_dw];
  assign cfg_wr   = rx_q[127:96];
  assign mem_addr = {rx_q[71:64], rx_q[79:72], rx_q[87:80], rx_q[95:88]};
  assign mem_data0 = rx_q[127:96];
  assign pio_idx   = mem_addr[9:2];

  always_comb begin
    cfg_nxt = cfg_rd;
    if (fbe[0]) cfg_nxt[7:0]   = cfg_wr[7:0];
    if (fbe[1]) cfg_nxt[15:8]  = cfg_wr[15:8];
    if (fbe[2]) cfg_nxt[23:16] = cfg_wr[23:16];
    if (fbe[3]) cfg_nxt[31:24] = cfg_wr[31:24];
    if (reg_dw == 6'd4)
      cfg_nxt = cfg_nxt & RIVET_CFG_BAR0_MASK;
  end

  assign rx_tready_o = (st_q == ST_RX);

  assign tx_tdata_o  = (st_q == ST_TX1) ? tx_q[127:64] : tx_q[63:0];
  assign tx_tkeep_o  = (st_q == ST_TX1) ? (tx_has_data_q ? 8'hFF : 8'h0F) : 8'hFF;
  assign tx_tlast_o  = (st_q == ST_TX1);
  assign tx_tvalid_o = (st_q == ST_TX0) || (st_q == ST_TX1);

  assign rx_hdr0_o   = hdr0_q;
  assign rx_len_dw_o = (is_cfgwr || is_memwr) ? ((req_len == 10'd0) ? 10'd1 : req_len) : 10'd0;
  assign tx_hdr0_o   = tx_q[7:0];
  assign tx_len_dw_o = tx_len_q;
  assign rx_accept_o = rx_tvalid_i && rx_tready_o && rx_tlast_i &&
                       (is_cfg_b0(have_lo_q ? hdr0_q : rx_tdata_i[7:0]) ||
                        is_mem_b0(have_lo_q ? hdr0_q : rx_tdata_i[7:0]));
  assign tx_accept_o = tx_tvalid_o && tx_tready_i && tx_tlast_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q          <= ST_RX;
      rx_q          <= '0;
      have_lo_q     <= 1'b0;
      hdr0_q        <= '0;
      tx_q          <= '0;
      tx_has_data_q <= 1'b0;
      tx_len_q      <= '0;
      for (int unsigned i = 0; i < CFG_N; i++) cfg_q[i] <= '0;
      for (int unsigned i = 0; i < PIO_N; i++) pio_q[i] <= '0;
      cfg_q[0]  <= {RIVET_CFG_DEVICE_ID, RIVET_CFG_VENDOR_ID};
      cfg_q[2]  <= {RIVET_CFG_CLASS, RIVET_CFG_REV_ID};
      cfg_q[13] <= 32'h0000_0070;          // capabilities pointer
      cfg_q[28] <= 32'h0002_0010;          // PCIe cap ID at 0x70
      cfg_q[29] <= 32'h0000_0000;          // Device Cap, CMPS=128B
      cfg_q[31] <= 32'h0000_0041;          // Link Cap: speed=1, width=4 (PG213 RP BFM is Gen1)
      cfg_q[32] <= 32'h0041_0000;          // Link Status: speed=1, width=4
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
              automatic logic [7:0] b0;
              automatic logic [5:0] rdw;
              automatic logic [31:0] maddr, mdata, crd;
              automatic logic [7:0]  pidx;
              b0 = have_lo_q ? hdr0_q : rx_tdata_i[7:0];
              have_lo_q <= 1'b0;
              if (b0 == RIVET_TLP_B0_MEMWR32) begin
                maddr = {rx_tdata_i[7:0], rx_tdata_i[15:8],
                         rx_tdata_i[23:16], rx_tdata_i[31:24]};
                mdata = rx_tdata_i[63:32];
                pidx  = maddr[9:2];
                pio_q[pidx] <= mdata;
                st_q <= ST_RX;
              end else begin
                tx_has_data_q <= (b0 == RIVET_TLP_B0_CFGRD0) || (b0 == RIVET_TLP_B0_MEMRD32);
                tx_len_q      <= ((b0 == RIVET_TLP_B0_CFGRD0) || (b0 == RIVET_TLP_B0_MEMRD32))
                                 ? 10'd1 : 10'd0;
                tx_q[7:0]   <= ((b0 == RIVET_TLP_B0_CFGRD0) || (b0 == RIVET_TLP_B0_MEMRD32))
                               ? RIVET_TLP_B0_CPLD : RIVET_TLP_B0_CPL;
                tx_q[15:8]  <= 8'h00;
                tx_q[23:16] <= 8'h00; // B2: Attr/AT/Length[9:8]
                tx_q[31:24] <= ((b0 == RIVET_TLP_B0_CFGRD0) || (b0 == RIVET_TLP_B0_MEMRD32))
                               ? 8'h01 : 8'h00; // B3: Length[7:0]
                tx_q[39:32] <= 8'h00; // completer ID[7:0]
                tx_q[47:40] <= 8'h01; // completer ID[15:8] bus=1 (PG213 EP)
                tx_q[55:48] <= 8'h00;
                tx_q[63:56] <= 8'h04;
                tx_q[71:64] <= have_lo_q ? rx_q[39:32] : 8'h00;
                tx_q[79:72] <= have_lo_q ? rx_q[47:40] : 8'h00;
                tx_q[87:80] <= have_lo_q ? rx_q[55:48] : 8'h00;
                tx_q[95:88] <= 8'h00;
                if (b0 == RIVET_TLP_B0_CFGRD0) begin
                  rdw = rx_tdata_i[31:26];
                  crd = cfg_q[rdw];
                  tx_q[103:96]  <= crd[7:0];
                  tx_q[111:104] <= crd[15:8];
                  tx_q[119:112] <= crd[23:16];
                  tx_q[127:120] <= crd[31:24];
                end else if (b0 == RIVET_TLP_B0_MEMRD32) begin
                  maddr = {rx_tdata_i[7:0], rx_tdata_i[15:8],
                           rx_tdata_i[23:16], rx_tdata_i[31:24]};
                  crd = pio_q[maddr[9:2]];
                  tx_q[103:96]  <= crd[7:0];
                  tx_q[111:104] <= crd[15:8];
                  tx_q[119:112] <= crd[23:16];
                  tx_q[127:120] <= crd[31:24];
                  tx_q[95:88]   <= {1'b0, maddr[6:0]};
                end
                st_q <= ST_TX0;
              end
            end
          end
        end
        ST_TX0: begin
          if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        end
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) begin
            if (is_cfgwr && ((reg_dw == 6'd1) || (reg_dw == 6'd4) ||
                             (reg_dw == 6'd30)))
              cfg_q[reg_dw] <= cfg_nxt;
            st_q <= ST_RX;
          end
        end
        default: st_q <= ST_RX;
      endcase
    end
  end

endmodule : rivet_tl_cfg
