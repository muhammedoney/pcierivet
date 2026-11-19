// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack TL->DLL AXI-ST-like beats into one whole TLP payload for rivet_dll_tlp_tx.
// Non-last beats are full 8-byte words, so each beat compacts its 8 bytes locally
// and writes one aligned 64-bit slot instead of a 160x8 byte-address mux.

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
  localparam int unsigned SLOTS  = SLOT_BYTES / KEEP_W;
  localparam int unsigned SLOT_W = (SLOTS <= 1) ? 1 : $clog2(SLOTS);
  localparam int unsigned OFF_W  = (SLOT_BYTES <= 1) ? 1 : $clog2(SLOT_BYTES + 1);

`ifndef SYNTHESIS
  initial begin
    if ((SLOT_BYTES % KEEP_W) != 0)
      $error("rivet_dll_tl_pack SLOT_BYTES (%0d) must be a multiple of %0d",
             SLOT_BYTES, KEEP_W);
  end
`endif

  logic [SLOT_BYTES*8-1:0] buf_q;
  logic [OFF_W-1:0]        len_q;
  logic                    pend_q;

  logic                    take;
  logic [7:0]              nbytes;
  logic [DATA_W-1:0]       beat_packed;
  logic [SLOT_BYTES*8-1:0] buf_next;
  logic [OFF_W-1:0]        len_next;
  logic [SLOT_W-1:0]       wr_slot;
  logic                    overflow;

  assign m_valid_o  = pend_q;
  assign m_data_o   = buf_q;
  assign m_len_o    = 16'(len_q);
  assign s_tready_o = !pend_q;

  assign take = s_tvalid_i && s_tready_o;

  logic [3:0] keep_pref [0:KEEP_W];

  always_comb begin
    keep_pref[0] = 4'd0;
    for (int unsigned i = 0; i < KEEP_W; i++)
      keep_pref[i + 1] = keep_pref[i] + 4'(s_tkeep_i[i]);
    nbytes      = 8'(keep_pref[KEEP_W]);
    beat_packed = '0;
    for (int unsigned b = 0; b < KEEP_W; b++) begin
      for (int unsigned i = 0; i < KEEP_W; i++) begin
        if (s_tkeep_i[i] && (keep_pref[i] == 4'(b)))
          beat_packed[8*b +: 8] = s_tdata_i[8*i +: 8];
      end
    end

    buf_next = buf_q;
    wr_slot  = SLOT_W'(len_q >> $clog2(KEEP_W));
    overflow = take && ((int'(len_q) + int'(nbytes)) > SLOT_BYTES);
    if (take && !overflow && (nbytes != 8'd0)) begin
      for (int unsigned s = 0; s < SLOTS; s++) begin
        if (wr_slot == SLOT_W'(s))
          buf_next[DATA_W*s +: DATA_W] = beat_packed;
      end
    end
    len_next = (take && !overflow) ? OFF_W'(int'(len_q) + int'(nbytes)) : len_q;
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
`ifndef SYNTHESIS
        if (!s_tlast_i && (nbytes != 8'(KEEP_W)))
          $error("rivet_dll_tl_pack: non-last beat has %0d bytes (expected %0d)",
                 nbytes, KEEP_W);
`endif
        buf_q <= buf_next;
        len_q <= len_next;
        if (s_tlast_i && ((nbytes != 8'd0) || (len_q != '0)))
          pend_q <= 1'b1;
      end
    end
  end

endmodule : rivet_dll_tl_pack
