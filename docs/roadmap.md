# Rivet roadmap

**Active generation: Gen2** (`MODE=EP`, `GEN=2`, lanes ×1/×2/×4).  
**Primary verified width: ×4.** Gen3/4/5 — see [gen-evolution.md](gen-evolution.md).

## Phase 0 — Bootstrap (done)

- Repo, Apache-2.0, docs, Cursor rules/skills
- Terminology: **`rivet_pcie_ctrl`** + **`rivet_pcie_phy_*`** + **`rivet_pcie`**
- PIPE + AXI-ST + `cfg_mgmt`; UVM skeleton; Verilator / Questa / Yosys hooks
- Vivado BFM side-path; target hardware **VCU118 (XCVU9P)** (lab **backlogged**)

## Phase 1 — MVP Gen2 EP ×4 (closed — tag `mvp-gen2-ep-x4`)

Shippable functional EP in sim:

- L0 + VC0 FC + Mem32 CQ/CC + RQ/RC + Type0 `cfg_mgmt` + PIO
- UVM gates @ ×4 (see [verification.md](verification.md) MVP table)
- BFM: PG213 Class A+C (+ Class B WAIVE / Class D PASS); PG239 Stage-2 dual `link_up`

FPGA / bitstream is **not** part of this gate.

## Phase 2 — Full Gen2 EP (sim) — closed

Ordered ×4 gates ([verification.md](verification.md)):

| Slice | Content | Gate |
|-------|---------|------|
| **B1 MAC M3** | Partner narrower than port / link-width negotiate; NLW; full lane reversal | Done — `smoke_linkwidth_peer_x{1,2}_dut_x4`, `smoke_link_reversed_x{2,4}` |
| **B2 MAC M4** | Recovery.RcvrLock/Cfg/Idle + **Recovery.Speed** Gen1→Gen2 | Done — `smoke_recovery_l0_gen2_x4`, `smoke_recovery_speed_gen2_x4` |
| **B3 Power / reset** | Hot Reset, Disabled; minimal ASPM L0s/L1 | Done — Hot Reset + Disabled @ ×4; minimal Tx_L0s / L1 (`smoke_aspm_l0s_gen2_x4`, `smoke_aspm_l1_gen2_x4`) |
| **B4 TL richer** | Mem64, IO, Msg; real RX buffer vs `rivet_tl_fc_stub` | Done — Mem64 CQ + IO/Msg route + finite CA buffer |
| **B5 Interrupts** | MSI then MSI-X | Done — `smoke_msi_gen2_x4`, `smoke_msix_gen2_x4` |
| **B6 AER / errors** | `cfg_err_*` / advisory / non-fatal | Done — `smoke_aer_gen2_x4` |
| **B7 Companion depth** | CQ NP credits, RQ tag/seq, `pcie_tfc_*` | Done — `smoke_companion_gen2_x4` |

Gen2 leftovers (closed): Recovery.Speed Gen2→Gen1 downshift (`smoke_recovery_downshift_gen2_x4`), minimal ASPM L0s/L1, RxStatus-error Recovery (`smoke_rxstatus_err_gen2_x4`), ×2 TLP clones (`smoke_tlp_rq_memwr_gen2_x2`, `smoke_tlp_cq_cc_gen2_x2`).

Phase 3 closed on 2026-11-23. Phase 4 closed on 2026-11-24. Phase 5 closed on 2026-11-25. Phase 6 closed on 2026-11-25. Next: Phase 7 Gen5 backlog, not started. Gen4 multi-mode is not started.

## Phase 3 — Gen2 port roles (closed 2026-11-23)

Design: [gen2-port-roles](gen2-port-roles.md).
Plan: [2026-11-23-gen2-up-dp-rc](superpowers/plans/2026-11-23-gen2-up-dp-rc.md).

