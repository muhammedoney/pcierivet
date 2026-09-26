// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Build a 6-byte wire DLLP (4 info + CRC-16) in a 64-bit DLL↔MAC TX beat.

module rivet_dllp_tx (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  rivet_pkg::rivet_dllp_req_t    req_i,
  input  logic                          req_valid_i,
  output logic                          req_ready_o,

  output rivet_pkg::rivet_dll_mac_tx_beat_t beat_o,
  output logic                          beat_valid_o,
  input  logic                          beat_ready_i
);

  import rivet_pkg::*;

  logic [47:0] body;
  logic [15:0] crc;
  logic [63:0] dllp_bytes;

  rivet_dll_crc16 u_crc (
    .body_i (body),
    .crc_o  (crc)
  );

  always_comb begin
    body = '0;
    unique case (req_i.kind)
      RIVET_DLLP_KIND_ACK,
      RIVET_DLLP_KIND_NAK: begin
        body[7:0]   = (req_i.kind == RIVET_DLLP_KIND_ACK) ? RIVET_DLLP_TYPE_ACK
                                                           : RIVET_DLLP_TYPE_NAK;
        body[15:8]  = 8'h00;
        // AckNak_Seq_Num in info bytes 2..3 (CRC occupies wire bytes 4..5).
        body[23:16] = req_i.ack_seq[7:0];
        body[31:24] = {4'h0, req_i.ack_seq[11:8]};
      end
      RIVET_DLLP_KIND_FC: begin
        body[7:0]   = rivet_dllp_fc_type_byte(req_i.fc_kind, req_i.vc);
        body[15:8]  = req_i.hdr_fc;
        body[23:16] = req_i.data_fc[7:0];
        body[31:24] = {4'h0, req_i.data_fc[11:8]};
      end
      default: body = '0;
    endcase
  end

  assign dllp_bytes = {16'h0000, crc[15:8], crc[7:0], body[31:24],
                       body[23:16], body[15:8], body[7:0]};

  logic pending_q;
  rivet_dll_mac_tx_beat_t beat_q;

  assign req_ready_o  = !pending_q || (beat_valid_o && beat_ready_i);
  assign beat_valid_o = pending_q;
  assign beat_o       = beat_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q <= 1'b0;
      beat_q    <= '0;
    end else begin
      if (pending_q && beat_ready_i) pending_q <= 1'b0;

      if (req_valid_i && req_ready_o && (req_i.kind != RIVET_DLLP_KIND_NONE)) begin
        beat_q.data     <= dllp_bytes;
        beat_q.keep     <= 8'hFF;
        beat_q.sop      <= 1'b1;
        beat_q.eop      <= 1'b1;
        beat_q.pkt_type <= RIVET_MAC_PKT_DLLP;
        pending_q       <= 1'b1;
      end
    end
  end

endmodule : rivet_dllp_tx
