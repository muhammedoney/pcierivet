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
| Recovery.Speed downshift | `.\scripts\sim_questa.ps1 smoke_recovery_downshift_gen2_x4 4` | Gen1→Gen2, then second Recovery (peer bit 7) → L0 @ Gen1 |
| ASPM Tx_L0s | `.\scripts\sim_questa.ps1 smoke_aspm_l0s_gen2_x4 4` | Forced `aspm_l0s_req`: L0 → `0x15` (EI, P0s) → FTS → L0 |
| ASPM L1 | `.\scripts\sim_questa.ps1 smoke_aspm_l1_gen2_x4 4` | Forced `aspm_l1_req`: L0 → `0x17` → `0x18` (P1) → Detect → L0 |
| RxStatus error | `.\scripts\sim_questa.ps1 smoke_rxstatus_err_gen2_x4 4` | Peer RxStatus `3'b100` with RxValid high → Recovery → L0 |
| RQ MemWr ×2 | `.\scripts\sim_questa.ps1 smoke_tlp_rq_memwr_gen2_x2 2` | `RIVET_TB_LANES=2` |
| CQ↔CC ×2 | `.\scripts\sim_questa.ps1 smoke_tlp_cq_cc_gen2_x2 2` | `RIVET_TB_LANES=2` |
| M3 link-width ×2 | `.\scripts\sim_questa.ps1 smoke_linkwidth_peer_x2_dut_x4 4` | Peer ×2 vs DUT ×4 → L0 @ width=2 + NLW |
| M3 link-width ×1 | `.\scripts\sim_questa.ps1 smoke_linkwidth_peer_x1_dut_x4 4` | Peer ×1 vs DUT ×4 → L0 @ width=1 + NLW |
| M3 lane reverse ×4 | `.\scripts\sim_questa.ps1 smoke_link_reversed_x4 4` | Peer Lane# 3..0 → L0 @ width=4 + NLW |
| M3 lane reverse ×2 | `.\scripts\sim_questa.ps1 smoke_link_reversed_x2 2` | Peer Lane# 1..0 → L0 @ width=2 + NLW |
| Hot Reset | `.\scripts\sim_questa.ps1 smoke_hot_reset_gen2_x4 4` | TS Hot Reset → Detect → L0 |
| Disabled | `.\scripts\sim_questa.ps1 smoke_disabled_gen2_x4 4` | TS Disable Link → Detect → L0 |
| Mem64 CQ↔CC | `.\scripts\sim_questa.ps1 smoke_tlp_cq_cc_mem64_gen2_x4 4` | Peer MemRd64 → CQ → CC CplD |
| MSI | `.\scripts\sim_questa.ps1 smoke_msi_gen2_x4 4` | cfg MSI + `cfg_interrupt_msi_*` → MemWr |
| MSI-X | `.\scripts\sim_questa.ps1 smoke_msix_gen2_x4 4` | External-table `cfg_interrupt_msix_*` |
| AER | `.\scripts\sim_questa.ps1 smoke_aer_gen2_x4 4` | `cfg_err_*` → outs + Device Status sticky |
| Companion | `.\scripts\sim_questa.ps1 smoke_companion_gen2_x4 4` | CQ NP + RQ tag/seq + `pcie_tfc_*` |
| Perf posted write | `.\scripts\sim_questa.ps1 perf_rq_memwr_gen2_x4 4` | 16× RQ MemWr32, finite-credit peer |
| Perf payload sweep | `.\scripts\sim_questa.ps1 perf_rq_sweep_gen2_x4 4` | 8× MemWr32 at 1..1024 DW (4 B..4096 B); infinite credits and ACK |
| Perf read latency | `.\scripts\sim_questa.ps1 perf_rq_rc_lat_gen2_x4 4` | 8× RQ MemRd32 → peer CplD → RC; min/avg/max `user_clk` cycles |
| Perf inbound read | `.\scripts\sim_questa.ps1 perf_cq_cc_gen2_x4 4` | 8× peer MemRd32 → CC CplD; 4 payload bytes per completion |
| Perf credit stall | `.\scripts\sim_questa.ps1 perf_credit_stall_gen2_x4 4` | RQ MemRd while sampling `pcie_tfc_nph_av` |

The performance tests print one `PERF tag=...` line. `user_clk` in `rivet_tb_top` is 4 ns, so a full 64-bit beat is 2000 MB/s. The Gen2 x4 symbol data rate used as `pct_gen2x4` is 2000 MB/s. Read latency includes the PIPE peer. The payload sweep is Questa 2024.1 on 22 Nov 2026. The other four lines are the 21 Nov 2026 run, when `user_clk` was 8 ns, and were not re-run. Both used `vsim -suppress 7061`.

- `rq_memwr`: 64 bytes, 96 cycles, `rq_stall=0`, `mb_s=83.333`, `pct_gen2x4=4.167` (finite-credit peer, 8 ns user clock, not the payload curve)
- `rq_dw1` .. `rq_dw1024` (`perf_rq_sweep_gen2_x4`, 8 TLPs, infinite credits and ACK, 4 ns user clock): `mb_s` 250.000, 500.000, 800.000, 1122.807, 1347.368, 1590.062, 1747.440, 1865.209, 1930.254, 1964.508, 1982.095. `rq_stall` 0, 0, 0, 1, 7, 9, 13, 13, 13, 13, 13. `pct_gen2x4` 12.500, 25.000, 40.000, 56.140, 67.368, 79.503, 87.372, 93.260, 96.513, 98.225, 99.105. 0 errors
- `rq_rc_lat`: `lat_n=8`, `lat_min=363`, `lat_avg=458`, `lat_max=714` at `user_clk_ns=8.0`
- `cq_cc`: 8 CQ and 8 CC, 32 bytes, 2876 cycles, `mb_s=1.391` at `user_clk_ns=8.0`
- `credit_stall`: `rq_stall=0`, `credit_stall=0`, `tfc_nph_min=4` at `user_clk_ns=8.0`

`vsim` without `-suppress 7061` stops in vopt (`vopt-7061` on the sim-only `tlp_ram` initial, then `vopt-2064`). The finite-credit posted-write burst is 16 TLPs so it stays inside the peer's 32 posted header credits. The payload sweep uses a peer that advertises infinite credits and ACKs every TLP.

ASPM requests are tied to 0 in `rivet_mac`; the ASPM smokes drive `rivet_link_status_if.aspm_l0s_req` / `aspm_l1_req`, and `rivet_tb_top` `force`s them onto `dut.u_mac.aspm_*_req`.

Phase 2 Full Gen2 EP (sim) **closed** when the table above is green @ ×4.

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
