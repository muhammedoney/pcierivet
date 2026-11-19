// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Unpack a whole TLP payload from rivet_dll_tlp_rx into TL AXI-ST-like beats.
// Remaining byte count, keep mask, and tlast are registered so buf_q shift CE
// and downstream TL logic see flip-flop outputs rather than a 16-bit subtractor.

module rivet_dll_tl_unpack #(
  parameter int unsigned DATA_W     = rivet_pkg::RIVET_TL_DLL_DATA_W,
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic                           s_valid_i,
  output logic                           s_ready_o,
  input  logic [SLOT_BYTES*8-1:0]        s_data_i,
  input  logic [15:0]                    s_len_i,
  input  logic [11:0]                    s_seq_i,

  output logic [DATA_W-1:0]              m_tdata_o,
  output logic [DATA_W/8-1:0]            m_tkeep_o,
  output logic                           m_tlast_o,
  output logic                           m_tvalid_o,
  input  logic                           m_tready_i,
  output logic [11:0]                    m_seq_o
);

  localparam int unsigned KEEP_W = DATA_W / 8;

  function automatic logic [KEEP_W-1:0] len_to_keep(input logic [8:0] rem);
    logic [KEEP_W-1:0] k;
    k = '0;
    for (int unsigned i = 0; i < KEEP_W; i++) begin
      if (9'(i) < rem) k[i] = 1'b1;
    end
    return k;
  endfunction

  logic [SLOT_BYTES*8-1:0] buf_q;
  logic [8:0]              rem_q;
  logic [KEEP_W-1:0]       keep_q;
  logic                    last_q;
  logic [11:0]             seq_q;
  logic                    busy_q;

  assign s_ready_o  = !busy_q;
  assign m_tvalid_o = busy_q;
  assign m_seq_o    = seq_q;
  assign m_tkeep_o  = busy_q ? keep_q : '0;
  assign m_tlast_o  = busy_q && last_q;

  always_comb begin
    m_tdata_o = '0;
    for (int unsigned i = 0; i < KEEP_W; i++) begin
      if (busy_q && keep_q[i])
        m_tdata_o[8*i +: 8] = buf_q[8*i +: 8];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      buf_q  <= '0;
      rem_q  <= '0;
      keep_q <= '0;
      last_q <= 1'b0;
      seq_q  <= '0;
      busy_q <= 1'b0;
    end else if (!busy_q) begin
      if (s_valid_i && s_ready_o && (s_len_i != 16'd0)) begin
        automatic logic [8:0] slen = s_len_i[8:0];
        buf_q  <= s_data_i;
        rem_q  <= slen;
        keep_q <= len_to_keep(slen);
        last_q <= (slen <= 9'(KEEP_W));
        seq_q  <= s_seq_i;
        busy_q <= 1'b1;
      end
    end else if (m_tvalid_o && m_tready_i) begin
      if (last_q) begin
        busy_q <= 1'b0;
        rem_q  <= '0;
        keep_q <= '0;
        last_q <= 1'b0;
      end else begin
        automatic logic [8:0] nrem = rem_q - 9'(KEEP_W);
        rem_q  <= nrem;
        keep_q <= len_to_keep(nrem);
        last_q <= (nrem <= 9'(KEEP_W));
        buf_q  <= buf_q >> DATA_W;
      end
    end
  end

endmodule : rivet_dll_tl_unpack
