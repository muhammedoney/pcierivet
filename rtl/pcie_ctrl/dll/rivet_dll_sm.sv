// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Data Link Layer feature SM (Rivet subset of DLCMSM):
//   Inactive → Init (FC) → Active ↔ Replay
// Side status: dl_up = Active | Replay.

module rivet_dll_sm (
  input  logic pclk_i,
  input  logic rst_ni,

  input  rivet_pkg::rivet_mac_dll_sb_t mac_sb_i,
  input  logic                         fc_init_done_i,
  input  logic                         replay_req_i,   // NAK / timer
  input  logic                         replay_done_i,  // buffer drained this bout

  output rivet_pkg::rivet_dl_state_e   state_o,
  output logic                         dl_up_o,        // Active or Replay
  output logic                         tlp_tx_en_o,    // Active only
  output logic                         replay_en_o,    // Replay state
  output logic                         fc_en_o         // Init / Active / Replay
);

  import rivet_pkg::*;

  rivet_dl_state_e state_q, state_d;

  always_comb begin
    state_d = state_q;
    if (!mac_sb_i.accept_dll_tlp) begin
      state_d = RIVET_DL_INACTIVE;
    end else begin
      unique case (state_q)
        RIVET_DL_INACTIVE: state_d = RIVET_DL_INIT;
        RIVET_DL_INIT: begin
          if (fc_init_done_i) state_d = RIVET_DL_ACTIVE;
        end
        RIVET_DL_ACTIVE: begin
          if (replay_req_i) state_d = RIVET_DL_REPLAY;
        end
        RIVET_DL_REPLAY: begin
          if (replay_done_i) state_d = RIVET_DL_ACTIVE;
        end
        default: state_d = RIVET_DL_INACTIVE;
      endcase
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= RIVET_DL_INACTIVE;
    else state_q <= state_d;
  end

  assign state_o     = state_q;
  assign dl_up_o     = (state_q == RIVET_DL_ACTIVE) || (state_q == RIVET_DL_REPLAY);
  assign tlp_tx_en_o = (state_q == RIVET_DL_ACTIVE);
  assign replay_en_o = (state_q == RIVET_DL_REPLAY);
  assign fc_en_o     = (state_q == RIVET_DL_INIT) || (state_q == RIVET_DL_ACTIVE) ||
                       (state_q == RIVET_DL_REPLAY);

endmodule : rivet_dll_sm
