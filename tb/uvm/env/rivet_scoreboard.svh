// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Modes: idle smoke (default) | cfg_mgmt R/W | TLP CQ↔CC / RQ↔RC correlation.

class rivet_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rivet_scoreboard)

  uvm_analysis_imp_pipe #(rivet_pipe_item, rivet_scoreboard)       pipe_imp;
  uvm_analysis_imp_axi  #(rivet_axi_st_item, rivet_scoreboard)     axi_imp;
  uvm_analysis_imp_cfg  #(rivet_cfg_mgmt_item, rivet_scoreboard)   cfg_imp;
  uvm_analysis_imp_comp #(rivet_companion_item, rivet_scoreboard)  comp_imp;
  uvm_analysis_imp_dllp #(rivet_dllp_item, rivet_scoreboard)       dllp_imp;

  int unsigned pipe_sample_count, mac_idle_ok;
  int unsigned axi_sample_count, axi_idle_ok, axi_unexpected;
  int unsigned cfg_sample_count, cfg_idle_ok, cfg_unexpected;
  int unsigned cfg_txn_count, cfg_complete_ok;
  int unsigned axi_xfer_count, axi_pkt_count;
  int unsigned tlp_cq_np_outstanding, tlp_rq_np_outstanding;
  int unsigned tlp_cc_matched, tlp_rc_matched, tlp_mismatch;
  int unsigned comp_sample_count, comp_idle_ok, comp_unexpected;
  bit pipe_checked, axi_checked, cfg_checked, comp_checked;
  bit ltssm_l0_mode;
  bit cfg_mgmt_mode;
  bit tlp_mode;
  bit dllp_fc_mode;
  int unsigned dllp_dut_fc, dllp_peer_fc, dllp_dut_init1, dllp_dut_init2;
  int unsigned dllp_dut_update, dllp_crc_bad;

  // Per-channel packet assembly (accepted beats only).
  bit             pkt_active[string];
  logic [63:0]    pkt_beat0[string];
  int unsigned    pkt_beats[string];
  bit [7:0]       pkt_tag[string];
  bit [15:0]      pkt_req_id[string];
  bit [3:0]       pkt_req_type[string];

  // Outstanding NP keys: {requester_id, tag}
  bit outstanding_cq[bit [23:0]];
  bit outstanding_rq[bit [23:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(bit)::get(this, "", "ltssm_l0_mode", ltssm_l0_mode));
    void'(uvm_config_db#(bit)::get(this, "", "cfg_mgmt_mode", cfg_mgmt_mode));
    void'(uvm_config_db#(bit)::get(this, "", "tlp_mode", tlp_mode));
    void'(uvm_config_db#(bit)::get(this, "", "dllp_fc_mode", dllp_fc_mode));
    pipe_imp = new("pipe_imp", this);
    axi_imp  = new("axi_imp", this);
    cfg_imp  = new("cfg_imp", this);
    comp_imp = new("comp_imp", this);
    dllp_imp = new("dllp_imp", this);
  endfunction

  function void write_pipe(rivet_pipe_item t);
    pipe_sample_count++;
    if (ltssm_l0_mode || cfg_mgmt_mode || dllp_fc_mode) begin
      pipe_checked = 1;
      return;
    end
    if (pipe_sample_count < 5) return;
    if (t.txelecidle !== 1'b1)
      `uvm_error(get_type_name(), $sformatf("MAC txelecidle=%0b expected 1", t.txelecidle))
    else if (t.powerdown !== 2'b10)
      `uvm_error(get_type_name(), $sformatf("MAC powerdown=%0b expected P1", t.powerdown))
    else if (t.rate !== 3'd0)
      `uvm_error(get_type_name(), $sformatf("MAC rate=%0d expected Gen1 (train rate)", t.rate))
    else if (t.as_mac_in_detect !== 1'b1)
      `uvm_error(get_type_name(), $sformatf("as_mac_in_detect=%0b expected 1", t.as_mac_in_detect))
    else
      mac_idle_ok++;
    pipe_checked = 1;
  endfunction

  function void write_axi(rivet_axi_st_item t);
    bit accepted;
    axi_sample_count++;

    accepted = t.tvalid && ((t.tready & 4'hF) != 4'h0);

    if (tlp_mode || cfg_mgmt_mode || dllp_fc_mode) begin
      axi_checked = 1;
      if (accepted) begin
        axi_xfer_count++;
        tlp_observe_beat(t);
      end else if (!cfg_mgmt_mode && t.tvalid == 0)
        axi_idle_ok++;
      return;
    end

    if (axi_sample_count < 5) return;
    if (t.tvalid) begin
      axi_unexpected++;
      `uvm_error(get_type_name(), $sformatf("Unexpected AXI beat on %s", t.channel))
    end else
      axi_idle_ok++;
    axi_checked = 1;
  endfunction

  function void tlp_observe_beat(rivet_axi_st_item t);
    string ch;
    bit [23:0] key;
    logic [31:0] addr_u;
    logic [10:0] dcount;
    logic [3:0]  rtype;
    logic [7:0]  tag;
    logic [15:0] rid;

    ch = t.channel;
    if (!pkt_active.exists(ch) || !pkt_active[ch]) begin
      pkt_active[ch] = 1'b1;
      pkt_beats[ch]  = 0;
      pkt_beat0[ch]  = t.tdata;
    end
    pkt_beats[ch]++;

    if (pkt_beats[ch] == 2 && (ch == "cq" || ch == "rq")) begin
      rivet_axi_tlp_util::unpack_mem_desc_2beat(
        pkt_beat0[ch], t.tdata, addr_u, dcount, rtype, tag, rid);
      pkt_tag[ch]      = tag;
      pkt_req_id[ch]   = rid;
      pkt_req_type[ch] = rtype;
    end

    if (!t.tlast)
      return;

    axi_pkt_count++;
    pkt_active[ch] = 1'b0;

    if (ch == "cq") begin
      if (pkt_req_type[ch] == rivet_pkg::RIVET_CQ_REQ_MEMRD) begin
        key = {pkt_req_id[ch], pkt_tag[ch]};
        outstanding_cq[key] = 1'b1;
        tlp_cq_np_outstanding++;
      end
    end else if (ch == "cc") begin
      // Match on tag/req_id from CC DW1/DW2 when available; beat0 has DW0|DW1.
      rid = t.tdata[63:48]; // rough: if last is data beat, use stored — see below
      // For 2-beat CplD, last beat is {data,DW2}; tag in DW2[7:0], req in prior.
      // Use key from first completion beat stored at start.
      if (pkt_beats[ch] >= 2) begin
        tag = t.tdata[7:0];
        // requester_id was on beat0 DW1[31:16] — recover from beat0 store.
        rid = pkt_beat0[ch][63:48];
        key = {rid, tag};
        if (outstanding_cq.exists(key) && outstanding_cq[key]) begin
          outstanding_cq.delete(key);
          tlp_cq_np_outstanding--;
          tlp_cc_matched++;
        end else begin
          tlp_mismatch++;
          `uvm_error(get_type_name(),
            $sformatf("CC completion unmatched tag=0x%02h req=0x%04h", tag, rid))
        end
      end
    end else if (ch == "rq") begin
      if (pkt_req_type[ch] == rivet_pkg::RIVET_CQ_REQ_MEMRD) begin
        key = {pkt_req_id[ch], pkt_tag[ch]};
        outstanding_rq[key] = 1'b1;
        tlp_rq_np_outstanding++;
      end
      // MemWr posted: no completion expected.
    end else if (ch == "rc") begin
      if (pkt_beats[ch] >= 2) begin
        tag = t.tdata[7:0];
        rid = pkt_beat0[ch][63:48];
        key = {rid, tag};
        if (outstanding_rq.exists(key) && outstanding_rq[key]) begin
          outstanding_rq.delete(key);
          tlp_rq_np_outstanding--;
          tlp_rc_matched++;
        end else begin
          tlp_mismatch++;
          `uvm_error(get_type_name(),
            $sformatf("RC completion unmatched tag=0x%02h req=0x%04h", tag, rid))
        end
      end
    end
  endfunction

  function void write_cfg(rivet_cfg_mgmt_item t);
    cfg_sample_count++;

    if (cfg_mgmt_mode) begin
      cfg_checked = 1;
      if (t.txn_complete) begin
        cfg_txn_count++;
        cfg_complete_ok++;
      end
      return;
    end

    if (ltssm_l0_mode || dllp_fc_mode) begin
      cfg_checked = 1;
      return;
    end

    if (cfg_sample_count < 5) return;
    if (t.read || t.write) begin
      cfg_unexpected++;
      `uvm_error(get_type_name(), "Unexpected cfg_mgmt access during idle smoke")
    end else if (t.read_write_done) begin
      cfg_unexpected++;
      `uvm_error(get_type_name(), "cfg_mgmt done asserted without request")
    end else
      cfg_idle_ok++;
    cfg_checked = 1;
  endfunction

  function void write_comp(rivet_companion_item t);
    comp_sample_count++;
    if (comp_sample_count < 5) return;
    if (ltssm_l0_mode || cfg_mgmt_mode || tlp_mode || dllp_fc_mode) begin
      comp_checked = 1;
      return;
    end
    if (t.rq_seq_num_vld0 || t.rq_tag_vld0 || t.rq_tag_vld1 ||
        t.rq_tag_av !== '0 || t.tfc_nph_av !== '0 || t.tfc_npd_av !== '0) begin
      comp_unexpected++;
      `uvm_error(get_type_name(), "Companion RQ/tfc non-zero on idle smoke DUT")
    end else
      comp_idle_ok++;
    comp_checked = 1;
  endfunction


  function void write_dllp(rivet_dllp_item t);
    if (!t.crc_ok) begin
      dllp_crc_bad++;
      `uvm_error(get_type_name(), $sformatf("DLLP CRC fail: %s", t.convert2string()))
      return;
    end
    if (!t.is_fc) return;
    if (t.from_dut) begin
      dllp_dut_fc++;
      unique case (t.fc_kind)
        rivet_pkg::RIVET_DLLP_FC_INIT1_P,
        rivet_pkg::RIVET_DLLP_FC_INIT1_NP,
        rivet_pkg::RIVET_DLLP_FC_INIT1_CPL: dllp_dut_init1++;
        rivet_pkg::RIVET_DLLP_FC_INIT2_P,
        rivet_pkg::RIVET_DLLP_FC_INIT2_NP,
        rivet_pkg::RIVET_DLLP_FC_INIT2_CPL: dllp_dut_init2++;
        rivet_pkg::RIVET_DLLP_FC_UPDATE_P,
        rivet_pkg::RIVET_DLLP_FC_UPDATE_NP,
        rivet_pkg::RIVET_DLLP_FC_UPDATE_CPL: dllp_dut_update++;
        default: ;
      endcase
    end else
      dllp_peer_fc++;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    if (dllp_fc_mode) begin
      if (dllp_peer_fc == 0)
        `uvm_error(get_type_name(), "dllp_fc mode: no peer FC DLLPs published")
      if (dllp_dut_init1 == 0)
        `uvm_error(get_type_name(), "dllp_fc mode: DUT did not send InitFC1")
      if (dllp_dut_init2 == 0)
        `uvm_error(get_type_name(), "dllp_fc mode: DUT did not send InitFC2")
      if (dllp_crc_bad != 0)
        `uvm_error(get_type_name(), $sformatf("dllp_fc mode: CRC errors=%0d", dllp_crc_bad))
      `uvm_info(get_type_name(),
        $sformatf("dllp_fc OK peer=%0d dut_fc=%0d init1=%0d init2=%0d upd=%0d",
                  dllp_peer_fc, dllp_dut_fc, dllp_dut_init1, dllp_dut_init2,
                  dllp_dut_update), UVM_LOW)
      return;
    end

    if (cfg_mgmt_mode) begin
      if (cfg_complete_ok == 0)
        `uvm_error(get_type_name(), "cfg_mgmt mode: no completed transactions observed")
      else
        `uvm_info(get_type_name(),
          $sformatf("cfg_mgmt mode OK (%0d completed)", cfg_complete_ok), UVM_LOW)
      return;
    end

    if (tlp_mode) begin
      if (tlp_mismatch != 0)
        `uvm_error(get_type_name(), $sformatf("TLP mismatches=%0d", tlp_mismatch))
      if (tlp_cq_np_outstanding != 0)
        `uvm_error(get_type_name(),
          $sformatf("Unmatched CQ NP outstanding=%0d", tlp_cq_np_outstanding))
      if (tlp_rq_np_outstanding != 0)
        `uvm_error(get_type_name(),
          $sformatf("Unmatched RQ NP outstanding=%0d", tlp_rq_np_outstanding))
      `uvm_info(get_type_name(),
        $sformatf("TLP mode: pkts=%0d cc_match=%0d rc_match=%0d",
                  axi_pkt_count, tlp_cc_matched, tlp_rc_matched), UVM_LOW)
      return;
    end

    if (ltssm_l0_mode) begin
      `uvm_info(get_type_name(), "LTSSM L0 mode — idle PIPE checks skipped (vseq owns L0)", UVM_LOW)
      return;
    end

    if (!pipe_checked || mac_idle_ok == 0)
      `uvm_error(get_type_name(), "No successful PIPE idle samples")
    else
      `uvm_info(get_type_name(), $sformatf("PIPE stub idle OK (%0d)", mac_idle_ok), UVM_LOW)

    if (!axi_checked || axi_idle_ok == 0 || axi_unexpected != 0)
      `uvm_error(get_type_name(), "AXI-ST idle check failed")
    else
      `uvm_info(get_type_name(), $sformatf("AXI-ST stub idle OK (%0d)", axi_idle_ok), UVM_LOW)

    if (!cfg_checked || cfg_idle_ok == 0 || cfg_unexpected != 0)
      `uvm_error(get_type_name(), "cfg_mgmt idle check failed")
    else
      `uvm_info(get_type_name(), $sformatf("cfg_mgmt idle OK (%0d)", cfg_idle_ok), UVM_LOW)

    if (!comp_checked || comp_idle_ok == 0 || comp_unexpected != 0)
      `uvm_error(get_type_name(), "Companion idle check failed")
    else
      `uvm_info(get_type_name(), $sformatf("Companion stub OK (%0d)", comp_idle_ok), UVM_LOW)
  endfunction
endclass : rivet_scoreboard
