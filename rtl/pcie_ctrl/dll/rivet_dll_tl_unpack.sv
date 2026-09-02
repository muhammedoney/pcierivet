// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Unpack a whole TLP payload from rivet_dll_tlp_rx into TL AXI-ST-like beats.

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
  localparam int unsigned OFF_W  = (SLOT_BYTES <= 1) ? 1 : $clog2(SLOT_BYTES + 1);

  logic [SLOT_BYTES*8-1:0] buf_q;
  logic [15:0]             len_q;
  logic [11:0]             seq_q;
  logic [OFF_W-1:0]        off_q;
  logic                    busy_q;

  logic [15:0] remain;
  logic [7:0]  beat_bytes;

  assign s_ready_o  = !busy_q;
  assign m_tvalid_o = busy_q;
  assign m_seq_o    = seq_q;

  always_comb begin
    remain     = (len_q > 16'(off_q)) ? (len_q - 16'(off_q)) : 16'd0;
    beat_bytes = (remain >= 16'(KEEP_W)) ? 8'(KEEP_W) : remain[7:0];
    m_tdata_o  = '0;
    m_tkeep_o  = '0;
    for (int unsigned i = 0; i < KEEP_W; i++) begin
      if (i < beat_bytes) begin
        m_tdata_o[8*i +: 8] = buf_q[8*(off_q + OFF_W'(i)) +: 8];
        m_tkeep_o[i]        = 1'b1;
      end
    end
    m_tlast_o = busy_q && (remain <= 16'(KEEP_W));
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      buf_q  <= '0;
      len_q  <= '0;
      seq_q  <= '0;
      off_q  <= '0;
      busy_q <= 1'b0;
    end else if (!busy_q) begin
      if (s_valid_i && s_ready_o && (s_len_i != 16'd0)) begin
        buf_q  <= s_data_i;
        len_q  <= s_len_i;
        seq_q  <= s_seq_i;
        off_q  <= '0;
        busy_q <= 1'b1;
      end
    end else if (m_tvalid_o && m_tready_i) begin
      if (m_tlast_o) begin
        busy_q <= 1'b0;
        off_q  <= '0;
      end else begin
        off_q <= off_q + OFF_W'(beat_bytes);
      end
    end
  end

endmodule : rivet_dll_tl_unpack
