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

Still **no Gen3/4 protocol**. Next: Phase 3 Gen2 port roles. Gen3 waits until that phase closes, because Recovery.Equalization needs a Downstream master and an Upstream slave.

## Phase 3 — Gen2 port roles (active)

Design: [gen2-port-roles](gen2-port-roles.md).
Plan: [2026-11-23-gen2-up-dp-rc](superpowers/plans/2026-11-23-gen2-up-dp-rc.md).

EP and USP share the Upstream port (Type 0, adopt Link# / Lane#). RC and DSP share the Downstream port (Type 1, offer Link#). RC alone sends config TLPs. Switch forwarding is out of this phase.

| Slice | Content | Gate |
|-------|---------|------|
| **3A LTSSM** | RC trains against an Upstream peer; Downstream originates Hot Reset and holds Disabled | `ltssm_l0_gen2_rc_x4`, `smoke_dp_hot_reset_gen2_x4`, `smoke_dp_disable_gen2_x4` |
| **3B Config** | Type 1 bridge header on RC/DSP; EP/USP image unchanged | `smoke_cfg_type1_gen2_rc_x4` |
| **3C Requester** | RC emits CfgWr1/CfgRd1, then one CfgRd0 | `smoke_rc_cfg_gen2_x4`, `smoke_cfg_type0_req_gen2_rc_x4` |
| **3D Aliases** | USP trains as Upstream + Type 0; DSP as Downstream + Type 1, no config master | `ltssm_l0_gen2_usp_x4`, `ltssm_l0_gen2_dsp_x4` |

Every current Gen2 EP smoke stays green after each slice.

## Phase 4 — EP Gen3

- After Phase 3. Both port roles already exist, so equalization can grow a master and a slave together.
- 128b/130b, Recovery.Equalization, PG239 EQ/assist
- Procedure (do not start while Phase 3 is open): [2026-11-23-gen3-ep](superpowers/plans/2026-11-23-gen3-ep.md)
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 5 — EP Gen4

- Gen4 rate / 64-bit US+ datapath; VCU118 constraints when HW available
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 6+ — Gen5

- Gen5 backlog. Multi-mode Gen2 is Phase 3, not this phase.

## Backlog — FPGA lab (explicitly deferred)

When a **VCU118** is available (not on the sim critical path):

1. Generate PG239 for **XCVU9P** Gen2 ×4; integrate `rivet_pcie` + constraints ([boards.md](boards.md), [hardware.md](hardware.md))
2. Board gates: `link_up`, BAR0 PIO, optional DMA/RQ
3. Until then: PHY stub + pad; BFM Stage-2 is the serial stand-in

## Other backlog

- ASIC microarchitecture (deferred)
