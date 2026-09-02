// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack TL→DLL AXI-ST-like beats into one whole TLP payload for rivet_dll_tlp_tx.

module rivet_dll_tl_pack #(
  parameter int unsigned DATA_W     = rivet_pkg::RIVET_TL_DLL_DATA_W,
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [DATA_W-1:0]              s_tdata_i,
  input  logic [DATA_W/8-1:0]            s_tkeep_i,
  input  logic                           s_tlast_i,
  input  logic                           s_tvalid_i,
  output logic                           s_tready_o,

  output logic                           m_valid_o,
  input  logic                           m_ready_i,
  output logic [SLOT_BYTES*8-1:0]        m_data_o,
  output logic [15:0]                    m_len_o
);

  localparam int unsigned KEEP_W = DATA_W / 8;
  localparam int unsigned OFF_W  = (SLOT_BYTES <= 1) ? 1 : $clog2(SLOT_BYTES + 1);

  logic [SLOT_BYTES*8-1:0] buf_q;
  logic [OFF_W-1:0]        len_q;
  logic                    pend_q;

  logic              take;
  logic [7:0]        nbytes;
  logic [OFF_W-1:0]  wr_base;
  int unsigned       filled;
  logic [SLOT_BYTES*8-1:0] buf_next;
  logic [OFF_W-1:0]        len_next;
  logic                    overflow;

  assign m_valid_o = pend_q;
  assign m_data_o  = buf_q;
  assign m_len_o   = 16'(len_q);
  assign s_tready_o = !pend_q;

  assign take = s_tvalid_i && s_tready_o;

  always_comb begin
    nbytes   = '0;
    for (int unsigned i = 0; i < KEEP_W; i++)
      if (s_tkeep_i[i]) nbytes++;
    wr_base  = len_q;
    buf_next = buf_q;
    filled   = 0;
    overflow = 1'b0;
    for (int unsigned i = 0; i < KEEP_W; i++) begin
      if (take && s_tkeep_i[i]) begin
        if (int'(wr_base) + filled >= SLOT_BYTES)
          overflow = 1'b1;
        else begin
          buf_next[8*(int'(wr_base) + filled) +: 8] = s_tdata_i[8*i +: 8];
          filled++;
        end
      end
    end
    len_next = take ? OFF_W'(int'(wr_base) + filled) : len_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      buf_q  <= '0;
      len_q  <= '0;
      pend_q <= 1'b0;
    end else begin
      if (pend_q && m_ready_i) begin
        pend_q <= 1'b0;
        len_q  <= '0;
        buf_q  <= '0;
      end

      if (take && !overflow) begin
        buf_q <= buf_next;
        len_q <= len_next;
        if (s_tlast_i && (filled != 0 || len_q != '0))
          pend_q <= 1'b1;
      end
    end
  end

endmodule : rivet_dll_tl_pack
