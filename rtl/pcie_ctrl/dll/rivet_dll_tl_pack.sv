// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack TL->DLL beats into a 64-bit word RAM. A 64-bit beat writes one
// word. A 128-bit beat writes two. The consumer reads one beat per cycle
// (registered): 64 bits, or a 128-bit pair for the wide transmitter.

module rivet_dll_tl_pack #(
  parameter int unsigned DATA_W     = rivet_pkg::RIVET_TL_DLL_DATA_W,
  parameter int unsigned SLOT_BYTES = 160
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [DATA_W-1:0]   s_tdata_i,
  input  logic [DATA_W/8-1:0] s_tkeep_i,
  input  logic                s_tlast_i,
  input  logic                s_tvalid_i,
  output logic                s_tready_o,

  output logic                m_valid_o,
  input  logic                m_ready_i,
  output logic [15:0]         m_len_o,

  input  logic [15:0]         rd_idx_i,
  output logic [DATA_W-1:0]   rd_data_o
);

  localparam int unsigned KEEP_W     = DATA_W / 8;
  localparam int unsigned WORD_BYTES = 8;
  localparam int unsigned SLOTS      = SLOT_BYTES / WORD_BYTES;
  localparam int unsigned SLOT_W     = (SLOTS <= 1) ? 1 : $clog2(SLOTS);
  localparam int unsigned OFF_W      = (SLOT_BYTES <= 1) ? 1 : $clog2(SLOT_BYTES + 1);

`ifndef SYNTHESIS
  initial begin
    if ((SLOT_BYTES % WORD_BYTES) != 0)
      $error("rivet_dll_tl_pack SLOT_BYTES (%0d) must be a multiple of %0d",
             SLOT_BYTES, WORD_BYTES);
    if ((KEEP_W != 8) && (KEEP_W != 16))
      $error("rivet_dll_tl_pack beat must be 8 or 16 bytes");
  end
`endif

  // Two banks so the next TLP can be collected while the current one
  // is read out a word at a time.
  localparam int unsigned RAM_WORDS = 2 * (1 << SLOT_W);
  (* ram_style = "block" *) logic [63:0] word_q [0:RAM_WORDS-1];
  logic [63:0]      rd_lo_q, rd_hi_q;
  logic             wr_bank_q, rd_bank_q, rd_bank_rd;
  logic [1:0]       full_q;
  logic [OFF_W-1:0] len_q [2];

  logic                    take;
  logic [7:0]              nbytes;
  logic [DATA_W-1:0]       beat_packed;
  logic [OFF_W-1:0]        len_next;
  logic [SLOT_W-1:0]       wr_slot;
  logic                    overflow;

  assign m_valid_o  = full_q[rd_bank_q];
  assign m_len_o    = 16'(len_q[rd_bank_q]);
  assign s_tready_o = !full_q[wr_bank_q];
  assign take       = s_tvalid_i && s_tready_o;

  generate
    if (DATA_W == 128) begin : g_rd128
      assign rd_data_o = {rd_hi_q, rd_lo_q};
    end else begin : g_rd64
      assign rd_data_o = rd_lo_q;
    end
  endgenerate

  logic [4:0] keep_pref [0:KEEP_W];

  always_comb begin
    keep_pref[0] = 5'd0;
    for (int unsigned i = 0; i < KEEP_W; i++)
      keep_pref[i + 1] = keep_pref[i] + 5'(s_tkeep_i[i]);
    nbytes      = 8'(keep_pref[KEEP_W]);
    beat_packed = '0;
    for (int unsigned b = 0; b < KEEP_W; b++) begin
      for (int unsigned i = 0; i < KEEP_W; i++) begin
        if (s_tkeep_i[i] && (keep_pref[i] == 5'(b)))
          beat_packed[8*b +: 8] = s_tdata_i[8*i +: 8];
      end
    end
    // Words stay 8 bytes wide so a short last beat and a 16-byte beat share
    // one address map.
    wr_slot  = SLOT_W'(len_q[wr_bank_q] >> 3);
    overflow = take && ((int'(len_q[wr_bank_q]) + int'(nbytes)) > SLOT_BYTES);
    len_next = (take && !overflow) ? OFF_W'(int'(len_q[wr_bank_q]) + int'(nbytes))
                                   : len_q[wr_bank_q];
  end

  logic [127:0] beat_w;
  always_comb begin
    beat_w = '0;
    beat_w[DATA_W-1:0] = beat_packed;
  end

  always_ff @(posedge clk_i) begin
    if (take && !overflow && (nbytes != 8'd0))
      word_q[{wr_bank_q, wr_slot}] <= beat_w[63:0];
    if (take && !overflow && (nbytes > 8'd8))
      word_q[{wr_bank_q, SLOT_W'(wr_slot + 1'b1)}] <= beat_w[127:64];
  end

  // Synchronous read-port reset. Versal rejects an async BRAM reset
  // that is not driven by a register (REQP-2042).
  // The bank pops on m_ready. The read issued that cycle must use the
  // bank that becomes current, or the next frame's first word is the
  // header of the frame that just finished.
  assign rd_bank_rd = (full_q[rd_bank_q] && m_ready_i) ? ~rd_bank_q : rd_bank_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rd_lo_q <= '0;
      rd_hi_q <= '0;
    end else begin
      rd_lo_q <= word_q[{rd_bank_rd, rd_idx_i[SLOT_W-1:0]}];
      rd_hi_q <= word_q[{rd_bank_rd, SLOT_W'(rd_idx_i[SLOT_W-1:0] + 1'b1)}];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_bank_q <= 1'b0;
      rd_bank_q <= 1'b0;
      full_q    <= '0;
      len_q[0]  <= '0;
      len_q[1]  <= '0;
    end else begin
      if (full_q[rd_bank_q] && m_ready_i) begin
        full_q[rd_bank_q] <= 1'b0;
        len_q[rd_bank_q]  <= '0;
        rd_bank_q         <= ~rd_bank_q;
      end
      if (take && !overflow) begin
`ifndef SYNTHESIS
        if (!s_tlast_i && (nbytes != 8'(KEEP_W)))
          $error("rivet_dll_tl_pack: non-last beat has %0d bytes (expected %0d)",
                 nbytes, KEEP_W);
`endif
        len_q[wr_bank_q] <= len_next;
        if (s_tlast_i && ((nbytes != 8'd0) || (len_q[wr_bank_q] != '0))) begin
          full_q[wr_bank_q] <= 1'b1;
          wr_bank_q         <= ~wr_bank_q;
        end
      end
    end
  end

endmodule : rivet_dll_tl_pack
