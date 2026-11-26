// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack TL->DLL beats into a 64-bit word RAM. A 64-bit beat writes one
// word. A 128-bit beat writes two. The consumer reads one beat per cycle
// (registered): 64 bits, or a 128-bit pair for the wide transmitter.
// STREAM presents each beat as it arrives. The word RAM is the
// store-and-forward path, used when STREAM is 0.

module rivet_dll_tl_pack #(
  parameter int unsigned DATA_W     = rivet_pkg::RIVET_TL_DLL_DATA_W,
  parameter int unsigned SLOT_BYTES = 160,
  parameter bit          STREAM     = 1'b0
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
  output logic                m_last_o,

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
    if ((KEEP_W != 8) && (KEEP_W != 16) && (KEEP_W != 32))
      $error("rivet_dll_tl_pack beat must be 8, 16, or 32 bytes");
  end
`endif

  logic [7:0]        nbytes;
  logic [DATA_W-1:0] beat_packed;

  // All TL producers emit contiguous low-byte tkeep masks; compute the
  // byte count with a shallow popcount tree and pass data straight through
  // (zeroing unused high bytes).
  always_comb begin
    logic [31:0] k32;
    logic [2:0]  c4 [8];
    logic [3:0]  c8 [4];
    logic [4:0]  c16 [2];
    logic [5:0]  cnt;
    k32 = '0;
    k32[KEEP_W-1:0] = s_tkeep_i;
    for (int unsigned i = 0; i < 8; i++)
      c4[i] = {2'd0, k32[4*i]} + {2'd0, k32[4*i + 1]} +
              {2'd0, k32[4*i + 2]} + {2'd0, k32[4*i + 3]};
    for (int unsigned i = 0; i < 4; i++)
      c8[i] = {1'b0, c4[2*i]} + {1'b0, c4[2*i + 1]};
    c16[0] = {1'b0, c8[0]} + {1'b0, c8[1]};
    c16[1] = {1'b0, c8[2]} + {1'b0, c8[3]};
    cnt    = {1'b0, c16[0]} + {1'b0, c16[1]};
    nbytes = {2'd0, cnt};
    beat_packed = '0;
    for (int unsigned b = 0; b < KEEP_W; b++) begin
      if (s_tkeep_i[b])
        beat_packed[8*b +: 8] = s_tdata_i[8*b +: 8];
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni && s_tvalid_i && ((s_tkeep_i & (s_tkeep_i + KEEP_W'(1))) != '0))
      $error("rivet_dll_tl_pack: non-contiguous s_tkeep_i 0x%0h", s_tkeep_i);
  end
`endif

  generate
    if (STREAM) begin : g_stream
      // One beat deep. Empty, the beat is the live input, so the framer
      // sees it on the cycle the producer is accepted. Ready drops only
      // while that beat is parked and the framer has not taken it.
      logic              held_q;
      logic [DATA_W-1:0] data_q;
      logic [15:0]       len_q;
      logic              last_q;
      logic              live_v;
      logic              s_fire;
      logic              m_fire;

      assign live_v     = s_tvalid_i && (nbytes != 8'd0);
      assign s_tready_o = !held_q || m_ready_i;
      assign m_valid_o  = held_q || live_v;
      assign m_len_o    = held_q ? len_q : 16'(nbytes);
      assign m_last_o   = held_q ? last_q : s_tlast_i;
      assign rd_data_o  = held_q ? data_q : beat_packed;
      assign s_fire     = live_v && s_tready_o;
      assign m_fire     = m_valid_o && m_ready_i;

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          held_q <= 1'b0;
          data_q <= '0;
          len_q  <= '0;
          last_q <= 1'b0;
        end else if (s_fire && (!m_fire || held_q)) begin
`ifndef SYNTHESIS
          if (!s_tlast_i && (nbytes != 8'(KEEP_W)))
            $error("rivet_dll_tl_pack: non-last beat has %0d bytes (expected %0d)",
                   nbytes, KEEP_W);
`endif
          held_q <= 1'b1;
          data_q <= beat_packed;
          len_q  <= 16'(nbytes);
          last_q <= s_tlast_i;
        end else if (m_fire && held_q) begin
          held_q <= 1'b0;
        end
      end
    end else begin : g_store
      // Two banks so the next TLP can be collected while the current one
      // is read out a word at a time.
      localparam int unsigned RAM_WORDS = 2 * (1 << SLOT_W);
      (* ram_style = "block" *) logic [63:0] word_q [0:RAM_WORDS-1];
      logic [63:0]      rd_lo_q, rd_hi_q;
      logic             wr_bank_q, rd_bank_q, rd_bank_rd;
      logic [1:0]       full_q;
      logic [OFF_W-1:0] len_q [2];
      logic             take;
      logic [OFF_W-1:0] len_next;
      logic [SLOT_W-1:0] wr_slot;
      logic             overflow;
      logic [127:0]     beat_w;

      assign m_valid_o  = full_q[rd_bank_q];
      assign m_len_o    = 16'(len_q[rd_bank_q]);
      assign m_last_o   = m_valid_o;
      assign s_tready_o = !full_q[wr_bank_q];
      assign take       = s_tvalid_i && s_tready_o;
      assign rd_bank_rd = (full_q[rd_bank_q] && m_ready_i) ? ~rd_bank_q : rd_bank_q;

      if (DATA_W == 128) begin : g_rd128
        assign rd_data_o = {rd_hi_q, rd_lo_q};
      end else begin : g_rd64
        assign rd_data_o = rd_lo_q;
      end

      always_comb begin
        // Words stay 8 bytes wide so a short last beat and a 16-byte beat
        // share one address map.
        wr_slot  = SLOT_W'(len_q[wr_bank_q] >> 3);
        overflow = take && ((int'(len_q[wr_bank_q]) + int'(nbytes)) > SLOT_BYTES);
        len_next = (take && !overflow) ? OFF_W'(int'(len_q[wr_bank_q]) + int'(nbytes))
                                       : len_q[wr_bank_q];
        beat_w   = '0;
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
    end
  endgenerate

endmodule : rivet_dll_tl_pack
