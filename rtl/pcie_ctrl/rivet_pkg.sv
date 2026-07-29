// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Common parameters and types for Rivet soft PCIe controller.

package rivet_pkg;

  typedef enum int unsigned {
    RIVET_MODE_EP  = 0, // Endpoint
    RIVET_MODE_RC  = 1, // Root Complex / Root Port
    RIVET_MODE_USP = 2, // Switch Upstream Port
    RIVET_MODE_DSP = 3  // Switch Downstream Port
  } rivet_mode_e;

  typedef enum int unsigned {
    RIVET_GEN2 = 2,
    RIVET_GEN4 = 4,
    RIVET_GEN5 = 5
  } rivet_gen_e;

  // PG213 cfg_ltssm_state[5:0] encodings (locked — see docs/mac.md).
  typedef enum logic [5:0] {
    RIVET_LTSSM_DETECT_QUIET              = 6'h00,
    RIVET_LTSSM_DETECT_ACTIVE             = 6'h01,
    RIVET_LTSSM_POLLING_ACTIVE            = 6'h02,
    RIVET_LTSSM_POLLING_COMPLIANCE        = 6'h03,
    RIVET_LTSSM_POLLING_CONFIGURATION     = 6'h04,
    RIVET_LTSSM_CFG_LINKWIDTH_START       = 6'h05,
    RIVET_LTSSM_CFG_LINKWIDTH_ACCEPT      = 6'h06,
    RIVET_LTSSM_CFG_LANENUM_ACCEPT        = 6'h07,
    RIVET_LTSSM_CFG_LANENUM_WAIT          = 6'h08,
    RIVET_LTSSM_CFG_COMPLETE              = 6'h09,
    RIVET_LTSSM_CFG_IDLE                  = 6'h0A,
    RIVET_LTSSM_RECOVERY_RCVRLOCK         = 6'h0B,
    RIVET_LTSSM_RECOVERY_SPEED            = 6'h0C,
    RIVET_LTSSM_RECOVERY_RCVRCFG          = 6'h0D,
    RIVET_LTSSM_RECOVERY_IDLE             = 6'h0E,
    RIVET_LTSSM_L0                        = 6'h10,
    RIVET_LTSSM_L1_ENTRY                  = 6'h17,
    RIVET_LTSSM_L1_IDLE                   = 6'h18,
    RIVET_LTSSM_DISABLED                  = 6'h20,
    RIVET_LTSSM_LOOPBACK_ENTRY            = 6'h21,
    RIVET_LTSSM_LOOPBACK_ACTIVE           = 6'h22,
    RIVET_LTSSM_LOOPBACK_EXIT             = 6'h23,
    RIVET_LTSSM_LOOPBACK_EXIT_TIMEOUT     = 6'h24,
    RIVET_LTSSM_HOT_RESET                 = 6'h27,
    RIVET_LTSSM_RCVRY_EQ0                 = 6'h28,
    RIVET_LTSSM_RCVRY_EQ1                 = 6'h29,
    RIVET_LTSSM_RCVRY_EQ2                 = 6'h2A,
    RIVET_LTSSM_RCVRY_EQ3                 = 6'h2B
  } rivet_ltssm_state_e;

  // PIPE PowerDown[1:0] (PCIe) — docs/pipe-notes.md
  typedef enum logic [1:0] {
    RIVET_PIPE_P0  = 2'b00,
    RIVET_PIPE_P0S = 2'b01,
    RIVET_PIPE_P1  = 2'b10,
    RIVET_PIPE_P2  = 2'b11
  } rivet_pipe_powerdown_e;

  typedef enum logic [1:0] {
    RIVET_MAC_PKT_IDLE = 2'b00,
    RIVET_MAC_PKT_DLLP = 2'b01,
    RIVET_MAC_PKT_TLP  = 2'b10
  } rivet_mac_pkt_type_e;

  typedef enum logic [2:0] {
    RIVET_MAC_OS_NONE = 3'b000,
    RIVET_MAC_OS_TS1  = 3'b001,
    RIVET_MAC_OS_TS2  = 3'b010,
    RIVET_MAC_OS_SKP  = 3'b011,
    RIVET_MAC_OS_EIOS = 3'b100,
    RIVET_MAC_OS_FTS  = 3'b101
  } rivet_mac_os_type_e;

  // DLL -> MAC TX payload beat (AXI-ST-like; not user AXI-ST).
  typedef struct packed {
    logic [63:0]          data;
    logic [7:0]           keep;
    logic                 sop;
    logic                 eop;
    rivet_mac_pkt_type_e  pkt_type;
  } rivet_dll_mac_tx_beat_t;

  // MAC -> DLL RX payload beat.
  typedef struct packed {
    logic [63:0]          data;
    logic [7:0]           keep;
    logic                 sop;
    logic                 eop;
    logic                 err;
    rivet_mac_pkt_type_e  pkt_type;
  } rivet_dll_mac_rx_beat_t;

  // MAC/LTSSM -> DLL control sideband (internal; not config space).
  typedef struct packed {
    logic                 link_up;
    rivet_ltssm_state_e   ltssm_state;
    logic [2:0]           negotiated_width; // 1/2/4 encoded later
    logic [1:0]           negotiated_speed; // Gen encoding
    logic                 accept_dll_tlp;   // typically L0 only
    logic                 replay_freeze;
  } rivet_mac_dll_sb_t;

  // DLL -> MAC/LTSSM control sideband.
  typedef struct packed {
    logic                 replay_timer_expired;
    logic                 nak_storm;
    logic                 tx_idle_req;
  } rivet_dll_mac_sb_t;

  function automatic bit rivet_lanes_legal(int unsigned lanes);
    return (lanes == 1) || (lanes == 2) || (lanes == 4);
  endfunction

  // Default AXI-ST data width for Gen2 stub (widens with gen/lanes later).
  localparam int unsigned RIVET_AXI_DATA_WIDTH_DEFAULT = 64;
  // PG213 AXI-ST TKEEP marks valid Dwords, not bytes.
  localparam int unsigned RIVET_AXI_KEEP_WIDTH_DEFAULT = RIVET_AXI_DATA_WIDTH_DEFAULT / 32;

  // PIPE per-lane data width (bits). Gen2 default 16; US+ PHY pins up to 64.
  localparam int unsigned RIVET_PIPE_DATA_WIDTH_DEFAULT = 16;
  localparam int unsigned RIVET_PIPE_DATAK_WIDTH_PER_LANE = 2;
  localparam int unsigned RIVET_PIPE_RXSTATUS_WIDTH_PER_LANE = 3;

endpackage : rivet_pkg
