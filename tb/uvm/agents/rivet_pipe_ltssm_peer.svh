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
  uvm_analysis_port #(rivet_dllp_item) dllp_ap;

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
    void'(uvm_config_db#(int unsigned)::get(this, "", "lanes", lanes));
    if (!enable) return;
    if (!uvm_config_db#(rivet_pipe_vif)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "rivet_pipe_vif not set for LTSSM peer")
  endfunction

  function automatic logic [8:0] peer_sym(
      input logic [3:0] idx,
      input bit         ts2,
      input bit         link_pad,
      input bit         lane_pad,
      input logic [7:0] lane
  );
    case (idx)
      4'd0:    return {1'b1, SYM_COM};
      4'd1:    return link_pad ? {1'b1, SYM_PAD} : {1'b0, PEER_LINK};
      4'd2:    return lane_pad ? {1'b1, SYM_PAD} : {1'b0, lane};
      4'd3:    return {1'b0, PEER_NFTS};
      4'd4:    return {1'b0, PEER_RATE};
      4'd5:    return {1'b0, 8'h00};
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
      for (l = 0; l < lanes; l++) begin
        for (s = 0; s < 2; s++) begin
          if (vif.txdatak[2*l + s]) dut_tx_k = 1'b1;
          else begin
            if (vif.txdata[16*l + 8*s +: 8] == SYM_TS1_ID) dut_tx_ts1 = 1'b1;
            if (vif.txdata[16*l + 8*s +: 8] == SYM_TS2_ID) dut_tx_ts2 = 1'b1;
          end
        end
      end
      dut_tx_data_only = !dut_tx_k && !dut_tx_ts1 && !dut_tx_ts2 &&
                         (vif.txelecidle == '0);

      send_ts2      = (phase_q == P_TS2_PAD) || (phase_q == P_TS2_CFG);
      send_link_pad = (phase_q == P_TS1_PAD) || (phase_q == P_TS2_PAD);
      send_lane_pad = (phase_q != P_TS1_LANE) && (phase_q != P_TS2_CFG);
      send_os       = peer_active && (phase_q != P_IDLE);

      vif.phystatus <= '0;
      vif.rxstatus  <= '0;

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
        vif.rxvalid    <= '1;
        vif.rxelecidle <= '0;
      end


      if (dllp_fc_enable && (lanes == 1) && peer_active && (phase_q == P_IDLE) && !fc_sending) begin
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
      end

      vif.rxdata  <= '0;
      vif.rxdatak <= '0;
      if (peer_active) begin
        for (l = 0; l < lanes; l++) begin
          automatic logic [15:0] lfsr = peer_lfsr[l];
          for (s = 0; s < 2; s++) begin
            if (fc_sending && (l == 0) && (lanes == 1)) begin
              fc_sym9  = rivet_dllp_util::framed_sym(fc_sym, fc_wire);
              peer_tmp = fc_sym9;
              peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8], 1'b0, lfsr);
              vif.rxdata[16*l + 8*s +: 8] <= peer_out;
              vif.rxdatak[2*l + s]        <= peer_tmp[8];
              fc_sym++;
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
              peer_tmp = send_os ? peer_sym(4'(peer_ptr + 5'(s)), send_ts2,
                                            send_link_pad, send_lane_pad, 8'(l))
                                 : {1'b0, 8'h00};
              peer_out = peer_scramble(peer_tmp[7:0], peer_tmp[8],
                                       send_os && !peer_tmp[8], lfsr);
              vif.rxdata[16*l + 8*s +: 8] <= peer_out;
              vif.rxdatak[2*l + s]        <= peer_tmp[8];
            end
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

      if (vif.txelecidle == '1) begin
        phase_q    = P_TS1_PAD;
        phase_sets = '0;
        peer_ptr   = '0;
        idle_seen  = '0;
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
          default: ;
        endcase
      end
    end
  endtask
endclass : rivet_pipe_ltssm_peer
