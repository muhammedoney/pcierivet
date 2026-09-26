// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Parse a 6-byte wire DLLP (bytes 5..6 = CRC-16) in a 64-bit MAC beat.

module rivet_dllp_rx (
  input  logic                              clk_i,
  input  logic                              rst_ni,

  input  rivet_pkg::rivet_dll_mac_rx_beat_t beat_i,
  input  logic                              beat_valid_i,
  output logic                              beat_ready_o,

  output rivet_pkg::rivet_dllp_dec_t        dec_o,
  output logic                              dec_valid_o,
  input  logic                              dec_ready_i
);

  import rivet_pkg::*;

  logic [47:0] body;
  logic [15:0] crc_rx;
  logic [15:0] crc_calc;
  logic        crc_ok;
  logic [7:0]  type_b;

  rivet_dll_crc16 u_crc (
    .body_i (body),
    .crc_o  (crc_calc)
  );

  assign body   = {16'h0, beat_i.data[31:0]};
  assign crc_rx = {beat_i.data[47:40], beat_i.data[39:32]};
  assign crc_ok = (crc_calc == crc_rx) && !beat_i.err;
  assign type_b = beat_i.data[7:0];

  rivet_dllp_dec_t dec_comb;
  always_comb begin
    dec_comb          = '0;
    dec_comb.crc_ok   = crc_ok;
    dec_comb.vc       = type_b[2:0];
    unique case (type_b)
      RIVET_DLLP_TYPE_ACK: begin
        dec_comb.kind    = RIVET_DLLP_KIND_ACK;
        dec_comb.ack_seq = {beat_i.data[27:24], beat_i.data[23:16]};
      end
      RIVET_DLLP_TYPE_NAK: begin
        dec_comb.kind    = RIVET_DLLP_KIND_NAK;
        dec_comb.ack_seq = {beat_i.data[27:24], beat_i.data[23:16]};
      end
      default: begin
        // FC family if high nibble matches known kinds.
        unique case (type_b[7:4])
          RIVET_DLLP_FC_INIT1_P,
          RIVET_DLLP_FC_INIT1_NP,
          RIVET_DLLP_FC_INIT1_CPL,
          RIVET_DLLP_FC_UPDATE_P,
          RIVET_DLLP_FC_UPDATE_NP,
          RIVET_DLLP_FC_UPDATE_CPL,
          RIVET_DLLP_FC_INIT2_P,
          RIVET_DLLP_FC_INIT2_NP,
          RIVET_DLLP_FC_INIT2_CPL: begin
            dec_comb.kind    = RIVET_DLLP_KIND_FC;
            dec_comb.fc_kind = rivet_dllp_fc_kind_e'(type_b[7:4]);
            dec_comb.hdr_fc  = beat_i.data[15:8];
            dec_comb.data_fc = {beat_i.data[27:24], beat_i.data[23:16]};
          end
          default: dec_comb.kind = RIVET_DLLP_KIND_NONE;
        endcase
      end
    endcase
  end

  logic            pending_q;
  rivet_dllp_dec_t dec_q;

  // Accept a new beat when we can store a decode, or when draining.
  assign beat_ready_o = !pending_q || (dec_valid_o && dec_ready_i);
  assign dec_valid_o  = pending_q;
  assign dec_o        = dec_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q <= 1'b0;
      dec_q     <= '0;
    end else begin
      if (pending_q && dec_ready_i) pending_q <= 1'b0;

      if (beat_valid_i && beat_ready_o &&
          beat_i.sop && beat_i.eop &&
          (beat_i.pkt_type == RIVET_MAC_PKT_DLLP)) begin
        dec_q     <= dec_comb;
        pending_q <= 1'b1;
      end
    end
  end

endmodule : rivet_dllp_rx
