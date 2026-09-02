// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Data Link Control and Management SM (Rivet Gen2 VC0 subset):
//   DL_Inactive → DL_Init (FC) → DL_Active
// DL_Feature omitted. Replay is a busy flag under DL_Active (not a DLCMSM state).
// Side status: DL_Up = Active; DL_Down = !DL_Up.

module rivet_dll_sm (
  input  logic pclk_i,
  input  logic rst_ni,

  input  rivet_pkg::rivet_mac_dll_sb_t mac_sb_i,
  input  logic                         fc_init_done_i,
  input  logic                         replay_req_i,   // NAK / timer
  input  logic                         replay_done_i,  // buffer drained this bout

  output rivet_pkg::rivet_dl_state_e   state_o,
  output logic                         dl_up_o,        // Active (spec DL_Up)
  output logic                         tlp_tx_en_o,    // Active and not replaying
  output logic                         replay_en_o,    // replay busy under Active
  output logic                         fc_en_o         // Init or Active
);

  import rivet_pkg::*;

  rivet_dl_state_e state_q, state_d;
  logic            replay_q, replay_d;

  always_comb begin
    state_d  = state_q;
    replay_d = replay_q;

    if (!mac_sb_i.accept_dll_tlp) begin
      state_d  = RIVET_DL_INACTIVE;
      replay_d = 1'b0;
    end else begin
      unique case (state_q)
        RIVET_DL_INACTIVE: begin
          state_d  = RIVET_DL_INIT;
          replay_d = 1'b0;
        end
        RIVET_DL_INIT: begin
          replay_d = 1'b0;
          if (fc_init_done_i) state_d = RIVET_DL_ACTIVE;
        end
        RIVET_DL_ACTIVE: begin
          if (replay_done_i) replay_d = 1'b0;
          else if (replay_req_i) replay_d = 1'b1;
        end
        default: begin
          state_d  = RIVET_DL_INACTIVE;
          replay_d = 1'b0;
        end
      endcase
    end
  end

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= RIVET_DL_INACTIVE;
      replay_q <= 1'b0;
    end else begin
      state_q  <= state_d;
      replay_q <= replay_d;
    end
  end

  assign state_o     = state_q;
  assign dl_up_o     = (state_q == RIVET_DL_ACTIVE);
  assign replay_en_o = (state_q == RIVET_DL_ACTIVE) && replay_q;
  assign tlp_tx_en_o = (state_q == RIVET_DL_ACTIVE) && !replay_q;
  assign fc_en_o     = (state_q == RIVET_DL_INIT) || (state_q == RIVET_DL_ACTIVE);

endmodule : rivet_dll_sm
