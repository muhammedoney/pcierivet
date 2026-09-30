# Verification

## Principle

**Verification before features.** Primary DUT is **`rivet_pcie_ctrl`** at PIPE (Questa UVM). Verilator is lint/elaborate; Vivado BFM is complementary. Active generation: **Gen2**. Gen3/4 deferred — [gen-evolution.md](gen-evolution.md).

Primary verified width: **Gen2 EP ×4** (`LANES=4`). ×1/×2 remain fast regression.

## Tracks

| Track | Tool | Role |
|-------|------|------|
| **Primary** | QuestaSim + UVM | Regression on **`rivet_pcie_ctrl`** at PIPE |
| **Fast smoke** | Verilator | Lint / elaborate controller |
| **Synth sanity** | Yosys | Open synth of controller stub |
| **Side-path** | Vivado BFM → Questa | Complementary; not a UVM substitute |

### BFM scripts

```powershell
.\scripts\sim_bfm_pg239.ps1 -Dut rivet   # Stage-2 dual link_up @ ×4
.\scripts\sim_bfm_pg213.ps1 -Dut rivet   # Class A+C (+ B WAIVE / D PASS|WAIVE)
```

---

## MVP Gen2 EP ×4 gate (`mvp-gen2-ep-x4`)

| Gate | Command / token | Status |
|------|-----------------|--------|
| Link L0 | `.\scripts\sim_questa.ps1 ltssm_l0_gen2_x4 4` | PASS |
| DLLP FC | `.\scripts\sim_questa.ps1 smoke_dllp_fc_gen2_x4 4` | PASS |
| cfg_mgmt @ L0 | `.\scripts\sim_questa.ps1 smoke_cfg_mgmt_gen2_x4 4` | PASS |
| RQ MemWr | `.\scripts\sim_questa.ps1 smoke_tlp_rq_memwr_gen2_x4 4` | PASS |
| CQ↔CC | `.\scripts\sim_questa.ps1 smoke_tlp_cq_cc_gen2_x4 4` | PASS |
| RQ↔RC | `.\scripts\sim_questa.ps1 smoke_tlp_rq_rc_gen2_x4 4` | PASS |
| PG213 Class A+C | `.\scripts\sim_bfm_pg213.ps1 -Dut rivet` → `Class A PASS` / `Class C PASS` | PASS |
| PG213 Class B | usrapp 1DW-only; MAC buf=160 + multi-DW PIO ready | **WAIVE** (UVM CQ/CC) |
| PG213 Class D | EP MemRd + RC | PASS (or WAIVE → UVM RQ↔RC) |
| PG239 Stage-2 | `.\scripts\sim_bfm_pg239.ps1 -Dut rivet` → `Test Completed Successfully (Rivet+PG239 link_up)` | PASS |

```powershell
.\scripts\sim_questa.ps1 ltssm_l0_gen2_x4 4
.\scripts\sim_questa.ps1 smoke_dllp_fc_gen2_x4 4
.\scripts\sim_questa.ps1 smoke_cfg_mgmt_gen2_x4 4
.\scripts\sim_questa.ps1 smoke_tlp_rq_memwr_gen2_x4 4
.\scripts\sim_questa.ps1 smoke_tlp_cq_cc_gen2_x4 4
.\scripts\sim_questa.ps1 smoke_tlp_rq_rc_gen2_x4 4
.\scripts\sim_bfm_pg213.ps1 -Dut rivet
.\scripts\sim_bfm_pg239.ps1 -Dut rivet
```

Annotated tag: **`mvp-gen2-ep-x4`**.

## Phase B UVM (post-MVP)

| Gate | Command | Notes |
|------|---------|-------|
| Recovery → L0 | `.\scripts\sim_questa.ps1 smoke_recovery_l0_gen2_x4 4` | RcvrLock/Cfg/Idle (no Speed) |
| Recovery.Speed | `.\scripts\sim_questa.ps1 smoke_recovery_speed_gen2_x4 4` | Gen1→Gen2 via mutual TS bit 7 |
| M3 link-width | `.\scripts\sim_questa.ps1 smoke_linkwidth_peer_x2_dut_x4 4` | Peer ×2 vs DUT ×4 → L0 @ width=2 |

---

## Phase 1 UVM build-out (historical)

| Step | Status |
|------|--------|
| PIPE / AXI / cfg_mgmt agents | Done |
| Smokes ×1/×2/×4 idle | Done |
| LTSSM L0 | Done (`ltssm_l0_gen2_x1/x2/x4`) |
| DLLP FC | Done (`smoke_dllp_fc_gen2_x1/x4`) |
| cfg_mgmt | Done (`smoke_cfg_mgmt_gen2_x1/x4`) |
| RQ MemWr / CQ↔CC / RQ↔RC | Done @ ×4 |
| Coverage | Done (grow bins with traffic) |

## QuestaSim (local)

Copy `scripts/local_paths.example.ps1` → `local_paths.ps1`, then run recipes above.

Uses built-in `-L mtiUvm` (match `UVM_HOME` to uvm-1.1d). Lane width is compile-time `+define+RIVET_TB_LANES=N`.

| Tool | Version |
|------|---------|
| QuestaSim | 2024.1 (local) |
| UVM | mtiUvm / 1.1d |
| Verilator | _TBD_ |
| Yosys | _TBD_ |

If Questa is not installed: note **UVM deferred — Questa not installed**.

## Spec policy

Do not commit PCIe / PIPE / PG213 / PG239 PDFs. Keep local copies under `specs/` (gitignored).

| Doc | Why |
|-----|-----|
| PG239 | PHY wrapper ports; AMD EQ/assist |
| PIPE **4.4.1** | Classic PIPE Gen1–Gen4 semantics |
| PG213 | User AXI-ST CQ/CC/RQ/RC ([audit](pg213-interface.md)) |
| PCIe Base (Gen2 focus) | LTSSM / DLLP / TLP |
