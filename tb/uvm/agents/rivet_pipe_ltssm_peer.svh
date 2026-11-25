// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Downstream Port PIPE peer: Detect ack + TS/Idle training against DUT TX.
// Mirrors tb/smoke/rivet_ltssm_smoke_tb.sv so Questa UVM can reach L0.
// Enable via config_db bit "ltssm_peer_enable"; use with pipe_agent PASSIVE.

class rivet_pipe_ltssm_peer extends uvm_component;
  `uvm_component_utils(rivet_pipe_ltssm_peer)

  rivet_pipe_vif vif;
  int unsigned   lanes = 1;
  bit            enable = 0;
  bit            dllp_fc_enable = 0;
  bit            tlp_memrd_enable = 0;
  bit            tlp_memrd64_enable = 0; // MemRd64 instead of MemRd32 when set
  bit            tlp_cpld_enable = 0;
  bit            speed_change_enable = 0; // set TS rate-ID bit 7 in Recovery
  bit            hot_reset_enable = 0;    // set TS training-control Hot Reset
  bit            disable_link_enable = 0; // set TS training-control Disable Link
  bit            gen3_block_only = 0;     // drive blocks, do not run the LTSSM
  bit            peer_gen3 = 0;           // advertise 8 GT/s and send blocks after Recovery.Speed
  bit            peer_gen4 = 0;           // advertise 16 GT/s, then a second EQ at Gen4
  // Upstream slave. Link# 00 and Lane# 0..n-1 match the numbers a downstream
  // DUT assigns, so the 8b/10b image is the echo. Gen3 blocks wait for the
  // master's 8'h0A, answer with one 8'h02 block, hold 8'h0A until the master
  // leaves EQ, then TS2 until the DUT is in Recovery.RcvrCfg, then logical idle.
  bit            peer_upstream = 0;
  logic [2:0]    rxstatus_err_code = 3'b100; // RxStatus injected by peer_rxstatus_err_go
  int unsigned   peer_lanes = 0;         // 0 = all DUT lanes; else narrower partner
  bit            peer_lane_reverse = 0;  // assign Lane# W-1..0 on phys 0..W-1
  uvm_analysis_port #(rivet_dllp_item) dllp_ap;

  bit [31:0] tlp_memrd_addr = 32'h0000_0010;
  bit [7:0]  tlp_memrd_tag  = 8'h23;
  bit [15:0] tlp_memrd_rid  = 16'h0001;
  bit [7:0]  tlp_cpld_tag   = 8'h11;
  bit [15:0] tlp_cpld_rid   = 16'h0100;
  // Tag byte of the DUT TLP currently being parsed, and one entry per END.
  bit [7:0]  seen_tag;
  bit [7:0]  req_tag_q[$];
  bit [31:0] tlp_cpld_data  = 32'hCAFE_BABE;
  // Set before link-up. InitFC credit 0 means infinite.
  bit            perf_rc;

  localparam logic [7:0] SYM_COM    = 8'hBC;
  localparam logic [7:0] SYM_PAD    = 8'hF7;
  localparam logic [7:0] SYM_TS1_ID = 8'h4A;
  localparam logic [7:0] SYM_TS2_ID = 8'h45;
  localparam logic [7:0] PEER_LINK  = 8'h00;
  localparam logic [7:0] PEER_NFTS  = 8'h00;
  localparam logic [7:0] PEER_RATE  = 8'h06;
  localparam int unsigned PW = `RIVET_TB_PIPE_W;

  // Gen3 TS block byte. Byte 6 is {success, phase request}; byte 7 is the preset.
  function automatic logic [7:0] gen3_ts_byte(
    input int unsigned idx,
    input bit          ts2,
    input logic [7:0]  lane_n,
    input logic [7:0]  eq_ctrl,
    input logic [7:0]  eq_data,
    input logic [7:0]  rate_b
  );
    case (idx[3:0])
      4'd0:    return ts2 ? 8'h2D : 8'h1E;
      4'd1:    return 8'h00;
      4'd2:    return lane_n;
      4'd4:    return rate_b;
      4'd6:    return eq_ctrl;
      4'd7:    return eq_data;
      default: return 8'h00;
    endcase
  endfunction

  typedef enum int unsigned {
    P_TS1_PAD,
    P_TS2_PAD,
    P_TS1_LINK,
    P_TS1_LANE,
    P_TS2_CFG,
    P_IDLE
  } peer_phase_e;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dllp_ap = new("dllp_ap", this);
    void'(uvm_config_db#(bit)::get(this, "", "ltssm_peer_enable", enable));
    void'(uvm_config_db#(bit)::get(this, "", "dllp_fc_enable", dllp_fc_enable));
    void'(uvm_config_db#(bit)::get(this, "", "tlp_memrd_enable", tlp_memrd_enable));
    void'(uvm_config_db#(bit)::get(this, "", "tlp_memrd64_enable", tlp_memrd64_enable));
    void'(uvm_config_db#(bit)::get(this, "", "tlp_cpld_enable", tlp_cpld_enable));
    void'(uvm_config_db#(bit)::get(this, "", "speed_change_enable", speed_change_enable));
    void'(uvm_config_db#(bit)::get(this, "", "hot_reset_enable", hot_reset_enable));
    void'(uvm_config_db#(bit)::get(this, "", "disable_link_enable", disable_link_enable));
    void'(uvm_config_db#(bit)::get(this, "", "gen3_block_only", gen3_block_only));
    void'(uvm_config_db#(bit)::get(this, "", "peer_gen3", peer_gen3));
    void'(uvm_config_db#(bit)::get(this, "", "peer_gen4", peer_gen4));
    void'(uvm_config_db#(bit)::get(this, "", "peer_upstream", peer_upstream));
    void'(uvm_config_db#(logic [2:0])::get(this, "", "rxstatus_err_code", rxstatus_err_code));
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
    void'(uvm_config_db#(int unsigned)::get(this, "", "peer_lanes", peer_lanes));
    void'(uvm_config_db#(bit)::get(this, "", "peer_lane_reverse", peer_lane_reverse));
    if (peer_lanes == 0 || peer_lanes > lanes)
      peer_lanes = lanes;
    if (peer_lanes <= 1)
      peer_lane_reverse = 1'b0;
    if (!enable) return;
    if (!uvm_config_db#(rivet_pipe_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_pipe_vif not set for LTSSM peer")
  endfunction

  function automatic logic [8:0] peer_sym(
      input logic [3:0] idx,
      input bit         ts2,
      input bit         link_pad,
      input bit         lane_pad,
      input logic [7:0] lane,
      input logic [7:0] rate_byte,
      input logic [7:0] train_byte
  );
    case (idx)
      4'd0:    return {1'b1, SYM_COM};
      4'd1:    return link_pad ? {1'b1, SYM_PAD} : {1'b0, PEER_LINK};
      4'd2:    return lane_pad ? {1'b1, SYM_PAD} : {1'b0, lane};
      4'd3:    return {1'b0, PEER_NFTS};
      4'd4:    return {1'b0, rate_byte};
      4'd5:    return {1'b0, train_byte};
      default: return ts2 ? {1'b0, SYM_TS2_ID} : {1'b0, SYM_TS1_ID};
    endcase
  endfunction

  function automatic logic [23:0] peer_lfsr_step(input logic [15:0] lfsr_in);
    return rivet_pkg::rivet_lfsr_step(lfsr_in);
  endfunction

  function automatic logic [7:0] peer_scramble(
      input  logic [7:0]  din,
      input  logic        is_k,
      input  logic        os_d,
      inout  logic [15:0] lfsr
  );
    logic [23:0] step;
    if (is_k && (din == SYM_COM)) begin
      lfsr = 16'hFFFF;
      return din;
    end
    if (is_k && (din == 8'h1C)) return din;
    step = peer_lfsr_step(lfsr);
    lfsr = step[23:8];
    if (!is_k && !os_d) return din ^ step[7:0];
    return din;
  endfunction

  // Match rivet_mac_scrambler: COM reloads the seed, SKP holds it, every
  // other symbol advances. Ordered-set data is not visible on PIPE, so this
  // is exact once L0 has no TS symbols.
  function automatic logic [7:0] dut_unscramble(
      input logic [7:0]  din,
      input logic        is_k,
      inout logic [15:0] lfsr
  );
    logic [23:0] step;
    if (is_k && (din == SYM_COM)) begin
      lfsr = 16'hFFFF;
      return din;
    end
    if (is_k && (din == 8'h1C))
      return din;
    step = peer_lfsr_step(lfsr);
    lfsr = step[23:8];
    if (!is_k)
      return din ^ step[7:0];
    return din;
  endfunction

  // st: 0 hunt, 1 TLP, 2 DLLP. First two TLP bytes are the sequence number.
  function automatic void dut_note_sym(
      input logic [7:0] sym,
      input logic       is_k,
      inout int unsigned st,
      inout int unsigned n,
      inout logic [7:0]  b0,
      inout logic [7:0]  b1,
      inout bit          pending,
      inout logic [11:0] seq,
      inout int unsigned tlp_ends
  );
    if (is_k && (sym == rivet_pkg::RIVET_SYM_STP)) begin
      st = 1;
      n  = 0;
    end else if (is_k && (sym == rivet_pkg::RIVET_SYM_SDP)) begin
      st = 2;
      n  = 0;
    end else if (st == 1) begin
      if (is_k && (sym == rivet_pkg::RIVET_SYM_END)) begin
        seq     = {b0[3:0], b1};
        pending = 1'b1;
        tlp_ends++;
        req_tag_q.push_back(seen_tag);
        st      = 0;
      end else if (!is_k) begin
        if (n == 0) b0 = sym;
        else if (n == 1) b1 = sym;
        else if (n == 8) seen_tag = sym;
        n++;
      end else begin
        st = 0;
      end
    end else if (st == 2) begin
      if ((is_k && (sym == rivet_pkg::RIVET_SYM_END)) || !is_k) begin
        if (!is_k) n++;
        if (is_k || (n > 6)) st = 0;
      end else begin
        st = 0;
      end
    end
  endfunction

  // Gen3 frame: STP, 2-byte little-endian DLL length, DLL bytes. A payload
  // byte equal to STP, SDP, or END is data. st: 0 hunt, 1 len lo, 2 len hi,
  // 3 TLP body, 4 DLLP body.
  function automatic void dut_note_g3(
      input logic [7:0] sym,
      inout int unsigned st,
      inout int unsigned n,
      inout int unsigned left,
      inout logic [7:0]  b0,
      inout logic [7:0]  b1,
      inout bit          pending,
      inout logic [11:0] seq,
      inout int unsigned tlp_ends
  );
    if (st == 0) begin
      if (sym == rivet_pkg::RIVET_SYM_STP) begin
        st   = 1;
        n    = 0;
        left = 0;
      end else if (sym == rivet_pkg::RIVET_SYM_SDP) begin
        st = 4;
        n  = 0;
      end
    end else if (st == 1) begin
      left = sym;
      st   = 2;
    end else if (st == 2) begin
      left = (int'(sym) << 8) | (left & 8'hFF);
      n    = 0;
      st   = (left == 0) ? 0 : 3;
    end else if (st == 3) begin
      if (n == 0) b0 = sym;
      else if (n == 1) b1 = sym;
      else if (n == 8) seen_tag = sym;
      n++;
      if (n >= left) begin
        seq     = {b0[3:0], b1};
        pending = 1'b1;
        tlp_ends++;
        req_tag_q.push_back(seen_tag);
        st = 0;
      end
    end else begin
      // DLLP body: 6 payload/CRC bytes plus trailing END. Do not exit early if
      // a DLLP payload/CRC byte happens to equal END (0xFD).
      n++;
      if (n >= 7) st = 0;
    end
  endfunction


  function automatic rivet_pkg::rivet_dllp_fc_kind_e fc_kind_at(input int unsigned idx);
    case (idx)
      0: return rivet_pkg::RIVET_DLLP_FC_INIT1_P;
      1: return rivet_pkg::RIVET_DLLP_FC_INIT1_NP;
      2: return rivet_pkg::RIVET_DLLP_FC_INIT1_CPL;
      3: return rivet_pkg::RIVET_DLLP_FC_INIT2_P;
      4: return rivet_pkg::RIVET_DLLP_FC_INIT2_NP;
      5: return rivet_pkg::RIVET_DLLP_FC_INIT2_CPL;
      6: return rivet_pkg::RIVET_DLLP_FC_UPDATE_P;
      7: return rivet_pkg::RIVET_DLLP_FC_UPDATE_NP;
      default: return rivet_pkg::RIVET_DLLP_FC_UPDATE_CPL;
    endcase
  endfunction

  function automatic void peer_fc_credits(
      input  rivet_pkg::rivet_dllp_fc_kind_e kind,
      output logic [7:0]  hdr,
      output logic [11:0] data);
    if (perf_rc) begin
      hdr  = 8'h00;
      data = 12'h000;
      return;
    end
    unique case (kind)
      rivet_pkg::RIVET_DLLP_FC_INIT1_P,
      rivet_pkg::RIVET_DLLP_FC_INIT2_P,
      rivet_pkg::RIVET_DLLP_FC_UPDATE_P: begin hdr = 8'h20; data = 12'h100; end
      rivet_pkg::RIVET_DLLP_FC_INIT1_NP,
      rivet_pkg::RIVET_DLLP_FC_INIT2_NP,
      rivet_pkg::RIVET_DLLP_FC_UPDATE_NP: begin hdr = 8'h10; data = 12'h080; end
      default: begin hdr = 8'h00; data = 12'h000; end
    endcase
  endfunction

  function void publish_peer_fc(rivet_pkg::rivet_dllp_fc_kind_e kind,
                                logic [7:0] hdr, logic [11:0] data);
    rivet_dllp_item item;
    item = rivet_dllp_item::type_id::create("dllp_peer");
    item.from_dut = 1'b0;
    item.crc_ok   = 1'b1;
    item.is_fc    = 1'b1;
    item.fc_kind  = kind;
    item.vc       = 3'd0;
    item.hdr_fc   = hdr;
    item.data_fc  = data;
    item.type_byte = rivet_pkg::rivet_dllp_fc_type_byte(kind, 3'd0);
    dllp_ap.write(item);
  endfunction

  // One 16-byte Gen3 block on every lane. rxstart_block is 2'b01 on the first
  // word only. A bubble holds rxdata_valid low and must not enter the stream.
  // Gen2 tests must not call this.
  task automatic drive_gen3_block(
      input logic [1:0] sync_hdr,
      input bit         bubble,
      input logic [7:0] base,
      input logic [1:0] start_sel = 2'b01
  );
    int unsigned w, l, b;
    int unsigned nwords;
    logic [63:0] word;
    localparam int unsigned PW = `RIVET_TB_PIPE_W;
    nwords = 128 / PW;
    for (w = 0; w < nwords; w++) begin
      @(posedge vif.pclk);
      word = '0;
      for (b = 0; b < (PW/8); b++)
        word[8*b +: 8] = base + 8'(w*(PW/8) + b);
      for (l = 0; l < lanes; l++) begin
        vif.rxdata[l*PW +: PW]       <= word[PW-1:0];
        vif.rxdatak[l*2 +: 2]        <= 2'b00;
        vif.rxdata_valid[l]          <= 1'b1;
        vif.rxstart_block[l*2 +: 2]  <= (w == 0) ? start_sel : 2'b00;
        vif.rxsync_header[l*2 +: 2]  <= (w == 0) ? sync_hdr : 2'b00;
        vif.rxelecidle[l]            <= 1'b1;
        vif.rxvalid[l]               <= 1'b0;
      end
      if (bubble && (w == 0)) begin
        @(posedge vif.pclk);
        for (l = 0; l < lanes; l++) begin
          vif.rxdata_valid[l]         <= 1'b0;
          vif.rxdata[l*PW +: PW]      <= {PW{1'b1}};
          vif.rxstart_block[l*2 +: 2] <= 2'b00;
        end
      end
    end
    @(posedge vif.pclk);
    vif.rxdata_valid  <= '0;
    vif.rxstart_block <= '0;
    vif.rxsync_header <= '0;
  endtask

  // One 16-byte Gen3 TS1 block on every lane. Byte 1 is the link number,
  // byte 2 is that lane's number, byte 4 is the rate identifier. Sync header
  // is an ordered set. Gen2 tests must not call this.
  task automatic drive_gen3_ts1(
      input logic [7:0] link_num,
      input logic [7:0] rate_id
  );
    int unsigned w, l, b;
    int unsigned nwords;
    logic [7:0]  sym;
    logic [31:0] word;
    localparam int unsigned PW = `RIVET_TB_PIPE_W;
    nwords = 128 / PW;
    for (w = 0; w < nwords; w++) begin
      @(posedge vif.pclk);
      for (l = 0; l < lanes; l++) begin
        word = '0;
        for (b = 0; b < (PW/8); b++) begin
          unique case (w*(PW/8) + b)
            0: sym = 8'h1E;
            1: sym = link_num;
            2: sym = 8'(l);
            4: sym = rate_id;
            default: sym = 8'h00;
          endcase
          word[8*b +: 8] = sym;
        end
        vif.rxdata[l*PW +: PW]      <= word[PW-1:0];
        vif.rxdatak[l*2 +: 2]       <= 2'b00;
        vif.rxdata_valid[l]         <= 1'b1;
        vif.rxstart_block[l*2 +: 2] <= (w == 0) ? 2'b01 : 2'b00;
        vif.rxsync_header[l*2 +: 2] <= (w == 0) ? 2'b10 : 2'b00;
        vif.rxelecidle[l]           <= 1'b1;
        vif.rxvalid[l]              <= 1'b0;
      end
    end
    @(posedge vif.pclk);
    vif.rxdata_valid  <= '0;
    vif.rxstart_block <= '0;
    vif.rxsync_header <= '0;
  endtask

  task run_phase(uvm_phase phase);
    peer_phase_e phase_q;
    logic [4:0]  peer_ptr;
    logic [11:0] phase_sets;
    logic [7:0]  idle_seen;
    logic [3:0]  detect_cnt;
    logic        detect_ack;
    logic        txdetectrx_d;
    logic        peer_active;
    logic [15:0] peer_lfsr[];
    logic        dut_tx_ts1, dut_tx_ts2, dut_tx_k, dut_tx_com, dut_tx_data_only;
    logic        send_ts2, send_link_pad, send_lane_pad, send_os;
    logic [8:0]  peer_tmp;
    logic [7:0]  peer_out;
    int unsigned l, s;
    int unsigned fc_idx, fc_sym, fc_gap_left;
    logic [47:0] fc_wire;
    logic [7:0]  fc_hdr;
    logic [11:0] fc_data;
    rivet_pkg::rivet_dllp_fc_kind_e fc_kind;
    bit          fc_sending;
    logic [8:0]  fc_sym9;
    bit          tlp_sending;
    bit          ack_inflight;
    bit          ack_pending;
    logic [11:0] ack_seq;
    logic [15:0] dut_lfsr[];
    int unsigned parse_st;
    int unsigned parse_n;
    int unsigned g3_left;
    logic [7:0]  seq_b0, seq_b1;
    int unsigned ack_n;
    bit          tlp_memrd_done;
    bit          tlp_cpld_done;
    int unsigned tlp_seq;
    bit          recovery_go;
    bit          recovery_pulse;
    logic [2:0]  last_rate;
    // Pipe data is one cycle behind the rate pin. Descramble with the
    // rate that actually scrambled this word.
    logic [2:0]  rate_d1;
    int unsigned rate_ack_left;
    logic [7:0]  peer_rate_byte;
    logic [7:0]  peer_train_byte;
    bit          hot_reset_go;
    bit          disable_go;
    bit          rxstatus_err_go;
    int unsigned rxstatus_err_left;
    bit          tc_inject_active;
    int unsigned tlp_sym;
    int unsigned tlp_nbytes;
    logic [8*32-1:0] tlp_frame;
    logic [63:0] tlp_b0, tlp_b1;
    logic [8:0]  tlp_sym9;
    logic [7:0]  cpld_mem[0:4127];
    bit          tlp_large;
    int unsigned cpld_owed;
    int unsigned tlp_ends;
    bit          cpld_auto;
    int unsigned g3_off;
    int unsigned g3_sets;
    bit          g3_speed;
    int unsigned com_hold;
    logic [22:0] g3_lfsr[];
    logic [22:0] g3_rx_lfsr[];
    logic [7:0]  g3_plain[0:3][0:7];
    bit          g3_frame_beat;
    bit          g3_wire;
    int unsigned g3_ns;
    bit          g3_rx_arm;
    bit          g3_rx_data_blk;
    bit          g3_rx_skp_blk;
    int unsigned g3_tx_off;
    int unsigned g3_up_ph;
    int unsigned g3_up_blk;
    bit          g3_saw_0a;
    bit          g3_left_eq;
    bit          g3_saw_ts2;
    bit          g3_tx_is_ts;
    logic [7:0]  g3_dut_eq;
    logic [7:0]  g3_dut_id;

    if (!enable) return;

    if (gen3_block_only) begin
      wait (vif.preset_n === 1'b1);
      vif.rxdata        <= '0;
      vif.rxdatak       <= '0;
      vif.rxdata_valid  <= '0;
      vif.rxstart_block <= '0;
      vif.rxsync_header <= '0;
      vif.rxvalid       <= '0;
      vif.rxelecidle    <= '1;
      vif.rxstatus      <= '0;
      vif.phystatus     <= '0;
      return;
    end

    perf_rc = 1'b0;
    void'(uvm_config_db#(bit)::get(null, "*", "peer_perf_rc", perf_rc));
    peer_lfsr = new[lanes];
    dut_lfsr  = new[lanes];
    g3_lfsr    = new[lanes];
    g3_rx_lfsr = new[lanes];
    wait (vif.preset_n === 1'b1);

    phase_q      = P_TS1_PAD;
    peer_ptr     = '0;
    phase_sets   = '0;
    idle_seen    = '0;
    detect_cnt   = '0;
    detect_ack   = 1'b0;
    txdetectrx_d = 1'b0;
    peer_active  = 1'b0;
    fc_idx = 0; fc_sym = 0; fc_gap_left = 0; fc_wire = '0; fc_sending = 1'b0;
    tlp_sending = 1'b0; tlp_memrd_done = 1'b0; tlp_cpld_done = 1'b0;
    tlp_seq = 0;
    tlp_sym = 0; tlp_nbytes = 0; tlp_frame = '0;
    recovery_go = 1'b0; recovery_pulse = 1'b0;
    last_rate = 3'd0; rate_d1 = 3'd0; rate_ack_left = 0; peer_rate_byte = PEER_RATE;
    g3_off = 0; g3_sets = 0; g3_speed = 1'b0; com_hold = 0; g3_frame_beat = 1'b0;
    g3_rx_arm = 1'b0;
    g3_rx_data_blk = 1'b0; g3_rx_skp_blk = 1'b0;
    g3_tx_off = 0; g3_up_ph = 0; g3_up_blk = 0;
    g3_saw_0a = 1'b0; g3_left_eq = 1'b0; g3_saw_ts2 = 1'b0;
    g3_tx_is_ts = 1'b0;
    g3_dut_eq = 8'h00; g3_dut_id = 8'h00;
    peer_train_byte = 8'h00; hot_reset_go = 1'b0; disable_go = 1'b0;
    tc_inject_active = 1'b0;
    rxstatus_err_go = 1'b0; rxstatus_err_left = 0;
    for (l = 0; l < lanes; l++) begin
      peer_lfsr[l] = 16'hFFFF;
      dut_lfsr[l]  = 16'hFFFF;
      g3_lfsr[l]    = 23'h7FFFFF;
      g3_rx_lfsr[l] = 23'h7FFFFF;
    end
    parse_st = 0; parse_n = 0; g3_left = 0; seq_b0 = '0; seq_b1 = '0;
    ack_pending = 1'b0; ack_inflight = 1'b0; ack_seq = '0; ack_n = 0;

    vif.rxdata        <= '0;
    vif.rxdatak       <= '0;
    vif.rxdata_valid  <= '0;
    vif.rxstart_block <= '0;
    vif.rxsync_header <= '0;
    vif.rxvalid       <= '0;
    vif.rxelecidle    <= '1;
    vif.rxstatus      <= '0;
    vif.phystatus     <= '0;
    vif.phystatus_rst <= '0;

    tlp_large = 1'b0;
    cpld_owed = 0;
    tlp_ends  = 0;

    forever begin
      @(posedge vif.pclk);
      g3_frame_beat = 1'b0;
      // Gen3 is four symbols. Gen4 is eight. Both use the length-prefixed frame.
      g3_wire = (peer_gen3 && (vif.rate == 3'd2)) ||
                (peer_gen4 && ((vif.rate == 3'd2) || (vif.rate == 3'd3)));
      g3_ns   = (vif.rate == 3'd3) ? 8 : (g3_wire ? 4 : 2);
      for (l = 0; l < 4; l++)
        for (s = 0; s < 8; s++)
          g3_plain[l][s] = 8'h00;
      cpld_auto = 1'b0;
      void'(uvm_config_db#(bit)::get(null, "*", "peer_cpld_auto", cpld_auto));

      dut_tx_ts1 = 1'b0;
      dut_tx_ts2 = 1'b0;
      dut_tx_k   = 1'b0;
      dut_tx_com = 1'b0;
      // Only wire-live peer lanes; DUT EI on unused lanes after width narrow.
      // A scrambled TLP byte can equal the TS identifier. Recovery is COM
      // plus that identifier in the same cycle; a bare identifier is not.
      for (l = 0; l < peer_lanes; l++) begin
        if (vif.txelecidle[l]) continue;
        for (s = 0; s < 2; s++) begin
          if (vif.txdatak[2*l + s]) begin
            dut_tx_k = 1'b1;
            if (vif.txdata[l*PW + 8*s +: 8] == SYM_COM) dut_tx_com = 1'b1;
          end else begin
            if (vif.txdata[l*PW + 8*s +: 8] == SYM_TS1_ID) dut_tx_ts1 = 1'b1;
            if (vif.txdata[l*PW + 8*s +: 8] == SYM_TS2_ID) dut_tx_ts2 = 1'b1;
          end
        end
      end
      dut_tx_data_only = !dut_tx_k && !dut_tx_ts1 && !dut_tx_ts2;
      if (dut_tx_data_only) begin
        for (l = 0; l < peer_lanes; l++) begin
          if (vif.txelecidle[l]) dut_tx_data_only = 1'b0;
        end
      end

      send_ts2      = (phase_q == P_TS2_PAD) || (phase_q == P_TS2_CFG);
      send_link_pad = (phase_q == P_TS1_PAD) || (phase_q == P_TS2_PAD);
      send_lane_pad = (phase_q != P_TS1_LANE) && (phase_q != P_TS2_CFG);
      send_os       = peer_active && (phase_q != P_IDLE);
      // Advertise Gen2, or 8 GT/s when peer_gen3. Speed-change bit in Recovery TS.
      peer_rate_byte = peer_gen4 ? 8'h1E : (peer_gen3 ? 8'h0E : PEER_RATE);
      if ((speed_change_enable || peer_gen3 || peer_gen4) && send_os && !send_link_pad)
        peer_rate_byte = peer_rate_byte | 8'h80;
      peer_train_byte = 8'h00;
      if (tc_inject_active && send_os && !send_link_pad) begin
        if (hot_reset_enable)
          peer_train_byte[0] = 1'b1;
        if (disable_link_enable)
          peer_train_byte[1] = 1'b1;
      end

      vif.phystatus <= '0;
      vif.rxstatus  <= '0;

      // PIPE rate-change ack: pulse PhyStatus after MAC updates Rate.
      if (vif.rate !== last_rate) begin
        if (detect_ack && (vif.rate != 3'd0 || last_rate != 3'd0))
          rate_ack_left = 4;
        // A new block rate counts a different number of symbols. Start that
        // block at offset 0 from the seed, matching the DUT descrambler.
        if (peer_gen4 && (vif.rate == 3'd3)) begin
          g3_off = 0;
          for (l = 0; l < lanes; l++)
            g3_lfsr[l] = 23'h7FFFFF;
        end
        last_rate = vif.rate;
      end
      if (rate_ack_left != 0) begin
        for (l = 0; l < lanes; l++) vif.phystatus[l] <= 1'b1;
        rate_ack_left = rate_ack_left - 1;
      end

      if (vif.txdetectrx && !txdetectrx_d) begin
        detect_cnt = '0;
        detect_ack = 1'b0;
      end else if (vif.txdetectrx && (vif.powerdown == 2'b10) && !detect_ack) begin
        detect_cnt = detect_cnt + 4'd1;
        if (detect_cnt == 4'd4) begin
          detect_ack    = 1'b1;
          vif.phystatus <= '1;
          for (l = 0; l < lanes; l++) vif.rxstatus[3*l +: 3] <= 3'b011;
        end
      end
      txdetectrx_d = vif.txdetectrx;

      if (detect_ack) begin
        peer_active    = 1'b1;
        // One-cycle RxValid drop forces DUT L0 → Recovery.RcvrLock.
        // Hot Reset / Disable Link: same pulse, then set TS training-control bits.
        recovery_go = 1'b0;
        hot_reset_go = 1'b0;
        disable_go = 1'b0;
        void'(uvm_config_db#(bit)::get(null, "*", "peer_recovery_go", recovery_go));
        void'(uvm_config_db#(bit)::get(null, "*", "peer_hot_reset_go", hot_reset_go));
        void'(uvm_config_db#(bit)::get(null, "*", "peer_disable_go", disable_go));
        if ((recovery_go || hot_reset_go || disable_go) &&
            (phase_q == P_IDLE) && !recovery_pulse) begin
          vif.rxvalid     <= '0;
          recovery_pulse  = 1'b1;
          // Gen3 L0 is already 128b/130b, so a DUT ordered set is not a COM.
          // Restart EQ TS with the speed-change bit for the Gen4 recovery.
          if (peer_gen4 && (vif.rate == 3'd2)) begin
            g3_speed = 1'b1;
            g3_sets  = 0;
            g3_off   = 0;
          end
          if (hot_reset_go || disable_go)
            tc_inject_active = 1'b1;
          uvm_config_db#(bit)::set(null, "*", "peer_recovery_go", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_hot_reset_go", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_disable_go", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_recovery_fired", 1'b1);
        end else begin
          vif.rxvalid    <= '1;
          recovery_pulse = 1'b0;
        end
        vif.rxelecidle <= '0;

        // RxStatus error inject in L0: brief error code on lane 0 with RxValid
        // held high; the DUT must enter Recovery (no RxValid drop).
        rxstatus_err_go = 1'b0;
        void'(uvm_config_db#(bit)::get(null, "*", "peer_rxstatus_err_go", rxstatus_err_go));
        if (rxstatus_err_go && (phase_q == P_IDLE) && (rxstatus_err_left == 0)) begin
          rxstatus_err_left = 2;
          uvm_config_db#(bit)::set(null, "*", "peer_rxstatus_err_go", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_rxstatus_err_fired", 1'b1);
        end
        if (rxstatus_err_left != 0) begin
          vif.rxstatus[2:0] <= rxstatus_err_code;
          rxstatus_err_left = rxstatus_err_left - 1;
        end
      end


      // Descramble DUT TX (same LFSR rules as rivet_mac_scrambler) and ACK each
      // finished TLP. Cumulative: the latest seq retires every earlier one.
      // Each END still owes one completion; one ACK must not merge that count.
      begin
        automatic int unsigned ends_before;
        ends_before = tlp_ends;
      if (perf_rc && peer_active && (vif.txelecidle == '0) &&
          (vif.txdata_valid != '0) &&
          (((peer_gen3 || peer_gen4) && (vif.rate == 3'd2)) ||
           (peer_gen4 && (vif.rate == 3'd3)))) begin
        // Arm on the first data block, matching the DUT scrambler's reseed.
        // Gen4 entry clears the arm so the next data block reloads the seed.
        automatic int unsigned rx_ns;
        rx_ns = (vif.rate == 3'd3) ? 8 : 4;
        if (peer_gen4 && (vif.rate == 3'd3) && (rate_d1 != 3'd3))
          g3_rx_arm = 1'b0;
        if (!g3_rx_arm && vif.txstart_block[0] && (vif.txsync_header[1:0] == 2'b01)) begin
          for (l = 0; l < peer_lanes; l++)
            g3_rx_lfsr[l] = 23'h7FFFFF;
          g3_rx_arm = 1'b1;
        end
        if (vif.txstart_block[0]) begin
          g3_rx_data_blk = (vif.txsync_header[1:0] == 2'b01);
          g3_rx_skp_blk  = (vif.txsync_header[1:0] == 2'b10) &&
                           (vif.txdata[7:0] == 8'hAA);
        end
        if (g3_rx_arm && !g3_rx_skp_blk) begin
          for (s = 0; s < rx_ns; s++) begin
            for (l = 0; l < peer_lanes; l++) begin
              automatic logic [30:0] step;
              automatic logic [7:0]  raw, sym;
              raw  = vif.txdata[l*PW + 8*s +: 8];
              step = rivet_pkg::rivet_lfsr23_byte(g3_rx_lfsr[l]);
              g3_rx_lfsr[l] = step[30:8];
              sym  = g3_rx_data_blk ? (raw ^ step[7:0]) : raw;
              if ((phase_q == P_IDLE) && g3_rx_data_blk)
                dut_note_g3(sym, parse_st, parse_n, g3_left, seq_b0, seq_b1,
                            ack_pending, ack_seq, tlp_ends);
            end
          end
        end
      end else if (perf_rc && peer_active && (vif.txelecidle != '1)) begin
        for (s = 0; s < 2; s++) begin
          for (l = 0; l < peer_lanes; l++) begin
            automatic logic [7:0] raw, sym;
            automatic logic        is_k;
            automatic logic [15:0] lfsr;
            raw  = vif.txdata[l*PW + 8*s +: 8];
            is_k = vif.txdatak[2*l + s];
            lfsr = dut_lfsr[l];
            sym  = dut_unscramble(raw, is_k, lfsr);
            dut_lfsr[l] = lfsr;
            if (phase_q == P_IDLE)
              dut_note_sym(sym, is_k, parse_st, parse_n, seq_b0, seq_b1,
                           ack_pending, ack_seq, tlp_ends);
          end
        end
      end
      if (cpld_auto)
        cpld_owed += tlp_ends - ends_before;
      end
      if (phase_q != P_IDLE) begin
        parse_st = 0;
        g3_left  = 0;
      end

      // FC DLLP inject in L0: stripe SDP+6+END across peer_lanes (enabled width).
      // A performance RC answers TLPs before it spends the link on UpdateFC,
      // and it does not send UpdateFC after infinite InitFC.
      if (perf_rc && ack_pending && peer_active && (phase_q == P_IDLE) &&
          !fc_sending && !tlp_sending) begin
        fc_wire      = rivet_dllp_util::pack_ack_wire(ack_seq);
        fc_sym       = 0;
        fc_sending   = 1'b1;
        ack_inflight = 1'b1;
        ack_pending  = 1'b0;
        ack_n++;
      end else if (dllp_fc_enable && peer_active && (phase_q == P_IDLE) &&
                   !fc_sending && !(perf_rc && (fc_idx >= 6))) begin
        if (fc_gap_left != 0) begin
          fc_gap_left--;
        end else begin
          fc_kind = fc_kind_at(fc_idx);
          peer_fc_credits(fc_kind, fc_hdr, fc_data);
          fc_wire    = rivet_dllp_util::pack_fc_wire(fc_kind, 3'd0, fc_hdr, fc_data);
          fc_sym     = 0;
          fc_sending = 1'b1;
          publish_peer_fc(fc_kind, fc_hdr, fc_data);
        end
      end else if (phase_q != P_IDLE) begin
        fc_idx = 0; fc_sym = 0; fc_gap_left = 64; fc_wire = '0; fc_sending = 1'b0;
        tlp_sending = 1'b0; tlp_sym = 0;
      end

      // TLP inject after InitFC2 (fc_idx >= 6), between FC gaps.
      // One-shot by default. perf tests set peer_*_rearm to allow another inject.
      if (peer_active && (phase_q == P_IDLE) && !fc_sending && !tlp_sending &&
          (fc_idx >= 6) && (fc_gap_left > 4)) begin
        bit rearm_m, rearm_c;
        rearm_m = 1'b0;
        rearm_c = 1'b0;
        void'(uvm_config_db#(bit)::get(null, "*", "peer_memrd_rearm", rearm_m));
        void'(uvm_config_db#(bit)::get(null, "*", "peer_cpld_rearm", rearm_c));
        if (rearm_m) begin
          tlp_memrd_done = 1'b0;
          uvm_config_db#(bit)::set(null, "*", "peer_memrd_rearm", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_memrd_go", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_tlp_memrd_done", 1'b0);
        end else if (rearm_c) begin
          tlp_cpld_done = 1'b0;
          uvm_config_db#(bit)::set(null, "*", "peer_cpld_rearm", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_cpld_go", 1'b0);
          uvm_config_db#(bit)::set(null, "*", "peer_tlp_cpld_done", 1'b0);
        end else if (tlp_memrd_enable) begin
          bit go_m;
          go_m = 1'b0;
          void'(uvm_config_db#(bit)::get(null, "*", "peer_memrd_go", go_m));
          // Dropping go lets a later rising go inject another MemRd.
          if (!go_m) begin
            tlp_memrd_done = 1'b0;
            uvm_config_db#(bit)::set(null, "*", "peer_tlp_memrd_done", 1'b0);
          end else if (!tlp_memrd_done) begin
            void'(uvm_config_db#(bit [7:0])::get(null, "*", "peer_memrd_tag", tlp_memrd_tag));
            if (tlp_memrd64_enable)
              rivet_axi_tlp_util::pack_memrd64_tl_beats(
                  {32'h0, tlp_memrd_addr}, tlp_memrd_tag, tlp_memrd_rid, 4'hF,
                  tlp_b0, tlp_b1);
            else
              rivet_axi_tlp_util::pack_memrd32_tl_beats(
                  tlp_memrd_addr, tlp_memrd_tag, tlp_memrd_rid, 4'hF, tlp_b0, tlp_b1);
            rivet_axi_tlp_util::pack_dll_tlp_frame(
                tlp_seq[11:0], tlp_b0, tlp_b1, 16, tlp_frame, tlp_nbytes);
            tlp_seq++;
            tlp_sym = 0; tlp_sending = 1'b1; tlp_memrd_done = 1'b1; tlp_large = 1'b0;
            uvm_config_db#(bit)::set(null, "*", "peer_tlp_memrd_done", 1'b1);
          end
        end else if (cpld_auto && (cpld_owed != 0)) begin
          int unsigned dw;
          dw = 1;
          void'(uvm_config_db#(int unsigned)::get(null, "*", "peer_cpld_dw", dw));
          if (dw == 0) dw = 1;
          if (dw > 1024) dw = 1024;
          if (req_tag_q.size() != 0)
            tlp_cpld_tag = req_tag_q.pop_front();
          rivet_axi_tlp_util::pack_cpld_mem(
              tlp_seq[11:0], tlp_cpld_tag, tlp_cpld_rid, dw, cpld_mem, tlp_nbytes);
          tlp_seq++;
          tlp_sym = 0; tlp_sending = 1'b1; tlp_large = 1'b1;
          cpld_owed--;
        end else if (tlp_cpld_enable && !tlp_cpld_done) begin
          bit go_c;
          go_c = 1'b0;
          void'(uvm_config_db#(bit)::get(null, "*", "peer_cpld_go", go_c));
          if (go_c) begin
            void'(uvm_config_db#(bit [7:0])::get(null, "*", "peer_cpld_tag", tlp_cpld_tag));
            rivet_axi_tlp_util::pack_cpld_tl_beats(
                tlp_cpld_rid, tlp_cpld_tag, tlp_cpld_data, tlp_b0, tlp_b1);
            rivet_axi_tlp_util::pack_dll_tlp_frame(
                tlp_seq[11:0], tlp_b0, tlp_b1, 16, tlp_frame, tlp_nbytes);
            tlp_seq++;
            tlp_sym = 0; tlp_sending = 1'b1; tlp_cpld_done = 1'b1; tlp_large = 1'b0;
            uvm_config_db#(bit)::set(null, "*", "peer_tlp_cpld_done", 1'b1);
          end
        end
      end

      vif.rxdata  <= '0;
      vif.rxdatak <= '0;
      if (peer_active) begin
        if (tlp_sending) begin
          automatic int unsigned ns;
          // Gen3 uses four symbols. Gen4 uses eight. Both are length-prefixed.
          ns = g3_ns;
          for (l = 0; l < peer_lanes; l++) begin
            automatic int unsigned phys;
            automatic logic [15:0] lfsr;
            phys = peer_lane_reverse ? (peer_lanes - 1 - l) : l;
            lfsr = peer_lfsr[phys];
            begin
              for (s = 0; s < ns; s++) begin
                automatic int unsigned stream_idx = tlp_sym + s * peer_lanes + l;
                automatic int unsigned framed_len;
                automatic bit          g3_tlp;
                g3_tlp = g3_wire;
                // Gen3 inserts a 2-byte length after STP and drops END.
                framed_len = g3_tlp ? (tlp_nbytes + 3) : (tlp_nbytes + 2);
                if (g3_tlp) begin
                  if (stream_idx == 0)
                    tlp_sym9 = {1'b0, rivet_pkg::RIVET_SYM_STP};
                  else if (stream_idx == 1)
                    tlp_sym9 = {1'b0, tlp_nbytes[7:0]};
                  else if (stream_idx == 2)
                    tlp_sym9 = {1'b0, tlp_nbytes[15:8]};
                  else if (stream_idx < framed_len) begin
                    if (tlp_large)
                      tlp_sym9 = {1'b0, cpld_mem[stream_idx - 3]};
                    else
                      tlp_sym9 = rivet_axi_tlp_util::framed_tlp_sym(
                          stream_idx - 2, tlp_frame, tlp_nbytes);
                  end else
                    tlp_sym9 = {1'b0, 8'h00};
                end else if (stream_idx < framed_len) begin
                  if (tlp_large) begin
                    if (stream_idx == 0)
                      tlp_sym9 = {1'b1, rivet_pkg::RIVET_SYM_STP};
                    else if (stream_idx == tlp_nbytes + 1)
                      tlp_sym9 = {1'b1, rivet_pkg::RIVET_SYM_END};
                    else
                      tlp_sym9 = {1'b0, cpld_mem[stream_idx - 1]};
                  end else
                    tlp_sym9 = rivet_axi_tlp_util::framed_tlp_sym(
                        stream_idx, tlp_frame, tlp_nbytes);
                end else
                  tlp_sym9 = {1'b0, 8'h00};
                peer_tmp = tlp_sym9;
                if (g3_tlp) begin
                  if (phys < 4)
                    g3_plain[phys][s] = peer_tmp[7:0];
                  g3_frame_beat = 1'b1;
                end else begin
                  peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8], 1'b0, lfsr);
                  vif.rxdata[phys*PW + 8*s +: 8] <= peer_out;
                  vif.rxdatak[2*phys + s]        <= peer_tmp[8];
                end
              end
            end
            peer_lfsr[phys] = lfsr;
          end
          tlp_sym += peer_lanes * ns;
          if (tlp_sym >= (g3_wire ? (tlp_nbytes + 3) : (tlp_nbytes + 2)))
            tlp_sending = 1'b0;
        end else if (fc_sending) begin
          for (l = 0; l < peer_lanes; l++) begin
            automatic int unsigned phys;
            automatic logic [15:0] lfsr;
            phys = peer_lane_reverse ? (peer_lanes - 1 - l) : l;
            lfsr = peer_lfsr[phys];
            begin
              automatic int unsigned ns;
              ns = g3_ns;
              for (s = 0; s < ns; s++) begin
                automatic int unsigned stream_idx = fc_sym + s * peer_lanes + l;
                if (stream_idx < 8) begin
                  fc_sym9  = rivet_dllp_util::framed_sym(stream_idx, fc_wire);
                  peer_tmp = fc_sym9;
                end else
                  peer_tmp = {1'b0, 8'h00};
                if (g3_wire) begin
                  if (phys < 4)
                    g3_plain[phys][s] = peer_tmp[7:0];
                  g3_frame_beat = 1'b1;
                end else begin
                  peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8], 1'b0, lfsr);
                  vif.rxdata[phys*PW + 8*s +: 8] <= peer_out;
                  vif.rxdatak[2*phys + s]        <= peer_tmp[8];
                end
              end
            end
            peer_lfsr[phys] = lfsr;
          end
          fc_sym += peer_lanes * g3_ns;
          if (fc_sym >= 8) begin
            fc_sending = 1'b0;
            if (ack_inflight) begin
              ack_inflight = 1'b0;
            end else if (fc_idx < 5) begin
              fc_idx++; fc_gap_left = 8;
            end else if (fc_idx == 5) begin
              fc_idx = 6; fc_gap_left = 16;
            end else begin
              if (fc_idx >= 8) fc_idx = 6; else fc_idx++;
              fc_gap_left = 32;
            end
          end
        end else begin
          for (l = 0; l < lanes; l++) begin
            automatic logic [15:0] lfsr = peer_lfsr[l];
            automatic logic [7:0]  lane_n;
            lane_n = (peer_lane_reverse && (l < peer_lanes))
                   ? 8'(peer_lanes - 1 - l) : 8'(l);
            for (s = 0; s < 2; s++) begin
              peer_tmp = send_os ? peer_sym(4'(peer_ptr + 5'(s)), send_ts2,
                                            send_link_pad || (l >= peer_lanes),
                                            send_lane_pad || (l >= peer_lanes), lane_n,
                                            peer_rate_byte, peer_train_byte)
                                 : {1'b0, 8'h00};
              peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8],
                                       send_os && !peer_tmp[8], lfsr);
              vif.rxdata[l*PW + 8*s +: 8] <= peer_out;
              vif.rxdatak[2*l + s]        <= peer_tmp[8];
            end
            peer_lfsr[l] = lfsr;
          end

          if (send_os) begin
            if (peer_ptr >= 5'd14) begin
              peer_ptr   = '0;
              phase_sets = phase_sets + 12'd1;
            end else
              peer_ptr = peer_ptr + 5'd2;
          end
        end
      end

      // DUT TX in EI restarts training, except Tx_L0s (P0s): the link stays
      // trained and the peer keeps sending Idle.
      if ((vif.txelecidle == '1) && (vif.powerdown != 2'b01)) begin
        phase_q    = P_TS1_PAD;
        phase_sets = '0;
        peer_ptr   = '0;
        idle_seen  = '0;
        tc_inject_active = 1'b0;
        for (l = 0; l < lanes; l++) begin
          peer_lfsr[l] = 16'hFFFF;
          dut_lfsr[l]  = 16'hFFFF;
        end
        parse_st = 0; g3_left = 0; ack_pending = 1'b0;
        com_hold = 0;
      end else begin
        case (phase_q)
          P_TS1_PAD: if (dut_tx_ts2) begin
            phase_q = P_TS2_PAD; phase_sets = '0; peer_ptr = '0;
          end
          P_TS2_PAD: if (dut_tx_ts1) begin
            phase_q = P_TS1_LINK; phase_sets = '0; peer_ptr = '0;
          end
          P_TS1_LINK: if (phase_sets >= 12'd16) begin
            phase_q = P_TS1_LANE; phase_sets = '0; peer_ptr = '0;
          end
          P_TS1_LANE: if (dut_tx_ts2) begin
            phase_q = P_TS2_CFG; phase_sets = '0; peer_ptr = '0;
          end
          P_TS2_CFG: begin
            if (dut_tx_data_only) idle_seen = idle_seen + 8'd1;
            else                  idle_seen = '0;
            if (idle_seen >= 8'd4) phase_q = P_IDLE;
          end
          P_IDLE: begin
            // DUT entered Recovery (TS1/TS2 again) — rejoin numbered training.
            // COM and the TS identifier are several symbols apart, so hold COM
            // for one ordered set. A bare identifier is still not enough.
            if (dut_tx_com)
              com_hold = 8;
            else if (com_hold != 0)
              com_hold = com_hold - 1;
            if ((com_hold != 0) && (dut_tx_ts1 || dut_tx_ts2)) begin
              phase_q    = dut_tx_ts2 ? P_TS2_CFG : P_TS1_LANE;
              phase_sets = '0;
              peer_ptr   = '0;
              idle_seen  = '0;
              com_hold   = 0;
            end
          end
          default: ;
        endcase
      end

      // After the PIPE rate is 8 GT/s or 16 GT/s, replace the 8b/10b symbols
      // with 16-byte blocks. The first blocks carry EQ phase 2 plus the
      // success bit and preset 1, then TS2, then data blocks. peer_gen4
      // repeats that walk at Gen4, and sets the speed-change bit when the
      // DUT leaves Gen3 L0.
      if (((peer_gen3 && (vif.rate == 3'd2)) ||
           (peer_gen4 && ((vif.rate == 3'd2) || (vif.rate == 3'd3)))) &&
          peer_active && (vif.txelecidle != '1)) begin
        bit          ts2;
        bit          data_blk;
        logic [7:0]  eqc, eqd, rate_b;
        int unsigned nsym;
        nsym     = (vif.rate == 3'd3) ? 8 : 4;
        if (peer_upstream && (vif.rate == 3'd2)) begin
          // Sample the DUT TS byte 6. A Gen3 block is 16 bytes, four per cycle.
          if (vif.txstart_block[0]) begin
            g3_tx_off   = 0;
            g3_tx_is_ts = (vif.txsync_header[1:0] == 2'b10) &&
                          ((vif.txdata[7:0] == 8'h1E) || (vif.txdata[7:0] == 8'h2D));
            if (g3_tx_is_ts)
              g3_dut_id = vif.txdata[7:0];
          end
          if (g3_tx_is_ts) begin
            for (s = 0; s < nsym; s++) begin
              if ((g3_tx_off + s) == 6)
                g3_dut_eq = vif.txdata[8*s +: 8];
            end
          end
          g3_tx_off = g3_tx_off + nsym;
          if (g3_tx_off >= 16) begin
            if (g3_tx_is_ts) begin
              if (g3_dut_eq == 8'h0A)
                g3_saw_0a = 1'b1;
              else if (g3_saw_0a)
                g3_left_eq = 1'b1;
              if (g3_dut_id == 8'h2D)
                g3_saw_ts2 = 1'b1;
            end
            g3_tx_off   = 0;
            g3_tx_is_ts = 1'b0;
          end
          data_blk = (g3_up_ph == 4);
          ts2      = (g3_up_ph == 3);
          if (g3_up_ph == 1) begin
            eqc = 8'h02;
            eqd = 8'h00;
          end else if (g3_up_ph == 2) begin
            eqc = 8'h0A;
            eqd = 8'h01;
          end else begin
            eqc = 8'h00;
            eqd = 8'h00;
          end
          rate_b = 8'h0E;
        end else begin
          ts2      = (g3_sets >= 24) && (g3_sets < 40);
          data_blk = (g3_sets >= 40);
          eqc      = (ts2 || data_blk) ? 8'h00 : 8'h0A;
          eqd      = (ts2 || data_blk) ? 8'h00 : 8'h01;
          if (vif.rate == 3'd3)
            rate_b = 8'h1E;
          else if (g3_speed)
            rate_b = 8'h8E;
          else
            rate_b = 8'h0E;
        end
        vif.rxdatak       <= '0;
        vif.rxdata_valid  <= '1;
        for (l = 0; l < lanes; l++) begin
          automatic logic [22:0] lfsr;
          lfsr = g3_lfsr[l];
          vif.rxdata[l*PW +: PW] <= '0;
          vif.rxstart_block[2*l +: 2] <= (g3_off == 0) ? 2'b01 : 2'b00;
          vif.rxsync_header[2*l +: 2] <= data_blk ? 2'b01 : 2'b10;
          for (s = 0; s < nsym; s++) begin
            automatic logic [7:0]  plain;
            automatic logic [30:0] step;
            if (!data_blk)
              plain = gen3_ts_byte(g3_off + s, ts2, 8'(l), eqc, eqd, rate_b);
            else if (g3_frame_beat && (s < 8))
              plain = g3_plain[l][s];
            else
              plain = 8'h00;
            // Same 23-bit step as the DUT descrambler. OS advances only.
            // Data is XORed so a logical idle is 00 after descramble.
            step = rivet_pkg::rivet_lfsr23_byte(lfsr);
            lfsr = step[30:8];
            if (data_blk)
              plain = plain ^ step[7:0];
            vif.rxdata[l*PW + 8*s +: 8] <= plain;
          end
          g3_lfsr[l] = lfsr;
        end
        g3_frame_beat = 1'b0;
        g3_off = g3_off + nsym;
        if (g3_off >= 16) begin
          g3_off = 0;
          if (peer_upstream && (vif.rate == 3'd2)) begin
            case (g3_up_ph)
              0: if (g3_saw_0a) begin
                   g3_up_ph  = 1;
                   g3_up_blk = 0;
                 end
              1: begin
                   g3_up_ph  = 2;
                   g3_up_blk = 0;
                 end
              2: begin
                   g3_up_blk = g3_up_blk + 1;
                   if ((g3_up_blk >= 1) && g3_left_eq) begin
                     g3_up_ph  = 3;
                     g3_up_blk = 0;
                   end
                 end
              3: begin
                   // RcvrLock consumes the first TS2s. Count 16 only after
                   // the DUT itself is sending TS2 (Recovery.RcvrCfg).
                   if (g3_saw_ts2)
                     g3_up_blk = g3_up_blk + 1;
                   if (g3_saw_ts2 && (g3_up_blk >= 16)) begin
                     g3_up_ph = 4;
                     phase_q  = P_IDLE;
                   end
                 end
              default: phase_q = P_IDLE;
            endcase
          end else
            g3_sets = g3_sets + 1;
        end
        if (data_blk)
          phase_q = P_IDLE;
      end else if (peer_gen3 || peer_gen4) begin
        g3_off   = 0;
        g3_sets  = 0;
        g3_speed = 1'b0;
        g3_tx_off = 0;
        g3_up_ph = 0;
        g3_up_blk = 0;
        g3_saw_0a = 1'b0;
        g3_left_eq = 1'b0;
        g3_saw_ts2 = 1'b0;
        g3_tx_is_ts = 1'b0;
        g3_dut_eq = 8'h00;
        g3_dut_id = 8'h00;
        if ((vif.rate != 3'd2) && (vif.rate != 3'd3)) begin
          for (l = 0; l < lanes; l++)
            g3_lfsr[l] = 23'h7FFFFF;
        end
        vif.rxdata_valid  <= '0;
        vif.rxstart_block <= '0;
        vif.rxsync_header <= '0;
      end
      // The valid/elecidle guard above misses the rate-change cycle, and
      // rate_d1 would then already be Gen4 so the arm would keep the Gen3
      // LFSR for the rest of the link.
      if (peer_gen4 && (vif.rate == 3'd3) && (rate_d1 != 3'd3))
        g3_rx_arm = 1'b0;
      rate_d1 = vif.rate;
    end
  endtask
endclass : rivet_pipe_ltssm_peer
