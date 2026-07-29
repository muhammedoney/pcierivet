#!/usr/bin/env python3
# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
"""Generate docs/ltssm.xlsx — Rivet LTSSM states, transitions, ports and timers.

Stdlib only (no openpyxl): writes a minimal OOXML workbook with inline strings.
This script is the diffable source of truth; regenerate after editing the tables.

Spec values are cited from PCI Express Base Specification Rev 2.1 section numbers.
Verify against the original PDF before RTL sign-off; the local text extract used
during authoring is not redistributable.
"""

from __future__ import annotations

import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

PCLK_GEN1_MHZ = 125  # 2.5 GT/s, 16-bit/lane (training rate)
PCLK_GEN2_MHZ = 250  # 5.0 GT/s, 16-bit/lane (after Recovery.Speed)

# --------------------------------------------------------------------------
# Sheet: States
# --------------------------------------------------------------------------
STATES_HDR = [
    "Code", "State", "rivet_pkg enum", "Phase", "In RTL today",
    "PowerDown", "TxElecIdle", "TxDetectRx", "Data rate", "TX pattern",
    "Exit condition (EP / Upstream Port)", "Timeout", "Spec §",
]

STATES = [
    ["6'h00", "Detect.Quiet", "RIVET_LTSSM_DETECT_QUIET", "M1", "Yes (holds here)",
     "P1", "1", "0", "2.5 GT/s (rate=0)", "Electrical Idle",
     "Detect.Active after 12 ms timeout OR Electrical Idle broken on any Lane. "
     "LinkUp=0; directed_speed_change/upconfigure_capable/idle_to_rlock_transitioned reset. "
     "If entered at non-2.5 GT/s, stay >=1 ms while changing to 2.5 GT/s.",
     "12 ms", "4.2.6.1.1"],
    ["6'h01", "Detect.Active", "RIVET_LTSSM_DETECT_ACTIVE", "M1", "No",
     "P1", "1", "1", "2.5 GT/s (rate=0)", "Receiver Detection sequence",
     "Polling if a Receiver is detected on ALL un-configured Lanes; Detect.Quiet if none. "
     "If some but not all: wait 12 ms, repeat detection; Polling only if exactly the same "
     "Lanes detect, else Detect.Quiet.",
     "12 ms (partial retry)", "4.2.6.1.2"],
    ["6'h02", "Polling.Active", "RIVET_LTSSM_POLLING_ACTIVE", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "TS1, Link#=PAD, Lane#=PAD",
     "Polling.Configuration after >=1024 TS1 transmitted AND all Lanes that detected a "
     "Receiver receive 8 consecutive TS1(PAD, ComplianceRx=0) / TS1(PAD, Loopback=1) / "
     "TS2(PAD). Otherwise 24 ms timeout path (partial-Lane rules apply). "
     "TX must be at default Transmit Margin within 192 ns of entry.",
     "24 ms", "4.2.6.2.1"],
    ["6'h03", "Polling.Compliance", "RIVET_LTSSM_POLLING_COMPLIANCE", "Later", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "Compliance pattern",
     "Entered when Enter Compliance (Link Control 2 bit 4) = 1. Exit sends 8 EIOS and "
     "1-2 ms Electrical Idle while returning to 2.5 GT/s.",
     "-", "4.2.6.2.2"],
    ["6'h04", "Polling.Configuration", "RIVET_LTSSM_POLLING_CONFIGURATION", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "TS2, Link#=PAD, Lane#=PAD",
     "Configuration after 8 consecutive TS2(PAD) received on any Lane that detected a "
     "Receiver AND 16 TS2 transmitted after receiving one TS2. Receiver must invert "
     "polarity here if needed. Transmit Margin reset to 000b on entry.",
     "48 ms -> Detect", "4.2.6.2.3"],
    ["6'h05", "Configuration.Linkwidth.Start", "RIVET_LTSSM_CFG_LINKWIDTH_START", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "TS1, Link#=PAD, Lane#=PAD (active Lanes)",
     "If any Lane receives 2 consecutive TS1 with non-PAD Link# and PAD Lane#: select a "
     "single Link#, transmit TS1 with that Link# and PAD Lane# on those Lanes -> "
     "Configuration.Linkwidth.Accept. Left-over Lanes transmit PAD/PAD.",
     "24 ms -> Detect", "4.2.6.3.1.2"],
    ["6'h06", "Configuration.Linkwidth.Accept", "RIVET_LTSSM_CFG_LINKWIDTH_ACCEPT", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "TS1 with Link# and assigned Lane#",
     "On receiving 2 consecutive TS1 with non-PAD Lane numbers, assign own Lane numbers "
     "(reversed if necessary) -> Configuration.Lanenum.Wait.",
     "24 ms -> Detect", "4.2.6.3.2.2"],
    ["6'h07", "Configuration.Lanenum.Accept", "RIVET_LTSSM_CFG_LANENUM_ACCEPT", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "TS1 with Link#/Lane#",
     "Configuration.Complete if received Lane numbers are acceptable/consistent; "
     "otherwise re-assign Lane numbers -> Configuration.Lanenum.Wait.",
     "24 ms -> Detect", "4.2.6.3.3.2"],
    ["6'h08", "Configuration.Lanenum.Wait", "RIVET_LTSSM_CFG_LANENUM_WAIT", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "TS1 with Link#/Lane#",
     "Configuration.Lanenum.Accept when 2 consecutive TS1 are received with a non-PAD "
     "Lane number that CHANGED since first entering this substate.",
     "24 ms -> Detect", "4.2.6.3.4.2"],
    ["6'h09", "Configuration.Complete", "RIVET_LTSSM_CFG_COMPLETE", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "TS2 with matching Link#/Lane#",
     "Configuration.Idle after all transmitting Lanes receive 8 consecutive TS2 with "
     "matching non-PAD Link/Lane and identical data rate identifiers, AND 16 TS2 sent "
     "after receiving one. Record remote data rate ID (speed capability). Note N_FTS. "
     "Lane-to-Lane de-skew must be complete on exit. Optional scrambling disable.",
     "2 ms -> Detect", "4.2.6.3.5.2"],
    ["6'h0A", "Configuration.Idle", "RIVET_LTSSM_CFG_IDLE", "M1", "No",
     "P0", "0", "0", "2.5 GT/s (rate=0)", "Idle data Symbols",
     "LinkUp = 1 in THIS substate (not L0). L0 after 8 consecutive Symbol Times of Idle "
     "received on all configured Lanes AND 16 Idle Symbols sent after receiving one. "
     "Otherwise after min 2 ms: Recovery.RcvrLock if idle_to_rlock_transitioned=0 "
     "(then set it), else Detect.",
     "min 2 ms", "4.2.6.3.6"],
    ["6'h10", "L0", "RIVET_LTSSM_L0", "M1 (gate)", "No",
     "P0", "0", "0", "2.5 GT/s first, Gen2 only after Recovery.Speed",
     "TLP / DLLP + periodic SKP",
     "Normal operation. Speed change to 5.0 GT/s happens by entering Recovery, never "
     "during initial training (Polling.Speed is unreachable).",
     "-", "4.2.6.4 / 4.2.6.2.4"],
    ["6'h0B", "Recovery.RcvrLock", "RIVET_LTSSM_RECOVERY_RCVRLOCK", "M2 (minimal)", "No",
     "P0", "0", "0", "current rate", "TS1",
     "Re-acquire training; entered on RxValid loss, framing/decode errors, retrain, or "
     "Configuration.Idle timeout path.",
     "24 ms", "4.2.6.4.1"],
    ["6'h0C", "Recovery.Speed", "RIVET_LTSSM_RECOVERY_SPEED", "M4 / later", "No",
     "P1 during change", "1 (during change)", "0", "changes 2.5 <-> 5.0 GT/s",
     "EIOS then Electrical Idle, then new rate",
     "Only path to Gen2 operation. Requires PIPE rate change + PhyStatus handshake.",
     "-", "4.2.6.4.2"],
    ["6'h0D", "Recovery.RcvrCfg", "RIVET_LTSSM_RECOVERY_RCVRCFG", "M2 (minimal)", "No",
     "P0", "0", "0", "current rate", "TS2",
     "Re-confirm configuration after RcvrLock.",
     "48 ms", "4.2.6.4.3"],
    ["6'h0E", "Recovery.Idle", "RIVET_LTSSM_RECOVERY_IDLE", "M2 (minimal)", "No",
     "P0", "0", "0", "current rate", "Idle data Symbols",
     "Back to L0 on Idle exchange, else Detect / Configuration per rules.",
     "2 ms", "4.2.6.4.4"],
    ["6'h11-6'h16", "L0s substates (Tx/Rx)", "MISSING from enum", "Later", "No",
     "P0s", "1 (Tx side)", "0", "current rate", "EIOS to enter; FTS to exit",
     "ASPM L0s. PG213 code assignment in this range must be confirmed before use.",
     "N_FTS based", "4.2.6.5 / 4.2.6.6"],
    ["6'h17", "L1.Entry", "RIVET_LTSSM_L1_ENTRY", "Later", "No",
     "P1 (or P2)", "1", "0", "current rate", "EIOS then Electrical Idle",
     "ASPM/PM L1 entry handshake.",
     "-", "4.2.6.7"],
    ["6'h18", "L1.Idle", "RIVET_LTSSM_L1_IDLE", "Later", "No",
     "P1 (or P2)", "1", "0", "current rate", "Electrical Idle",
     "Exit to Recovery on Electrical Idle exit.",
     "-", "4.2.6.7"],
    ["6'h19-6'h1F", "L2 / reserved", "MISSING from enum", "Later", "No",
     "P2", "1", "0/1", "-", "Beacon / Electrical Idle",
     "L2/L3 and reserved codes. Confirm PG213 assignment before use.",
     "-", "4.2.6.8"],
    ["6'h20", "Disabled", "RIVET_LTSSM_DISABLED", "Later", "No",
     "P1", "1", "0", "-", "TS1 with Disable Link bit",
     "Entered when directed / on receiving 2 consecutive TS1 with Disable Link asserted.",
     "-", "4.2.6.9"],
    ["6'h21-6'h24", "Loopback.Entry/Active/Exit/ExitTimeout", "RIVET_LTSSM_LOOPBACK_*", "Later", "No",
     "P0", "0", "0", "-", "Master: TS1 w/ Loopback bit; Slave: retransmit",
     "Rivet names cover 4 substates; confirm exact PG213 code/name mapping "
     "(docs/mac.md lists 6'h21-6'h26).",
     "-", "4.2.6.10"],
    ["6'h27", "Hot_Reset", "RIVET_LTSSM_HOT_RESET", "Later", "No",
     "P0", "0", "0", "-", "TS1 with Hot Reset bit",
     "In-band reset propagation.",
     "2 ms", "4.2.6.11"],
    ["6'h28-6'h2B", "Recovery.Equalization Phase 0-3", "RIVET_LTSSM_RCVRY_EQ0..EQ3", "Gen3+ only", "No",
     "P0", "0", "0", "8.0 GT/s and above", "EQ TS1 with EC field",
     "NEVER entered while GEN=2. Keep in enum for forward compatibility only.",
     "-", "Gen3 spec"],
]

