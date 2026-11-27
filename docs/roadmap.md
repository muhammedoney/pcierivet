# Rivet roadmap

**Default elaboration: Gen2** (`MODE=EP`, `GEN=2`, lanes ×1/×2/×4, 16-bit PIPE).  
**In simulation:** Gen3 and Gen4 x4 for EP, RC, USP, and DSP, including RC config, CplD, directed reset, a posted switch hop, and opt-in equalization. **Primary verified width: ×4.** Gen5 is not started. See [gen-evolution.md](gen-evolution.md).

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

Phase 3 closed on 2026-11-23. Phase 4 closed on 2026-11-24. Phase 5 closed on 2026-11-25. Phase 6 closed on 2026-11-25. Phase 7 closed on 2026-11-25. Phase 8 closed on 2026-11-25. Next: Phase 9 Gen5 backlog, not started.

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
- 64-bit US+ datapath. Opt-in preset search, one coefficient, and a margin nibble landed in Phase 8. Gen5 is not started.
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 6 — Gen3 port roles (closed 2026-11-25)

Design: [2026-11-25-gen3-usp-dsp-rc](superpowers/plans/2026-11-25-gen3-usp-dsp-rc.md).

USP is the same upstream equalization slave as EP. RC and DSP are the downstream master: EQ byte `8'h0A` and preset `8'h01`. The UVM peer's `peer_upstream` mode is the slave for RC and DSP. Each mode reaches L0 at 8 GT/s and posts one RQ MemWr32. Config TLPs at 8 GT/s and switch forwarding are not in this phase. Gen4 port roles are Phase 7.

| Slice | Content | Gate |
|-------|---------|------|
| **6A USP** | `MODE=2`, existing downstream peer | `smoke_gen3_l0_usp_x4`, `smoke_gen3_memwr_usp_x4` |
| **6B DSP** | Downstream EQ master, `peer_upstream` | `smoke_gen3_l0_dsp_x4`, `smoke_gen3_memwr_dsp_x4` |
| **6C RC** | Same master as DSP | `smoke_gen3_l0_rc_x4`, `smoke_gen3_memwr_rc_x4` |

## Phase 7 — Gen4 port roles (closed 2026-11-25)

Design: [2026-11-25-gen4-usp-dsp-rc](superpowers/plans/2026-11-25-gen4-usp-dsp-rc.md).

The Gen3 downstream master already transmits EQ byte `8'h0A` and preset `8'h01` at any PIPE rate, so this phase changes no LTSSM RTL. USP uses the existing Gen4 downstream peer. RC and DSP set `peer_upstream`. After Gen3 L0 that slave holds speed-change TS2 (rate byte `8'h9E`) until TxElecIdle, then repeats the equalization walk at 16 GT/s. Each mode reaches L0 at 16 GT/s and posts one RQ MemWr32.

| Slice | Content | Gate |
|-------|---------|------|
| **7A USP** | `MODE=2`, existing downstream peer | `smoke_gen4_l0_usp_x4`, `smoke_gen4_memwr_usp_x4` |
| **7B DSP** | `peer_upstream` through both equalizations | `smoke_gen4_l0_dsp_x4`, `smoke_gen4_memwr_dsp_x4` |
| **7C RC** | Same slave as DSP | `smoke_gen4_l0_rc_x4`, `smoke_gen4_memwr_rc_x4` |

## Phase 8 — Config, completions, reset, switch hop, equalization

Closed 2026-11-25. Gen3 first, then the same shapes at Gen4. Default elaboration is still `GEN=2`, 16-bit PIPE, `MODE=EP`. Preset search stays off unless the testbench forces `eq_search`.

| Slice | Content | Gate |
|-------|---------|------|
| **8A Config** | RC Type 0/1 at 8 GT/s and 16 GT/s. The 128-bit and 256-bit RQ packers emit the config header the 64-bit packer already emitted. | `smoke_gen3_cfg_rc_x4`, `smoke_gen4_cfg_rc_x4` |
| **8B CplD** | USP, DSP, and RC post one CplD after L0 | `smoke_gen3_cpld_{usp,dsp,rc}_x4`, `smoke_gen4_cpld_{usp,dsp,rc}_x4` |
| **8C Reset** | Hot Reset and Link Disable from L0. Endpoint reacts to TS byte 5. RC originates and the peer answers with a clean directed TS. | `smoke_hot_reset_gen3_x4`, `smoke_hot_reset_gen3_rc_x4`, `smoke_disabled_gen3_x4`, `smoke_disabled_gen3_rc_x4`, and the Gen4 twins |
| **8D Switch hop** | `rivet_sw_posted_fwd` rewrites a CQ MemWr into the RQ descriptor at 64, 128, and 256 bits and drops config. It is the fabric between two controllers, not a second trained link. | `tb/switch/rivet_sw_fwd_tb.sv` |
| **8E Equalization** | Opt-in EQ0 sends preset 0. With no phase-2 echo it moves to preset 1 and `8'h0A`. Adaptation done copies the new cursor into `pipe_txeq_coeff` with ctrl `2'b10`. A margin message whose high nibble is `4'h1` drives `pipe_txmargin`. | `smoke_eq_search_gen3_x4`, `smoke_eq_search_gen4_x4` |

## Phase 9+ — Gen5

- Gen5 backlog.

## Backlog — FPGA lab (explicitly deferred)

When a **VCU118** is available (not on the sim critical path):

The Gen4 EP x4 project scripts exist for VCU118 and VMK180 (`fpga/build_gen4_ep.ps1`, `create_project.cmd 4 ep`). Gen3 and the other port roles remain later work. This phase is not closed.

1. Program the VCU118 Gen2 image. The PHY is `rivet_pcie_phy_soft` on GTYE4, not PG239 ([boards.md](boards.md), [hardware.md](hardware.md))
2. Board gates: `link_up`, BAR0 PIO, optional DMA/RQ
3. Until the board is on the bench: the PCS loopback model is the PHY gate. Versal stays on PG345.

## Other backlog

- ASIC microarchitecture (deferred)
