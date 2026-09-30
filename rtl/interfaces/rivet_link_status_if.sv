// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Link status snapshot for UVM (cfg_ltssm_state / link_up / PIPE rate).

interface rivet_link_status_if (
  input logic pclk,
  input logic preset_n
);
  logic       link_up;
  logic [5:0] cfg_ltssm_state;
  logic [2:0] pipe_rate;
  logic [2:0] negotiated_width;
  // TB-driven ASPM requests; rivet_tb_top forces them onto the MAC (default 0).
  logic       aspm_l0s_req;
  logic       aspm_l1_req;
endinterface : rivet_link_status_if