# --------------------------------------------------------------------------
# Sheet: Transitions (Gen2 EP M1 ladder)
# --------------------------------------------------------------------------
TRANS_HDR = ["#", "From", "To", "Condition", "Timer / count", "Priority", "Spec §"]

TRANSITIONS = [
    ["1", "(reset)", "Detect.Quiet", "Asynchronous reset deasserted (preset_n)", "-", "M0 done", "4.2.6.1.1"],
    ["2", "Detect.Quiet", "Detect.Active",
     "12 ms timeout OR Electrical Idle broken on any Lane (rxelecidle deasserts)",
     "12 ms", "M1", "4.2.6.1.1"],
    ["3", "Detect.Active", "Polling.Active",
     "Receiver detected on ALL un-configured Lanes (rxstatus=011 with phystatus)",
     "-", "M1", "4.2.6.1.2"],
    ["4", "Detect.Active", "Detect.Quiet",
     "No Receiver detected on any Lane", "-", "M1", "4.2.6.1.2"],
    ["5", "Detect.Active", "Detect.Active",
     "Partial detect: wait 12 ms and repeat the detection sequence",
     "12 ms", "M1 (x2/x4)", "4.2.6.1.2"],
    ["6", "Polling.Active", "Polling.Configuration",
     ">=1024 TS1 transmitted AND 8 consecutive qualifying TS received on all detected Lanes",
     "1024 TX / 8 RX", "M1", "4.2.6.2.1"],
    ["7", "Polling.Active", "Polling.Configuration",
     "24 ms timeout path: any detected Lane got 8 consecutive TS, >=1024 TS1 sent after "
     "first TS1 RX, and enough Lanes saw Electrical Idle exit",
     "24 ms", "M1", "4.2.6.2.1"],
    ["8", "Polling.Active", "Polling.Compliance",
     "Enter Compliance bit (Link Control 2 bit 4) = 1", "-", "Later", "4.2.6.2.1"],
    ["9", "Polling.Active", "Detect", "24 ms timeout without qualifying reception",
     "24 ms", "M1", "4.2.6.2.1"],
    ["10", "Polling.Configuration", "Configuration.Linkwidth.Start",
     "8 consecutive TS2(PAD) received AND 16 TS2 transmitted after receiving one",
     "8 RX / 16 TX", "M1", "4.2.6.2.3"],
    ["11", "Polling.Configuration", "Detect", "48 ms timeout", "48 ms", "M1", "4.2.6.2.3"],
    ["12", "Configuration.Linkwidth.Start", "Configuration.Linkwidth.Accept",
     "2 consecutive TS1 with non-PAD Link# and PAD Lane# received",
     "2 RX", "M1", "4.2.6.3.1.2"],
    ["13", "Configuration.Linkwidth.Accept", "Configuration.Lanenum.Wait",
     "2 consecutive TS1 with non-PAD Lane numbers received; own Lane numbers assigned",
     "2 RX", "M1", "4.2.6.3.2.2"],
    ["14", "Configuration.Lanenum.Wait", "Configuration.Lanenum.Accept",
     "2 consecutive TS1 with non-PAD Lane# that changed since entering Wait",
     "2 RX", "M1", "4.2.6.3.4.2"],
    ["15", "Configuration.Lanenum.Accept", "Configuration.Complete",
     "Received Lane numbers acceptable", "-", "M1", "4.2.6.3.3.2"],
    ["16", "Configuration.Lanenum.Accept", "Configuration.Lanenum.Wait",
     "Lane numbers not acceptable; re-assign", "-", "M1", "4.2.6.3.3.2"],
    ["17", "Configuration.Complete", "Configuration.Idle",
     "8 consecutive TS2 with matching non-PAD Link/Lane and identical rate IDs AND "
     "16 TS2 sent after receiving one; de-skew complete",
     "8 RX / 16 TX", "M1", "4.2.6.3.5.2"],
    ["18", "Configuration.Complete", "Detect", "2 ms timeout", "2 ms", "M1", "4.2.6.3.5.2"],
    ["19", "Configuration.Idle", "L0",
     "8 consecutive Symbol Times of Idle received on all configured Lanes AND 16 Idle "
     "Symbols sent after receiving one (LinkUp already 1 in Config.Idle)",
     "8 RX / 16 TX", "M1 gate", "4.2.6.3.6"],
    ["20", "Configuration.Idle", "Recovery.RcvrLock",
     "min 2 ms timeout with idle_to_rlock_transitioned = 0", "2 ms", "M2", "4.2.6.3.6"],
    ["21", "Configuration.Idle", "Detect",
     "min 2 ms timeout with idle_to_rlock_transitioned = 1", "2 ms", "M1", "4.2.6.3.6"],
    ["22", "L0", "Recovery.RcvrLock",
     "RxValid loss / decode or EB error / retrain / directed speed change",
     "-", "M2", "4.2.6.4"],
    ["23", "Recovery.RcvrLock", "Recovery.RcvrCfg", "TS1 exchange re-established",
     "24 ms", "M2", "4.2.6.4.1"],
    ["24", "Recovery.RcvrCfg", "Recovery.Idle", "TS2 exchange complete", "48 ms", "M2", "4.2.6.4.3"],
    ["25", "Recovery.Idle", "L0", "Idle exchange complete", "2 ms", "M2", "4.2.6.4.4"],
    ["26", "Recovery.RcvrLock", "Recovery.Speed",
     "Speed change negotiated (needs recorded remote rate ID from Config.Complete)",
     "-", "M4", "4.2.6.4.2"],
    ["27", "any", "Detect", "Fundamental / hot reset, link disable, or LTSSM timeout",
     "-", "Later", "4.2.6"],
]

