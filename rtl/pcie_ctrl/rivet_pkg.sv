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

  // PIPE Rate[2:0]. Link training always runs at 2.5 GT/s; 5.0 GT/s is only
  // reached through Recovery.Speed (Base 2.1 §4.2.6.2.4).
  typedef enum logic [2:0] {
    RIVET_PIPE_RATE_GEN1 = 3'd0,
    RIVET_PIPE_RATE_GEN2 = 3'd1
  } rivet_pipe_rate_e;

  // PIPE RxStatus[2:0] per lane.
  typedef enum logic [2:0] {
    RIVET_RXSTATUS_OK           = 3'b000,
    RIVET_RXSTATUS_SKP_ADDED    = 3'b001,
    RIVET_RXSTATUS_SKP_REMOVED  = 3'b010,
    RIVET_RXSTATUS_RX_DETECTED  = 3'b011,
    RIVET_RXSTATUS_DECODE_ERR   = 3'b100,
    RIVET_RXSTATUS_EB_OVERFLOW  = 3'b101,
    RIVET_RXSTATUS_EB_UNDERFLOW = 3'b110,
    RIVET_RXSTATUS_DISPARITY    = 3'b111
  } rivet_pipe_rxstatus_e;

  // 8b/10b control symbols the MAC places on txdata with txdatak asserted.
  localparam logic [7:0] RIVET_SYM_COM = 8'hBC; // K28.5 comma
  localparam logic [7:0] RIVET_SYM_SKP = 8'h1C; // K28.0
  localparam logic [7:0] RIVET_SYM_FTS = 8'h3C; // K28.1
  localparam logic [7:0] RIVET_SYM_IDL = 8'h7C; // K28.3 (EIOS filler)
  localparam logic [7:0] RIVET_SYM_PAD = 8'hF7; // K23.7

  // TS identifier symbols (Base 2.1 Tables 4-2/4-3). A polarity-inverted lane
  // delivers the bitwise complement, which is the documented inversion hint.
  localparam logic [7:0] RIVET_SYM_TS1_ID     = 8'h4A; // D10.2
  localparam logic [7:0] RIVET_SYM_TS2_ID     = 8'h45; // D5.2
  localparam logic [7:0] RIVET_SYM_TS1_ID_INV = 8'hB5; // D21.5
  localparam logic [7:0] RIVET_SYM_TS2_ID_INV = 8'hBA; // D26.5

  // TS Data Rate Identifier (Symbol 4). Bit 1 = 2.5 GT/s, bit 2 = 5.0 GT/s.
  // Supported rates are advertised even while the link trains at 2.5 GT/s.
  localparam logic [7:0] RIVET_TS_RATE_GEN1  = 8'h02;
  localparam logic [7:0] RIVET_TS_RATE_GEN2  = 8'h06;
  localparam int unsigned RIVET_TS_RATE_SPEED_CHANGE_BIT = 7;

  // TS Training Control (Symbol 5) bit positions.
  localparam int unsigned RIVET_TS_TC_HOT_RESET  = 0;
  localparam int unsigned RIVET_TS_TC_DISABLE    = 1;
  localparam int unsigned RIVET_TS_TC_LOOPBACK   = 2;
  localparam int unsigned RIVET_TS_TC_NO_SCRAM   = 3;
  localparam int unsigned RIVET_TS_TC_COMPL_RX   = 4;

  // Ordered-set lengths in symbols at 2.5/5.0 GT/s 8b/10b encoding.
  localparam int unsigned RIVET_TS_LEN      = 16;
  localparam int unsigned RIVET_SHORT_OS_LEN = 4; // SKP / FTS / EIOS at Gen1

  // Exit thresholds from the LTSSM sections (Base 2.1 §4.2.6.2 / §4.2.6.3).
  localparam int unsigned RIVET_N_TS_CONSEC     = 8;    // consecutive TS received
  localparam int unsigned RIVET_N_TS_NUM_CONSEC = 2;    // consecutive TS carrying numbers
  localparam int unsigned RIVET_N_IDLE_CONSEC   = 8;    // consecutive Idle symbol times
  localparam int unsigned RIVET_N_TS_AFTER_RX   = 16;   // TS sent after first TS received
  localparam int unsigned RIVET_N_IDLE_TX       = 16;   // Idle symbols sent after first RX
  localparam int unsigned RIVET_N_TS1_POLLING   = 1024; // TS1 sent before Polling.Config

  typedef enum logic [1:0] {
    RIVET_MAC_PKT_IDLE = 2'b00,
    RIVET_MAC_PKT_DLLP = 2'b01,
    RIVET_MAC_PKT_TLP  = 2'b10
  } rivet_mac_pkt_type_e;

  typedef enum logic [2:0] {
    RIVET_MAC_OS_NONE = 3'b000, // transmitter parked (electrical idle)
    RIVET_MAC_OS_TS1  = 3'b001,
    RIVET_MAC_OS_TS2  = 3'b010,
    RIVET_MAC_OS_SKP  = 3'b011,
    RIVET_MAC_OS_EIOS = 3'b100,
    RIVET_MAC_OS_FTS  = 3'b101,
    RIVET_MAC_OS_IDLE = 3'b110  // logical Idle data symbols
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

  // LTSSM timeouts in pclk cycles at the 2.5 GT/s training rate (125 MHz with a
  // 16-bit per-lane PIPE datapath). Simulation overrides these with far smaller
  // values; the numbers here are the silicon-intent defaults.
  localparam int unsigned RIVET_PCLK_GEN1_MHZ = 125;
  localparam int unsigned RIVET_T_12MS_CYC = 12 * RIVET_PCLK_GEN1_MHZ * 1000;
  localparam int unsigned RIVET_T_24MS_CYC = 24 * RIVET_PCLK_GEN1_MHZ * 1000;
  localparam int unsigned RIVET_T_48MS_CYC = 48 * RIVET_PCLK_GEN1_MHZ * 1000;
  localparam int unsigned RIVET_T_2MS_CYC  =  2 * RIVET_PCLK_GEN1_MHZ * 1000;

  // Width of the shared LTSSM timeout counter.
  localparam int unsigned RIVET_LTSSM_TIMER_W = 32;

  // Divide a silicon timeout down for simulation, never below one cycle.
  function automatic int unsigned rivet_scale_cyc(int unsigned cyc,
                                                  int unsigned scale);
    int unsigned s;
    int unsigned r;
    s = (scale == 0) ? 1 : scale;
    r = cyc / s;
    return (r == 0) ? 1 : r;
  endfunction

  // negotiated_width encoding in rivet_mac_dll_sb_t: raw lane count.
  function automatic logic [2:0] rivet_width_encode(int unsigned lanes);
    return lanes[2:0];
  endfunction

  // Default AXI-ST data width for Gen2 stub (widens with gen/lanes later).
  localparam int unsigned RIVET_AXI_DATA_WIDTH_DEFAULT = 64;
  // PG213 AXI-ST TKEEP marks valid Dwords, not bytes.
  localparam int unsigned RIVET_AXI_KEEP_WIDTH_DEFAULT = RIVET_AXI_DATA_WIDTH_DEFAULT / 32;

  // PIPE per-lane data width (bits). Gen2 default 16; US+ PHY pins up to 64.
  localparam int unsigned RIVET_PIPE_DATA_WIDTH_DEFAULT = 16;
  localparam int unsigned RIVET_PIPE_DATAK_WIDTH_PER_LANE = 2;
  localparam int unsigned RIVET_PIPE_RXSTATUS_WIDTH_PER_LANE = 3;

  // -------------------------------------------------------------------------
  // Gen2 scrambler LFSR (Base Spec §4.2.3): G(X)=X^16+X^5+X^4+X^3+1, seed FFFFh.
  // Advance eight serial steps; return {new_lfsr[15:0], pad[7:0]} (pad bit0 first).
  // -------------------------------------------------------------------------
  localparam logic [15:0] RIVET_LFSR_SEED = 16'hFFFF;

  function automatic logic [23:0] rivet_lfsr_step(input logic [15:0] lfsr_in);
    logic [15:0] lfsr;
    logic [7:0]  pad;
    lfsr = lfsr_in;
    for (int unsigned i = 0; i < 8; i++) begin
      pad[i] = lfsr[15];
      lfsr   = {lfsr[14:0], lfsr[15] ^ lfsr[4] ^ lfsr[3] ^ lfsr[2]};
    end
    return {lfsr, pad};
  endfunction

endpackage : rivet_pkg
