// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// MSI / MSI-X → posted MemWr32 toward DLL (pclk domain).
// MSI uses cfg Message Address/Data; MSI-X uses external table ports.

module rivet_tl_msi (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        bus_master_en_i,
  input  logic        link_up_i,

  // MSI capability snapshot
  input  logic        msi_enable_i,
  input  logic [31:0] msi_addr_i,
  input  logic [15:0] msi_data_i,

  // PG213 MSI request (already synced to pclk)
  input  logic [31:0] msi_int_i,
  output logic        msi_enable_o,
  output logic        msi_sent_o,
  output logic        msi_fail_o,

  // MSI-X external vector (synced)
  input  logic        msix_enable_i,
  input  logic [63:0] msix_addr_i,
  input  logic [31:0] msix_data_i,
  input  logic        msix_int_i,
  output logic        msix_sent_o,
  output logic        msix_fail_o,

  // TL→DLL stream
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

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_TX0  = 2'd1,
    ST_TX1  = 2'd2
  } st_e;

  st_e          st_q;
  logic [127:0] tx_q;
  logic         msi_int_d, msix_int_d;
  logic         pend_msi_q, pend_msix_q;
  logic [31:0]  addr_q;
  logic [31:0]  data_q;
  logic         do_msi, do_msix;
  logic [4:0]   vec;
  int unsigned  vi;
  // Stretch status pulses so multi-flop CDC to user_clk cannot drop them.
  logic [4:0]   msi_sent_cnt_q, msi_fail_cnt_q, msix_sent_cnt_q, msix_fail_cnt_q;

  assign msi_enable_o = msi_enable_i;
  assign tx_tdata_o   = (st_q == ST_TX1) ? tx_q[127:64] : tx_q[63:0];
  assign tx_tkeep_o   = 8'hFF;
  assign tx_tlast_o   = (st_q == ST_TX1);
  assign tx_tvalid_o  = (st_q == ST_TX0) || (st_q == ST_TX1);
  assign tx_hdr0_o    = RIVET_TLP_B0_MEMWR32;
  assign tx_len_dw_o  = 10'd1;
  assign tx_accept_o  = tx_tvalid_o && tx_tready_i && tx_tlast_o;
  assign msi_sent_o   = |msi_sent_cnt_q;
  assign msi_fail_o   = |msi_fail_cnt_q;
  assign msix_sent_o  = |msix_sent_cnt_q;
  assign msix_fail_o  = |msix_fail_cnt_q;

  always_comb begin
    vec = 5'd0;
    for (vi = 0; vi < 32; vi++)
      if (msi_int_i[vi]) vec = 5'(vi);
    do_msi  = (|msi_int_i) && !msi_int_d;
    do_msix = msix_int_i && !msix_int_d;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q             <= ST_IDLE;
      tx_q             <= '0;
      msi_int_d        <= 1'b0;
      msix_int_d       <= 1'b0;
      pend_msi_q       <= 1'b0;
      pend_msix_q      <= 1'b0;
      addr_q           <= '0;
      data_q           <= '0;
      msi_sent_cnt_q   <= '0;
      msi_fail_cnt_q   <= '0;
      msix_sent_cnt_q  <= '0;
      msix_fail_cnt_q  <= '0;
    end else begin
      if (msi_sent_cnt_q  != '0) msi_sent_cnt_q  <= msi_sent_cnt_q  - 5'd1;
      if (msi_fail_cnt_q  != '0) msi_fail_cnt_q  <= msi_fail_cnt_q  - 5'd1;
      if (msix_sent_cnt_q != '0) msix_sent_cnt_q <= msix_sent_cnt_q - 5'd1;
      if (msix_fail_cnt_q != '0) msix_fail_cnt_q <= msix_fail_cnt_q - 5'd1;

      msi_int_d  <= |msi_int_i;
      msix_int_d <= msix_int_i;

      if (do_msi) begin
        if (msi_enable_i && bus_master_en_i && link_up_i) begin
          pend_msi_q <= 1'b1;
          addr_q     <= msi_addr_i;
          data_q     <= {16'h0, msi_data_i[15:5], vec};
        end else
          msi_fail_cnt_q <= 5'd16;
      end
      if (do_msix) begin
        if (msix_enable_i && bus_master_en_i && link_up_i && (msix_addr_i[63:32] == 32'h0)) begin
          pend_msix_q <= 1'b1;
          addr_q      <= msix_addr_i[31:0];
          data_q      <= msix_data_i;
        end else
          msix_fail_cnt_q <= 5'd16;
      end

      unique case (st_q)
        ST_IDLE: begin
          if (pend_msi_q || pend_msix_q) begin
            tx_q[7:0]     <= RIVET_TLP_B0_MEMWR32;
            tx_q[15:8]    <= 8'h00;
            tx_q[23:16]   <= 8'h00;
            tx_q[31:24]   <= 8'h01;
            tx_q[39:32]   <= 8'h00;
            tx_q[47:40]   <= 8'h01;
            tx_q[55:48]   <= 8'h00;
            tx_q[59:56]   <= 4'hF;
            tx_q[63:60]   <= 4'h0;
            tx_q[71:64]   <= addr_q[31:24];
            tx_q[79:72]   <= addr_q[23:16];
            tx_q[87:80]   <= addr_q[15:8];
            tx_q[95:88]   <= addr_q[7:0];
            tx_q[103:96]  <= data_q[7:0];
            tx_q[111:104] <= data_q[15:8];
            tx_q[119:112] <= data_q[23:16];
            tx_q[127:120] <= data_q[31:24];
            st_q <= ST_TX0;
          end
        end
        ST_TX0: if (tx_tvalid_o && tx_tready_i) st_q <= ST_TX1;
        ST_TX1: begin
          if (tx_tvalid_o && tx_tready_i) begin
            if (pend_msi_q) begin
              msi_sent_cnt_q <= 5'd16;
              pend_msi_q     <= 1'b0;
            end else begin
              msix_sent_cnt_q <= 5'd16;
              pend_msix_q     <= 1'b0;
            end
            st_q <= ST_IDLE;
          end
        end
        default: st_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_tl_msi