# --------------------------------------------------------------------------
# Sheet: Inputs
# --------------------------------------------------------------------------
IN_HDR = ["Signal (proposed)", "Width", "Source", "In RTL today",
          "Needed by state(s)", "Purpose", "Priority"]

INPUTS = [
    ["pclk_i", "1", "controller (pclk)", "Yes", "all", "PIPE-domain clock", "-"],
    ["rst_ni", "1", "controller (preset_n)", "Yes", "all",
     "Async assert / active-low reset", "-"],
    ["phystatus_i", "LANES", "pipe adapter (PHY)", "NO",
     "Detect.Active, Recovery.Speed, power-state changes",
     "Completion handshake for receiver detect, rate change and power change",
     "M1 blocker"],
    ["phystatus_rst_i", "LANES", "pipe adapter (PG239)", "NO", "reset sequence",
     "PHY reset/ready done (AMD-specific)", "M1"],
    ["rxelecidle_i", "LANES", "pipe adapter", "NO",
     "Detect.Quiet, L0s/L1 exit, Recovery",
     "'Electrical Idle broken on any Lane' - the documented Detect.Quiet exit",
     "M1 blocker"],
    ["rx_detected_i", "LANES", "pipe adapter (decode rxstatus=011 at phystatus)", "NO",
     "Detect.Active", "Per-Lane receiver-present map", "M1 blocker"],
    ["rxvalid_i", "LANES", "pipe adapter", "NO", "L0, Recovery",
     "Symbol lock; loss triggers Recovery", "M2"],
    ["rxstatus_skp_add_i / _rem_i", "LANES each", "pipe adapter decode", "NO", "L0",
     "SKP added/removed (expected, not an error)", "M2"],
    ["rxstatus_decode_err_i", "LANES", "pipe adapter decode", "NO", "L0 -> Recovery",
     "8b/10b decode error (rxstatus=100)", "M2"],
    ["rxstatus_eb_over_i / _under_i", "LANES each", "pipe adapter decode", "NO",
     "L0 -> Recovery", "Elastic buffer overflow/underflow (101/110)", "M2"],
    ["rxstatus_disparity_err_i", "LANES", "pipe adapter decode", "NO", "L0 -> Recovery",
     "Disparity error (rxstatus=111)", "M2"],
    ["ts1_rx_valid_i / ts2_rx_valid_i", "LANES each", "os_rx",
     "Partial: 1 bit, tied 0", "Polling, Configuration",
     "Per-Lane TS reception (currently a single link-wide bit)", "M1 (widen)"],
    ["ts_rx_consec_cnt_i", "4+ bits per Lane", "os_rx", "NO",
     "Polling (8 consecutive), Configuration (2 consecutive), Config.Complete (8)",
     "Consecutive matching-TS counters - the actual exit criteria", "M1 blocker"],
    ["ts_rx_link_num_i", "8 x LANES", "os_rx", "NO", "Config.Linkwidth.*",
     "Received Link number", "M1"],
    ["ts_rx_lane_num_i", "8 x LANES", "os_rx", "NO", "Config.Lanenum.*",
     "Received Lane number", "M1"],
    ["ts_rx_link_is_pad_i / lane_is_pad_i", "LANES each", "os_rx", "NO",
     "Polling, Configuration", "PAD (K23.7) detection - drives most Config decisions",
     "M1"],
    ["ts_rx_lane_num_changed_i", "LANES", "os_rx", "NO", "Config.Lanenum.Wait",
     "Lane number differs from value seen on entry to Wait", "M1"],
    ["ts_rx_rate_id_i", "8 x LANES", "os_rx", "NO", "Config.Complete",
     "Remote advertised data rates; recorded for later speed change", "M2"],
    ["ts_rx_n_fts_i", "8 x LANES", "os_rx", "NO", "Config.Complete -> L0s",
     "N_FTS must be noted when leaving Config.Complete", "Later"],
    ["ts_rx_training_ctrl_i", "5 x LANES", "os_rx", "NO",
     "Loopback, Disabled, Hot_Reset, Compliance, scrambling",
     "Training Control bits (Symbol 5) incl. Disable Link / Loopback / Hot Reset",
     "Later"],
    ["polarity_inverted_i", "LANES", "os_rx", "NO", "Polling.Configuration",
     "Per-Lane polarity inversion needed", "M1"],
    ["idle_rx_consec_i", "count per Lane", "os_rx", "NO",
     "Config.Idle, Recovery.Idle",
     "Consecutive Idle data Symbol Times received (8 required)", "M1"],
    ["deskew_done_i", "1", "os_rx", "NO", "Config.Complete exit",
     "Lane-to-Lane de-skew complete (mandatory on exit)", "M1 (x2/x4)"],
    ["ts_tx_count_i", "11+ bits", "os_tx", "NO",
     "Polling.Active (1024 TS1), Polling.Config (16 TS2), Config.Complete (16 TS2)",
     "Transmitted ordered-set counters", "M1 blocker"],
    ["idle_tx_count_i", "5+ bits", "os_tx", "NO", "Config.Idle (16 Idle Symbols)",
     "Transmitted Idle Symbol counter", "M1"],
    ["os_tx_busy_i / done_i", "1 each", "os_tx", "NO", "all TX states",
     "Handshake that a requested OS burst is in flight / finished", "M1"],
    ["timer_expired_i", "1 (or per-timer)", "rivet_mac_timer (new)", "NO",
     "Detect.Quiet, Polling.*, Configuration.*, Recovery.*",
     "12 / 24 / 48 / 2 ms timeouts; sim-abbreviated by parameter", "M1 blocker"],
    ["cfg_link_training_enable_i", "1", "TL / config space", "NO", "leaving Detect",
     "PG213 cfg_link_training_enable gate", "M2"],
    ["cfg_link_disable_i", "1", "TL / config space", "NO", "Disabled",
     "Link Disable bit", "Later"],
    ["cfg_retrain_link_i", "1", "TL / config space", "NO", "Recovery entry",
     "Retrain Link bit (Link Control)", "Later"],
    ["cfg_enter_compliance_i", "1", "TL / config space", "NO", "Polling.Compliance",
     "Link Control 2 bit 4", "Later"],
    ["cfg_target_link_speed_i", "4", "TL / config space", "NO", "Recovery.Speed",
     "Target Link Speed (Link Control 2)", "M4"],
    ["cfg_select_deemphasis_i", "1", "TL / config space", "NO",
     "Detect.Quiet, Gen2 de-emphasis", "select_deemphasis variable / Link Control 2",
     "M4"],
    ["cfg_hot_reset_i", "1", "TL / config space", "NO", "Hot_Reset",
     "Secondary bus reset propagation", "Later"],
    ["dll_replay_timer_expired_i", "1", "DLL sideband", "In struct, not an LTSSM port",
     "Recovery policy", "REPLAY_NUM rollover hint", "M2"],
    ["dll_nak_storm_i", "1", "DLL sideband", "In struct, not an LTSSM port",
     "Recovery policy", "Excessive NAK indication", "M2"],
    ["dll_tx_idle_req_i", "1", "DLL sideband", "In struct, not an LTSSM port",
     "L0s / L1 entry", "DLL requests transmitter idle", "Later"],
]

