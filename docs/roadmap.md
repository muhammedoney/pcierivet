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

Still **no Gen3/4 protocol**. Next: Phase 3 when Gen2 link proof + backlog allow.

## Phase 3 — EP Gen3

- After Gen2 UVM + link proof (sim first; HW when board available)
- 128b/130b, Recovery.Equalization, PG239 EQ/assist
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 4 — EP Gen4

- Gen4 rate / 64-bit US+ datapath; VCU118 constraints when HW available
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 5+ — Gen5 / other modes

- Gen5 backlog; RC/USP/DSP via `MODE`

## Backlog — FPGA lab (explicitly deferred)

When a **VCU118** is available (not on the sim critical path):

1. Generate PG239 for **XCVU9P** Gen2 ×4; integrate `rivet_pcie` + constraints ([boards.md](boards.md), [hardware.md](hardware.md))
2. Board gates: `link_up`, BAR0 PIO, optional DMA/RQ
3. Until then: PHY stub + pad; BFM Stage-2 is the serial stand-in

## Other backlog

- ASIC microarchitecture (deferred)
