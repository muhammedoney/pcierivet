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
    RIVET_GEN1 = 1,
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
  // Packet framing tokens (Base 2.1 §4.2.2) — Logical Idle plane before 8b/10b.
  localparam logic [7:0] RIVET_SYM_SDP = 8'h5C; // K28.2 Start DLLP
  localparam logic [7:0] RIVET_SYM_STP = 8'hFB; // K27.7 Start TLP
  localparam logic [7:0] RIVET_SYM_END = 8'hFD; // K29.7 End good packet
  localparam logic [7:0] RIVET_SYM_EDB = 8'hFE; // K30.7 End bad / nullified

  // Wire DLLP: SDP + 6 bytes + END. Bytes 1..4 = info, bytes 5..6 = CRC-16.
  // The DLL↔MAC beat stays 64-bit (bytes 7..8 unused).
  localparam int unsigned RIVET_DLLP_INFO_BYTES  = 4;
  localparam int unsigned RIVET_DLLP_WIRE_BYTES  = 6;
  localparam int unsigned RIVET_DLLP_FRAMED_LEN  = 8;

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
  localparam int unsigned RIVET_SHORT_OS_LEN = 4; // SKP / FTS / EIOS at Gen1 rate
  // Gen1 and Gen2 (8b/10b) both require TX SKP OS in L0 for clock compensation.
  // Base: schedule between 1180 and 1538 Symbol Times (never mid-packet).
  localparam int unsigned RIVET_SKP_MIN_SYM_TIMES = 1180;
  localparam int unsigned RIVET_SKP_MAX_SYM_TIMES = 1538;
  localparam int unsigned RIVET_SKP_INTERVAL_SYM  = 1400; // mid-range pick

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
    logic                 dl_up;                 // Active or Replay
    logic                 replay_timer_expired;
    logic                 nak_storm;
    logic                 tx_idle_req;
  } rivet_dll_mac_sb_t;

  // Data Link Control and Management SM (Gen2 VC0 subset; no DL_Feature).
  // Replay is not a DLCMSM state — it is a busy flag under DL_Active.
  typedef enum logic [1:0] {
    RIVET_DL_INACTIVE = 2'd0,
    RIVET_DL_INIT     = 2'd1,
    RIVET_DL_ACTIVE   = 2'd2
  } rivet_dl_state_e;

  // -------------------------------------------------------------------------
  // DLLP / flow-control types (Base 2.1 §3.4). On the wire a DLLP is 32 bits of
  // information plus CRC-16 (6 symbols between SDP and END). The DLL↔MAC beat
  // stays 64-bit; do not shrink it to LANES*16.
  // -------------------------------------------------------------------------
  localparam int unsigned RIVET_DLLP_BYTES = 8;
  localparam int unsigned RIVET_DLL_DATA_W_DEFAULT = 64; // one DLLP / beat today

  // High nibble of FC DLLP Type field (VC is OR'd into [2:0]).
  typedef enum logic [3:0] {
    RIVET_DLLP_FC_INIT1_P  = 4'h4,
    RIVET_DLLP_FC_INIT1_NP = 4'h5,
    RIVET_DLLP_FC_INIT1_CPL = 4'h6,
    RIVET_DLLP_FC_UPDATE_P  = 4'h8,
    RIVET_DLLP_FC_UPDATE_NP = 4'h9,
    RIVET_DLLP_FC_UPDATE_CPL = 4'hA,
    RIVET_DLLP_FC_INIT2_P  = 4'hC,
    RIVET_DLLP_FC_INIT2_NP = 4'hD,
    RIVET_DLLP_FC_INIT2_CPL = 4'hE
  } rivet_dllp_fc_kind_e;

  localparam logic [7:0] RIVET_DLLP_TYPE_ACK = 8'h00;
  localparam logic [7:0] RIVET_DLLP_TYPE_NAK = 8'h10;

  typedef enum logic [2:0] {
    RIVET_DLLP_KIND_NONE = 3'd0,
    RIVET_DLLP_KIND_ACK  = 3'd1,
    RIVET_DLLP_KIND_NAK  = 3'd2,
    RIVET_DLLP_KIND_FC   = 3'd3
  } rivet_dllp_kind_e;

  // One VC's six credit counters (+ infinite flags). Hdr=8b, Data=12b fields.
  typedef struct packed {
    logic [7:0]  ph;
    logic [11:0] pd;
    logic [7:0]  nph;
    logic [11:0] npd;
    logic [7:0]  cplh;
    logic [11:0] cpld;
    logic        ph_inf;
    logic        pd_inf;
    logic        nph_inf;
    logic        npd_inf;
    logic        cplh_inf;
    logic        cpld_inf;
  } rivet_fc_credit_set_t;

  // TL -> DLL: advertised CA, free pulses, and TX credit consume (D3).
  typedef struct packed {
    rivet_fc_credit_set_t ca;
    logic                 ph_freed;
    logic                 pd_freed;
    logic                 nph_freed;
    logic                 npd_freed;
    logic                 cplh_freed;
    logic                 cpld_freed;
    logic                 consume_ph;
    logic                 consume_pd;
    logic                 consume_nph;
    logic                 consume_npd;
    logic                 consume_cplh;
    logic                 consume_cpld;
    logic [7:0]           consume_ph_amt;
    logic [11:0]          consume_pd_amt;
    logic [7:0]           consume_nph_amt;
    logic [11:0]          consume_npd_amt;
    logic [7:0]           consume_cplh_amt;
    logic [11:0]          consume_cpld_amt;
  } rivet_tl_dll_fc_sb_t;

  // DLL -> TL: peer CL, consumed, available, gate status + DL feature status.
  typedef struct packed {
    rivet_fc_credit_set_t cl;
    rivet_fc_credit_set_t cc;
    rivet_fc_credit_set_t av; // CL-CC (finite); *_inf mirrors CL infinite
    logic                 fc_init_done;
    logic                 dl_up;         // DL SM Active or Replay (from rivet_dll)
    logic                 dl_active;     // alias of dl_up (TL readiness)
    logic                 tx_gate_ready; // fc_init_done; TLP TX may use av
    logic                 ph_ok;         // >=1 hdr credit (or inf)
    logic                 pd_ok;
    logic                 nph_ok;
    logic                 npd_ok;
    logic                 cplh_ok;
    logic                 cpld_ok;
  } rivet_dll_tl_fc_sb_t;

  // TL <-> DLL TLP stream (internal; not user AXI-ST). Byte-granular keep.
  localparam int unsigned RIVET_TL_DLL_DATA_W  = 64;
  localparam int unsigned RIVET_TL_DLL_KEEP_W  = RIVET_TL_DLL_DATA_W / 8;

  // PG213 cfg_fc_sel (UltraScale+ Table 32 subset we implement).
  localparam logic [2:0] RIVET_CFG_FC_SEL_RX_AVAIL  = 3'b000;
  localparam logic [2:0] RIVET_CFG_FC_SEL_RX_CONS   = 3'b010;
  localparam logic [2:0] RIVET_CFG_FC_SEL_TX_AVAIL  = 3'b100;
  localparam logic [2:0] RIVET_CFG_FC_SEL_TX_LIMIT  = 3'b101;
  localparam logic [2:0] RIVET_CFG_FC_SEL_TX_CONS   = 3'b110;

  // PG213: infinite TX credits available → 8'h80 / 12'h800 on cfg_fc_*.
  localparam logic [7:0]  RIVET_CFG_FC_HDR_INF_TX_AV = 8'h80;
  localparam logic [11:0] RIVET_CFG_FC_DATA_INF_TX_AV = 12'h800;

  function automatic logic [7:0] rivet_fc_hdr_avail(
      input logic [7:0] cl, input logic [7:0] cc, input logic inf);
    return inf ? 8'hFF : (cl - cc);
  endfunction

  function automatic logic [11:0] rivet_fc_data_avail(
      input logic [11:0] cl, input logic [11:0] cc, input logic inf);
    return inf ? 12'hFFF : (cl - cc);
  endfunction

  function automatic bit rivet_fc_hdr_ok(
      input logic [7:0] cl, input logic [7:0] cc, input logic inf,
      input logic [7:0] need);
    if (inf) return 1'b1;
    return (cl - cc) >= need;
  endfunction

  function automatic bit rivet_fc_data_ok(
      input logic [11:0] cl, input logic [11:0] cc, input logic inf,
      input logic [11:0] need);
    if (inf) return 1'b1;
    return (cl - cc) >= need;
  endfunction

  // pcie_tfc_* scale: 0..14 exact, 15 = 15 or more (PG213).
  function automatic logic [3:0] rivet_fc_tfc_scale(input logic [11:0] avail, input logic inf);
    if (inf) return 4'hF;
    if (avail >= 12'd15) return 4'hF;
    return avail[3:0];
  endfunction


  function automatic logic [7:0] rivet_dllp_fc_type_byte(
      input rivet_dllp_fc_kind_e kind,
      input logic [2:0] vc);
    return {kind, 1'b0, vc};
  endfunction

  // Soft request into dllp_tx (before CRC).
  typedef struct packed {
    rivet_dllp_kind_e     kind;
    rivet_dllp_fc_kind_e  fc_kind;
    logic [2:0]           vc;
    logic [7:0]           hdr_fc;
    logic [11:0]          data_fc;
    logic [11:0]          ack_seq;
  } rivet_dllp_req_t;

  // Decoded DLLP from dllp_rx (after CRC check).
  typedef struct packed {
    rivet_dllp_kind_e     kind;
    rivet_dllp_fc_kind_e  fc_kind;
    logic [2:0]           vc;
    logic [7:0]           hdr_fc;
    logic [11:0]          data_fc;
    logic [11:0]          ack_seq;
    logic                 crc_ok;
  } rivet_dllp_dec_t;

  // DLL TLP framing sizes (seq + LCRC around TL payload).
  localparam int unsigned RIVET_TLP_SEQ_BYTES  = 2;
  localparam int unsigned RIVET_TLP_LCRC_BYTES = 4;
  // MAC assemble buffer (Cfg/Cpl-class TLPs). Larger payloads come later.
  localparam int unsigned RIVET_MAC_TLP_BUF_BYTES = 64;

  // Type 0 config space (EP smoke)
  localparam logic [15:0] RIVET_CFG_VENDOR_ID = 16'h1EE0;
  localparam logic [15:0] RIVET_CFG_DEVICE_ID = 16'h0001;
  localparam logic [15:0] RIVET_CFG_CLASS_REV = 16'h0000;
  localparam logic [7:0]  RIVET_CFG_REV_ID    = 8'h01;
  localparam logic [23:0] RIVET_CFG_CLASS     = 24'h120000;
  localparam logic [31:0] RIVET_CFG_BAR0_MASK = 32'hFFFF_0000; // 64 KiB MMIO

  // TLP Fmt/Type in header byte 0: {Fmt[2:0], Type[4:0]}.
  localparam logic [4:0] RIVET_TLP_TYPE_MEM = 5'b00000;
  localparam logic [4:0] RIVET_TLP_TYPE_CFG = 5'b00100;
  localparam logic [4:0] RIVET_TLP_TYPE_CPL = 5'b01010;
  localparam logic [7:0] RIVET_TLP_B0_CFGRD0 = 8'h04;
  localparam logic [7:0] RIVET_TLP_B0_CFGWR0 = 8'h44;
  localparam logic [7:0] RIVET_TLP_B0_CPL    = 8'h0A;
  localparam logic [7:0] RIVET_TLP_B0_CPLD   = 8'h4A;

  typedef enum logic [1:0] {
    RIVET_FC_CLS_P   = 2'd0,
    RIVET_FC_CLS_NP  = 2'd1,
    RIVET_FC_CLS_CPL = 2'd2
  } rivet_fc_cls_e;

  function automatic logic [4:0] rivet_tlp_type5(input logic [7:0] b0);
    return b0[4:0];
  endfunction

  function automatic logic rivet_tlp_has_data(input logic [7:0] b0);
    return b0[6];
  endfunction

  function automatic rivet_fc_cls_e rivet_tlp_fc_class(input logic [7:0] b0);
    if (rivet_tlp_type5(b0) == RIVET_TLP_TYPE_CPL)
      return RIVET_FC_CLS_CPL;
    if (rivet_tlp_type5(b0) == RIVET_TLP_TYPE_CFG)
      return RIVET_FC_CLS_NP;
    if (rivet_tlp_has_data(b0))
      return RIVET_FC_CLS_P;
    return RIVET_FC_CLS_NP;
  endfunction

  function automatic logic [11:0] rivet_tlp_data_credits(input logic [9:0] len_dw);
    return 12'((32'(len_dw) + 32'd3) / 32'd4);
  endfunction

  function automatic logic [9:0] rivet_tlp_len_dw(input logic [7:0] b2, input logic [7:0] b3);
    return {b3[1:0], b2};
  endfunction

  function automatic logic [15:0] rivet_tlp_seq_bytes(input logic [11:0] seq);
    // Byte0: {Rsvd[3:0], Seq[11:8]}; Byte1: Seq[7:0]
    return {seq[7:0], 4'h0, seq[11:8]};
  endfunction

  // Combinational LCRC (same algorithm as rivet_dll_lcrc32 streaming core).
  // Argument width covers default REPLAY_SLOT_BYTES (160).
  function automatic logic [31:0] rivet_lcrc32_calc(
      input logic [8*160-1:0] bytes_le, // byte0 in [7:0]
      input int unsigned      nbytes);
    logic [31:0] crc;
    logic [7:0]  b;
    logic        din;
    logic        fb;
    int unsigned bi, bit_i;
    crc = 32'hFFFF_FFFF;
    for (bi = 0; bi < nbytes; bi++) begin
      b = bytes_le[8*bi +: 8];
      for (bit_i = 0; bit_i < 8; bit_i++) begin
        din = b[bit_i];
        fb  = crc[0] ^ din;
        crc = {1'b0, crc[31:1]};
        if (fb) crc = crc ^ 32'hEDB88320;
      end
    end
    // LSB-first remainder already matches the LCRC field — complement only.
    return ~crc;
  endfunction

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
  // One Symbol: pad bit i ← lfsr[15-i] (D15→data bit0), then 8-bit parallel
  // advance (FFFF→E817→0328→…; scrambled 00h→FF,17,C0,14,…).
  // -------------------------------------------------------------------------
  localparam logic [15:0] RIVET_LFSR_SEED = 16'hFFFF;

  function automatic logic [23:0] rivet_lfsr_step(input logic [15:0] lfsr_in);
    logic [15:0] lfsr;
    logic [7:0]  pad;
    lfsr = lfsr_in;
    pad  = {lfsr[8],  lfsr[9],  lfsr[10], lfsr[11],
            lfsr[12], lfsr[13], lfsr[14], lfsr[15]};
    lfsr = {lfsr[7],
            lfsr[6],
            lfsr[5],
            lfsr[4]  ^ lfsr[15],
            lfsr[3]  ^ lfsr[15] ^ lfsr[14],
            lfsr[2]  ^ lfsr[15] ^ lfsr[14] ^ lfsr[13],
            lfsr[1]  ^ lfsr[14] ^ lfsr[13] ^ lfsr[12],
            lfsr[0]  ^ lfsr[13] ^ lfsr[12] ^ lfsr[11],
            lfsr[15] ^ lfsr[12] ^ lfsr[11] ^ lfsr[10],
            lfsr[14] ^ lfsr[11] ^ lfsr[10] ^ lfsr[9],
            lfsr[13] ^ lfsr[10] ^ lfsr[9]  ^ lfsr[8],
            lfsr[12] ^ lfsr[9]  ^ lfsr[8],
            lfsr[11] ^ lfsr[8],
            lfsr[10],
            lfsr[9],
            lfsr[8]};
    return {lfsr, pad};
  endfunction

endpackage : rivet_pkg
