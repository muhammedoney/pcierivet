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

## Phase 2 — Full Gen2 EP (sim) — current

Ordered ×4 gates ([verification.md](verification.md)):

| Slice | Content | Gate |
|-------|---------|------|
| **B1 MAC M3** | Partner narrower than port / link-width negotiate | UVM peer ×2 vs DUT ×4 |
| **B2 MAC M4** | Recovery.RcvrLock/Cfg/Idle + **Recovery.Speed** Gen1→Gen2 | `smoke_recovery_l0_gen2_x4`, `smoke_recovery_speed_gen2_x4` |
| **B3 Power / reset** | Hot Reset, Disabled; L0s/L1 if needed | Directed LTSSM |
| **B4 TL richer** | Mem64, IO, Msg; real RX buffer vs `rivet_tl_fc_stub` | UVM + BFM Class B stress |
| **B5 Interrupts** | MSI then MSI-X | UVM interrupt agent + BFM |
| **B6 AER / errors** | `cfg_err_*` / advisory / non-fatal | Directed PIPE/DLL inject |
| **B7 Companion depth** | CQ NP credits, RQ tag/seq, `pcie_tfc_*` | Functional companion checks |

Still **no Gen3/4 protocol**.

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