# --------------------------------------------------------------------------
# Sheet: Outputs
# --------------------------------------------------------------------------
OUT_HDR = ["Signal", "Width", "Destination", "In RTL today", "Purpose", "Priority"]

OUTPUTS = [
    ["txdetectrx_o", "1", "pipe adapter -> PIPE", "Yes (0)",
     "Receiver detection request (with P1 + TxElecIdle)", "-"],
    ["txelecidle_o", "LANES", "pipe adapter -> PIPE", "Yes ('1)",
     "Electrical Idle control per Lane", "-"],
    ["powerdown_o", "2", "pipe adapter -> PIPE", "Yes (P1)",
     "P0 / P0s / P1 / P2 selection", "-"],
    ["rate_o", "3", "pipe adapter -> PIPE", "Yes - HARDCODED Gen2 (3'd1)",
     "MUST be 2.5 GT/s (0) for Detect..L0; Gen2 only after Recovery.Speed",
     "FIX in M1"],
    ["as_mac_in_detect_o", "1", "pipe adapter -> PG239", "Yes (1)",
     "AMD assist: MAC is in Detect", "-"],
    ["as_cdr_hold_req_o", "1", "pipe adapter -> PG239", "Yes (0)",
     "AMD assist: CDR hold request", "-"],
    ["as_mac_in_L0_o", "1", "pipe adapter -> PG239", "Yes (0)",
     "AMD assist: MAC in L0 (ASPM L0s path)", "-"],
    ["ltssm_state_o", "6", "rivet_mac -> ctrl", "Yes, but swallowed in ctrl",
     "PG213 cfg_ltssm_state[5:0]; must become a controller top-level port", "M1"],
    ["link_up_o", "1", "rivet_mac -> ctrl / DLL", "Yes (constant 0)",
     "LinkUp: spec sets it in Configuration.Idle, not on L0 entry", "M1"],
    ["os_req_o", "3", "os_tx", "Yes (NONE)",
     "Ordered-set type request (TS1/TS2/SKP/EIOS/FTS)", "-"],
    ["os_req_valid_o", "1", "os_tx", "Yes (0)", "Request valid", "-"],
    ["os_tx_link_num_o", "8", "os_tx", "NO", "Link number to transmit in TS", "M1"],
    ["os_tx_lane_num_o", "8 x LANES", "os_tx", "NO", "Per-Lane Lane number to transmit", "M1"],
    ["os_tx_link_pad_o / lane_pad_o", "1 / LANES", "os_tx", "NO",
     "Send PAD (K23.7) instead of a number", "M1"],
    ["os_tx_lane_mask_o", "LANES", "os_tx", "NO",
     "Which Lanes transmit the requested OS", "M1 (x2/x4)"],
    ["os_tx_rate_id_o", "8", "os_tx", "NO",
     "Advertised data rates in TS (Gen1+Gen2 even while training at 2.5 GT/s)", "M1"],
    ["os_tx_n_fts_o", "8", "os_tx", "NO", "N_FTS advertised in TS", "Later"],
    ["os_tx_training_ctrl_o", "5", "os_tx", "NO",
     "Hot Reset / Disable Link / Loopback / Disable Scrambling / Compliance Receive",
     "Later"],
    ["os_tx_count_req_o", "11", "os_tx", "NO",
     "How many OS to send (1024 TS1, 16 TS2, 16 Idle)", "M1"],
    ["rxpolarity_o", "LANES", "pipe adapter -> PIPE", "NO (adapter ties 0)",
     "Polarity inversion request; decided in Polling.Configuration", "M1"],
    ["txcompliance_o", "LANES", "pipe adapter -> PIPE", "NO (adapter ties 0)",
     "Compliance pattern control", "Later"],
    ["txdeemph_o", "1", "pipe adapter -> PIPE", "NO (adapter hardcodes 1)",
     "Gen2 de-emphasis selection (-3.5 / -6 dB); negotiated, not constant", "M4"],
    ["negotiated_width_o", "3", "DLL sideband / status", "In struct, always 0",
     "Configured Link width after Configuration", "M1"],
    ["negotiated_speed_o", "2", "DLL sideband / status", "In struct, always 0",
     "Current data rate (2.5 GT/s until Recovery.Speed)", "M1"],
    ["active_lane_mask_o", "LANES", "os_tx / os_rx / DLL", "NO",
     "Lanes that form the configured Link", "M1 (x2/x4)"],
    ["accept_dll_tlp_o", "1", "DLL sideband", "In struct, always 0",
     "Allow DLL traffic (L0 only)", "M2"],
    ["replay_freeze_o", "1", "DLL sideband", "In struct, always 1",
     "Freeze DLL replay while not in L0", "M2"],
    ["cfg_rx_pm_state_o", "2", "pipe adapter -> PG239", "NO (adapter ties 0)",
     "ASPM RX L0s substate reporting", "Later"],
]

