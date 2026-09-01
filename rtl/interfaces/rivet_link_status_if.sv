// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Link status snapshot for UVM (cfg_ltssm_state / link_up).

interface rivet_link_status_if (
  input logic pclk,
  input logic preset_n
);
  logic       link_up;
  logic [5:0] cfg_ltssm_state;
endinterface : rivet_link_status_if