EP and USP share the Upstream port (Type 0, adopt Link# / Lane#). RC and DSP share the Downstream port (Type 1, offer Link#). RC alone sends config TLPs. Switch forwarding is out of this phase.

| Slice | Content | Gate |
|-------|---------|------|
| **3A LTSSM** | RC and DSP train against the PG213 Endpoint model; Downstream originates Hot Reset and holds Disabled | `sim_bfm_pg213_rc.ps1` and `-Mode 3` → link_up, hot reset, link disable |
| **3B Config** | Type 1 bridge header on RC/DSP; a foreign bus completes as UR; EP/USP image unchanged | `smoke_cfg_type1_gen2_rc_x4`, `smoke_cfg_ur_gen2_rc_x4` |
| **3C Requester** | RC emits CfgWr1/CfgRd1/CfgWr0/CfgRd0; the PG213 Endpoint completes CfgRd0 with vendor `16'h10EE` | `smoke_rc_cfg_gen2_x4`, `smoke_cfg_type0_req_gen2_rc_x4`, `PASS: Rivet RC + PG213 EP cfg rd0` |
| **3D Aliases** | USP trains as Upstream + Type 0; DSP is Downstream + Type 1 and holds RQ `tready` low on a config descriptor | `ltssm_l0_gen2_usp_x4`, `ltssm_l0_gen2_dsp_x4`, `PASS: Rivet DSP + PG213 EP type1`, `PASS: Rivet DSP + PG213 EP rq stall` |

Every current Gen2 EP smoke stays green after each slice.

## Phase 4 — EP Gen3 (closed 2026-11-24)

- Endpoint x4 reaches L0 at 8 GT/s through Recovery.Speed and four equalization phases, then one MemWr32 and one CplD.
- Gates: `smoke_gen3_l0_x4`, `smoke_gen3_memwr_x4`, `smoke_gen3_cpld_x4` (see [verification.md](verification.md)).
- Procedure: [2026-11-23-gen3-gen4-ep](superpowers/plans/2026-11-23-gen3-gen4-ep.md) Tasks 1–6. The older Gen3-only file is superseded.
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 5 — EP Gen4 (closed 2026-11-25)

- Endpoint x4 reaches L0 at 16 GT/s through a second equalization, then one MemWr32 and one CplD.
- Gates: `smoke_gen4_l0_x4`, `smoke_gen4_memwr_x4`, `smoke_gen4_cpld_x4` (see [verification.md](verification.md)).
- Procedure: [2026-11-23-gen3-gen4-ep](superpowers/plans/2026-11-23-gen3-gen4-ep.md) Tasks 7–11.
- 64-bit US+ datapath. No message-bus margining. Gen5 is not started.
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 6 — Gen3 port roles (closed 2026-11-25)

Design: [2026-11-25-gen3-usp-dsp-rc](superpowers/plans/2026-11-25-gen3-usp-dsp-rc.md).

USP is the same upstream equalization slave as EP. RC and DSP are the downstream master: EQ byte `8'h0A` and preset `8'h01`. The UVM peer's `peer_upstream` mode is the slave for RC and DSP. Each mode reaches L0 at 8 GT/s and posts one RQ MemWr32. Gen4 multi-mode, config TLPs at 8 GT/s, and switch forwarding are not in this phase.

| Slice | Content | Gate |
|-------|---------|------|
| **6A USP** | `MODE=2`, existing downstream peer | `smoke_gen3_l0_usp_x4`, `smoke_gen3_memwr_usp_x4` |
| **6B DSP** | Downstream EQ master, `peer_upstream` | `smoke_gen3_l0_dsp_x4`, `smoke_gen3_memwr_dsp_x4` |
| **6C RC** | Same master as DSP | `smoke_gen3_l0_rc_x4`, `smoke_gen3_memwr_rc_x4` |

## Phase 7+ — Gen5

- Gen5 backlog. Gen4 for USP, DSP, and RC is not started.

## Backlog — FPGA lab (explicitly deferred)

When a **VCU118** is available (not on the sim critical path):

1. Generate PG239 for **XCVU9P** Gen2 ×4; integrate `rivet_pcie` + constraints ([boards.md](boards.md), [hardware.md](hardware.md))
2. Board gates: `link_up`, BAR0 PIO, optional DMA/RQ
3. Until then: PHY stub + pad; BFM Stage-2 is the serial stand-in

## Other backlog

- ASIC microarchitecture (deferred)