# --------------------------------------------------------------------------
# Sheet: Timers
# --------------------------------------------------------------------------
TIMER_HDR = ["Timer / counter", "Spec value", "Cycles @125 MHz (2.5 GT/s)",
             "Cycles @250 MHz (5.0 GT/s)", "Used in", "Suggested parameter", "Spec §"]


def cycles(ms: float, mhz: int) -> str:
    return f"{int(ms * mhz * 1000):,}"


TIMERS = [
    ["Detect.Quiet timeout", "12 ms", cycles(12, PCLK_GEN1_MHZ), cycles(12, PCLK_GEN2_MHZ),
     "Detect.Quiet", "T_DETECT_QUIET_CYC", "4.2.6.1.1"],
    ["Detect.Active partial-detect wait", "12 ms", cycles(12, PCLK_GEN1_MHZ),
     cycles(12, PCLK_GEN2_MHZ), "Detect.Active", "T_DETECT_RETRY_CYC", "4.2.6.1.2"],
    ["Polling.Active timeout", "24 ms", cycles(24, PCLK_GEN1_MHZ), cycles(24, PCLK_GEN2_MHZ),
     "Polling.Active", "T_POLLING_ACTIVE_CYC", "4.2.6.2.1"],
    ["Polling.Configuration timeout", "48 ms", cycles(48, PCLK_GEN1_MHZ),
     cycles(48, PCLK_GEN2_MHZ), "Polling.Configuration", "T_POLLING_CFG_CYC", "4.2.6.2.3"],
    ["Configuration substate timeout", "24 ms", cycles(24, PCLK_GEN1_MHZ),
     cycles(24, PCLK_GEN2_MHZ), "Linkwidth.Start/Accept, Lanenum.Accept/Wait",
     "T_CONFIG_CYC", "4.2.6.3.1-4"],
    ["Configuration.Complete timeout", "2 ms", cycles(2, PCLK_GEN1_MHZ),
     cycles(2, PCLK_GEN2_MHZ), "Configuration.Complete", "T_CFG_COMPLETE_CYC",
     "4.2.6.3.5.2"],
    ["Configuration.Idle timeout", "min 2 ms", cycles(2, PCLK_GEN1_MHZ),
     cycles(2, PCLK_GEN2_MHZ), "Configuration.Idle", "T_CFG_IDLE_CYC", "4.2.6.3.6"],
    ["Recovery.RcvrLock timeout", "24 ms", cycles(24, PCLK_GEN1_MHZ),
     cycles(24, PCLK_GEN2_MHZ), "Recovery.RcvrLock", "T_RCVRLOCK_CYC", "4.2.6.4.1"],
    ["Recovery.RcvrCfg timeout", "48 ms", cycles(48, PCLK_GEN1_MHZ),
     cycles(48, PCLK_GEN2_MHZ), "Recovery.RcvrCfg", "T_RCVRCFG_CYC", "4.2.6.4.3"],
    ["Rate-change Electrical Idle", ">1 ms and <=2 ms", cycles(1, PCLK_GEN1_MHZ),
     cycles(2, PCLK_GEN2_MHZ), "Polling.Compliance exit, rate change",
     "T_RATE_EI_CYC", "4.2.6.2.2"],
    ["Non-2.5 GT/s entry to Detect.Quiet", ">=1 ms", cycles(1, PCLK_GEN1_MHZ),
     cycles(1, PCLK_GEN2_MHZ), "Detect.Quiet", "T_RATE_SETTLE_CYC", "4.2.6.1.1"],
    ["TX common mode settle (margin default)", "192 ns", "24", "48",
     "Polling.Active entry", "T_TXMARGIN_NS", "4.2.6.2.1"],
    ["TS1 transmitted before Polling.Config", "1024 TS1", "counter", "counter",
     "Polling.Active", "N_TS1_MIN", "4.2.6.2.1"],
    ["Consecutive TS required (Polling/Complete)", "8", "counter", "counter",
     "Polling.Active, Polling.Config, Config.Complete", "N_TS_CONSEC", "4.2.6.2.1/3, 4.2.6.3.5"],
    ["TS2 transmitted after first TS2 RX", "16", "counter", "counter",
     "Polling.Configuration, Config.Complete", "N_TS2_AFTER_RX", "4.2.6.2.3, 4.2.6.3.5"],
    ["Consecutive TS1 for Link/Lane number", "2", "counter", "counter",
     "Configuration.Linkwidth/Lanenum", "N_TS1_NUM_CONSEC", "4.2.6.3.1-4"],
    ["Idle Symbols received / transmitted", "8 RX / 16 TX", "counter", "counter",
     "Configuration.Idle, Recovery.Idle", "N_IDLE_RX / N_IDLE_TX", "4.2.6.3.6"],
]

