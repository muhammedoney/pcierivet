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
  int unsigned   peer_lanes = 0;         // 0 = all DUT lanes; else narrower partner
  uvm_analysis_port #(rivet_dllp_item) dllp_ap;

  bit [31:0] tlp_memrd_addr = 32'h0000_0010;
  bit [7:0]  tlp_memrd_tag  = 8'h23;
  bit [15:0] tlp_memrd_rid  = 16'h0001;
  bit [7:0]  tlp_cpld_tag   = 8'h11;
  bit [15:0] tlp_cpld_rid   = 16'h0100;
  bit [31:0] tlp_cpld_data  = 32'hCAFE_BABE;

  localparam logic [7:0] SYM_COM    = 8'hBC;
  localparam logic [7:0] SYM_PAD    = 8'hF7;
  localparam logic [7:0] SYM_TS1_ID = 8'h4A;
  localparam logic [7:0] SYM_TS2_ID = 8'h45;
  localparam logic [7:0] PEER_LINK  = 8'h00;
  localparam logic [7:0] PEER_NFTS  = 8'h00;
  localparam logic [7:0] PEER_RATE  = 8'h06;

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
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
    void'(uvm_config_db#(int unsigned)::get(this, "", "peer_lanes", peer_lanes));
    if (peer_lanes == 0 || peer_lanes > lanes)
      peer_lanes = lanes;
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
    logic        dut_tx_ts1, dut_tx_ts2, dut_tx_k, dut_tx_data_only;
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
    bit          tlp_memrd_done;
    bit          tlp_cpld_done;
    bit          recovery_go;
    bit          recovery_pulse;
    logic [2:0]  last_rate;
    int unsigned rate_ack_left;
    logic [7:0]  peer_rate_byte;
    logic [7:0]  peer_train_byte;
    bit          hot_reset_go;
    bit          disable_go;
    bit          tc_inject_active;
    int unsigned tlp_sym;
    int unsigned tlp_nbytes;
    logic [8*32-1:0] tlp_frame;
    logic [63:0] tlp_b0, tlp_b1;
    logic [8:0]  tlp_sym9;

    if (!enable) return;

    peer_lfsr = new[lanes];
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
    tlp_sym = 0; tlp_nbytes = 0; tlp_frame = '0;
    recovery_go = 1'b0; recovery_pulse = 1'b0;
    last_rate = 3'd0; rate_ack_left = 0; peer_rate_byte = PEER_RATE;
    peer_train_byte = 8'h00; hot_reset_go = 1'b0; disable_go = 1'b0;
    tc_inject_active = 1'b0;
    for (l = 0; l < lanes; l++) peer_lfsr[l] = 16'hFFFF;

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

    forever begin
      @(posedge vif.pclk);

      dut_tx_ts1 = 1'b0;
      dut_tx_ts2 = 1'b0;
      dut_tx_k   = 1'b0;
      // Only wire-live peer lanes; DUT EI on unused lanes after width narrow.
      for (l = 0; l < peer_lanes; l++) begin
        if (vif.txelecidle[l]) continue;
        for (s = 0; s < 2; s++) begin
          if (vif.txdatak[2*l + s]) dut_tx_k = 1'b1;
          else begin
            if (vif.txdata[16*l + 8*s +: 8] == SYM_TS1_ID) dut_tx_ts1 = 1'b1;
            if (vif.txdata[16*l + 8*s +: 8] == SYM_TS2_ID) dut_tx_ts2 = 1'b1;
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
      // Advertise Gen2; set speed-change bit during Recovery TS when enabled.
      peer_rate_byte = PEER_RATE;
      if (speed_change_enable && send_os && !send_link_pad)
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
      end


      // FC DLLP inject in L0: stripe SDP+6+END like MAC (stream_idx = s*LANES+l).
      if (dllp_fc_enable && peer_active && (phase_q == P_IDLE) && !fc_sending) begin
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

      // One-shot TLP inject after InitFC2 (fc_idx >= 6), between FC gaps.
      if (peer_active && (phase_q == P_IDLE) && !fc_sending && !tlp_sending &&
          (fc_idx >= 6) && (fc_gap_left > 4)) begin
        if (tlp_memrd_enable && !tlp_memrd_done) begin
          bit go_m;
          go_m = 1'b0;
          void'(uvm_config_db#(bit)::get(null, "*", "peer_memrd_go", go_m));
          if (go_m) begin
            if (tlp_memrd64_enable)
              rivet_axi_tlp_util::pack_memrd64_tl_beats(
                  {32'h0, tlp_memrd_addr}, tlp_memrd_tag, tlp_memrd_rid, 4'hF,
                  tlp_b0, tlp_b1);
            else
              rivet_axi_tlp_util::pack_memrd32_tl_beats(
                  tlp_memrd_addr, tlp_memrd_tag, tlp_memrd_rid, 4'hF, tlp_b0, tlp_b1);
            rivet_axi_tlp_util::pack_dll_tlp_frame(
                12'd0, tlp_b0, tlp_b1, 16, tlp_frame, tlp_nbytes);
            tlp_sym = 0; tlp_sending = 1'b1; tlp_memrd_done = 1'b1;
            uvm_config_db#(bit)::set(null, "*", "peer_tlp_memrd_done", 1'b1);
          end
        end else if (tlp_cpld_enable && !tlp_cpld_done) begin
          bit go_c;
          go_c = 1'b0;
          void'(uvm_config_db#(bit)::get(null, "*", "peer_cpld_go", go_c));
          if (go_c) begin
            rivet_axi_tlp_util::pack_cpld_tl_beats(
                tlp_cpld_rid, tlp_cpld_tag, tlp_cpld_data, tlp_b0, tlp_b1);
            rivet_axi_tlp_util::pack_dll_tlp_frame(
                12'd0, tlp_b0, tlp_b1, 16, tlp_frame, tlp_nbytes);
            tlp_sym = 0; tlp_sending = 1'b1; tlp_cpld_done = 1'b1;
            uvm_config_db#(bit)::set(null, "*", "peer_tlp_cpld_done", 1'b1);
          end
        end
      end

      vif.rxdata  <= '0;
      vif.rxdatak <= '0;
      if (peer_active) begin
        if (tlp_sending) begin
          for (l = 0; l < lanes; l++) begin
            automatic logic [15:0] lfsr = peer_lfsr[l];
            for (s = 0; s < 2; s++) begin
              automatic int unsigned stream_idx = tlp_sym + s * lanes + l;
              automatic int unsigned framed_len = tlp_nbytes + 2;
              if (stream_idx < framed_len)
                tlp_sym9 = rivet_axi_tlp_util::framed_tlp_sym(
                    stream_idx, tlp_frame, tlp_nbytes);
              else
                tlp_sym9 = {1'b0, 8'h00};
              peer_tmp = tlp_sym9;
              peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8], 1'b0, lfsr);
              vif.rxdata[16*l + 8*s +: 8] <= peer_out;
              vif.rxdatak[2*l + s]        <= peer_tmp[8];
            end
            peer_lfsr[l] = lfsr;
          end
          tlp_sym += lanes * 2;
          if (tlp_sym >= (tlp_nbytes + 2))
            tlp_sending = 1'b0;
        end else if (fc_sending) begin
          for (l = 0; l < lanes; l++) begin
            automatic logic [15:0] lfsr = peer_lfsr[l];
            for (s = 0; s < 2; s++) begin
              automatic int unsigned stream_idx = fc_sym + s * lanes + l;
              if (stream_idx < 8) begin
                fc_sym9  = rivet_dllp_util::framed_sym(stream_idx, fc_wire);
                peer_tmp = fc_sym9;
              end else
                peer_tmp = {1'b0, 8'h00};
              peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8], 1'b0, lfsr);
              vif.rxdata[16*l + 8*s +: 8] <= peer_out;
              vif.rxdatak[2*l + s]        <= peer_tmp[8];
            end
            peer_lfsr[l] = lfsr;
          end
          fc_sym += lanes * 2;
          if (fc_sym >= 8) begin
            fc_sending = 1'b0;
            if (fc_idx < 5) begin
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
            for (s = 0; s < 2; s++) begin
              peer_tmp = send_os ? peer_sym(4'(peer_ptr + 5'(s)), send_ts2,
                                            send_link_pad || (l >= peer_lanes),
                                            send_lane_pad || (l >= peer_lanes), 8'(l),
                                            peer_rate_byte, peer_train_byte)
                                 : {1'b0, 8'h00};
              peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8],
                                       send_os && !peer_tmp[8], lfsr);
              vif.rxdata[16*l + 8*s +: 8] <= peer_out;
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

      if (vif.txelecidle == '1) begin
        phase_q    = P_TS1_PAD;
        phase_sets = '0;
        peer_ptr   = '0;
        idle_seen  = '0;
        tc_inject_active = 1'b0;
        for (l = 0; l < lanes; l++) peer_lfsr[l] = 16'hFFFF;
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
            if (dut_tx_ts1 || dut_tx_ts2) begin
              phase_q    = dut_tx_ts2 ? P_TS2_CFG : P_TS1_LANE;
              phase_sets = '0;
              peer_ptr   = '0;
              idle_seen  = '0;
            end
          end
          default: ;
        endcase
      end
    end
  endtask
endclass : rivet_pipe_ltssm_peer