# --------------------------------------------------------------------------
# Sheet: Findings
# --------------------------------------------------------------------------
FIND_HDR = ["#", "Severity", "Finding", "Where", "Action"]

FINDINGS = [
    ["1", "Bug", "rate_o is hardcoded to Gen2 (3'd1). The spec requires 2.5 GT/s for "
     "Detect through L0; Polling.Speed is unreachable and Gen2 is reached only via "
     "Recovery.Speed.", "rivet_ltssm.sv", "Drive rate=0 during training; add rate change in M4"],
    ["2", "Blocker", "LTSSM has no phystatus / rxelecidle / rx_detected inputs, so it "
     "cannot leave Detect for any real reason.",
     "rivet_ltssm.sv ports; rivet_mac_pipe_adapter.sv unused sink",
     "Fan PHY status out of the adapter into the LTSSM"],
    ["3", "Blocker", "No timers exist and no timer parameters are defined.",
     "rivet_ltssm.sv", "Add rivet_mac_timer with sim-abbreviated parameters"],
    ["4", "Blocker", "TS detection is a single link-wide bit with no counting; exits need "
     "per-Lane counts (8 consecutive RX, 1024/16 TX).",
     "rivet_mac_os_rx.sv, rivet_mac_os_tx.sv", "Widen to per-Lane + counters"],
    ["5", "Spec detail", "LinkUp = 1 is set in Configuration.Idle, not on L0 entry.",
     "rivet_ltssm.sv link_up_o", "Assert link_up in Config.Idle"],
    ["6", "Gap", "cfg_ltssm_state is not a port on rivet_pcie_ctrl or rivet_pcie; the "
     "internal state is consumed by an unused sink.",
     "rivet_pcie_ctrl.sv", "Expose as PG213-style status output"],
    ["7", "Gap", "Polling.Configuration must invert Receiver polarity, but rxpolarity is "
     "hardcoded to 0 in the adapter.",
     "rivet_mac_pipe_adapter.sv", "Drive from LTSSM / os_rx"],
    ["8", "Gap", "Configuration.Complete must record the remote data rate identifier and "
     "note N_FTS; neither is modelled.", "os_rx / rivet_ltssm.sv",
     "Add rate-ID and N_FTS capture (M2)"],
    ["9", "Gap", "Lane-to-Lane de-skew must be complete when leaving Config.Complete.",
     "rivet_mac_os_rx.sv", "Add deskew_done for x2/x4"],
    ["10", "Doc risk", "Enum has no L0s (6'h11-16) or L2 (6'h19-1F) codes, and Loopback "
     "naming may not match PG213 exactly.", "rivet_pkg.sv, docs/mac.md",
     "Confirm PG213 table before using those codes"],
    ["11", "Process", "Spec values here come from a local text extract of PCIe Base 2.1; "
     "the extract is not redistributable and OCR/layout may be imperfect.",
     "this workbook", "Verify against the original PDF before RTL sign-off"],
]

SHEETS = [
    ("States", STATES_HDR, STATES, [10, 30, 34, 12, 18, 11, 11, 11, 22, 34, 70, 18, 14]),
    ("Transitions", TRANS_HDR, TRANSITIONS, [5, 30, 30, 70, 16, 12, 14]),
    ("Inputs", IN_HDR, INPUTS, [34, 18, 34, 26, 40, 60, 14]),
    ("Outputs", OUT_HDR, OUTPUTS, [26, 12, 28, 30, 62, 14]),
    ("Timers", TIMER_HDR, TIMERS, [40, 20, 24, 24, 44, 26, 20]),
    ("Findings", FIND_HDR, FINDINGS, [5, 12, 78, 46, 46]),
]


def col_name(idx: int) -> str:
    name = ""
    idx += 1
    while idx:
        idx, rem = divmod(idx - 1, 26)
        name = chr(65 + rem) + name
    return name


def sheet_xml(header: list[str], rows: list[list[str]], widths: list[int]) -> str:
    out = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
           '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
           '<sheetViews><sheetView workbookViewId="0">',
           '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>',
           '</sheetView></sheetViews>',
           '<sheetFormatPr defaultRowHeight="15"/>']
    out.append("<cols>")
    for i, w in enumerate(widths, start=1):
        out.append(f'<col min="{i}" max="{i}" width="{w}" customWidth="1"/>')
    out.append("</cols><sheetData>")

    def row_xml(values: list[str], r: int, style: int) -> str:
        cells = []
        for c, val in enumerate(values):
            ref = f"{col_name(c)}{r}"
            cells.append(
                f'<c r="{ref}" s="{style}" t="inlineStr"><is><t xml:space="preserve">'
                f"{escape(str(val))}</t></is></c>"
            )
        return f'<row r="{r}">' + "".join(cells) + "</row>"

    out.append(row_xml(header, 1, 1))
    for n, row in enumerate(rows, start=2):
        out.append(row_xml(row, n, 2))
    out.append("</sheetData></worksheet>")
    return "".join(out)


STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FF1F3864"/><name val="Calibri"/></font>
</fonts>
<fills count="3">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="3">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
</cellXfs>
</styleSheet>"""


def main() -> None:
    out_path = Path(__file__).resolve().parents[1] / "docs" / "ltssm.xlsx"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    content_types = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
                     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
                     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
                     '<Default Extension="xml" ContentType="application/xml"/>',
                     '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
                     '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>']
    for i in range(1, len(SHEETS) + 1):
        content_types.append(
            f'<Override PartName="/xl/worksheets/sheet{i}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        )
    content_types.append("</Types>")

    root_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                 '<Relationship Id="rId1" '
                 'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
                 'Target="xl/workbook.xml"/></Relationships>')

    wb = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
          "<sheets>"]
    for i, (name, _, _, _) in enumerate(SHEETS, start=1):
        wb.append(f'<sheet name="{escape(name)}" sheetId="{i}" r:id="rId{i}"/>')
    wb.append("</sheets></workbook>")

    wb_rels = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
               '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">']
    for i in range(1, len(SHEETS) + 1):
        wb_rels.append(
            f'<Relationship Id="rId{i}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            f'Target="worksheets/sheet{i}.xml"/>'
        )
    wb_rels.append(
        f'<Relationship Id="rId{len(SHEETS) + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/></Relationships>'
    )

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", "".join(content_types))
        z.writestr("_rels/.rels", root_rels)
        z.writestr("xl/workbook.xml", "".join(wb))
        z.writestr("xl/_rels/workbook.xml.rels", "".join(wb_rels))
        z.writestr("xl/styles.xml", STYLES)
        for i, (_, hdr, rows, widths) in enumerate(SHEETS, start=1):
            z.writestr(f"xl/worksheets/sheet{i}.xml", sheet_xml(hdr, rows, widths))

    print(f"Wrote {out_path}")
    for name, hdr, rows, _ in SHEETS:
        print(f"  {name}: {len(rows)} rows x {len(hdr)} cols")


if __name__ == "__main__":
    main()
