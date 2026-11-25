# Verification

## Principle

**Verification before features.** Primary DUT is **`rivet_pcie_ctrl`** at PIPE (Questa UVM). Verilator is lint/elaborate; Vivado BFM is complementary. Active generation: **Gen2**, with EP/RC/USP/DSP closed. Next is EP Gen3 — [gen-evolution.md](gen-evolution.md).

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
| Perf Gen3 payload sweep | `.\scripts\sim_questa.ps1 perf_rq_sweep_gen3_x4 4 0` | Same sizes after Gen3 L0; 24 Nov 2026 |
| Perf MemWr64 sweep | `.\scripts\sim_questa.ps1 perf_rq_memwr64_gen2_x4 4` | Same sizes, `addr[63:32]=1` (TLP type 0x60) |
| Perf MemRd sweep | `.\scripts\sim_questa.ps1 perf_rq_memrd_gen2_x4 4` | 8× MemRd32 then 8× MemRd64 at 1..1024 DW; CplD payload on RC |
| Perf read latency | `.\scripts\sim_questa.ps1 perf_rq_rc_lat_gen2_x4 4` | 8× RQ MemRd32 → peer CplD → RC; min/avg/max `user_clk` cycles |
| Perf inbound read | `.\scripts\sim_questa.ps1 perf_cq_cc_gen2_x4 4` | 8× peer MemRd32 → CC CplD; 4 payload bytes per completion |
| Perf credit stall | `.\scripts\sim_questa.ps1 perf_credit_stall_gen2_x4 4` | RQ MemRd while sampling `pcie_tfc_nph_av` |

The performance tests print one `PERF tag=...` line. `user_clk` in `rivet_tb_top` is 4 ns, so a full 64-bit beat is 2000 MB/s. The Gen2 x4 symbol data rate used as `pct_gen2x4` is 2000 MB/s. Read latency includes the PIPE peer. The posted-write sweeps are Questa 2024.1 on 22 Nov 2026. The MemRd sweep is 23 Nov 2026. `rq_rc_lat`, `cq_cc`, and `credit_stall` are the 21 Nov 2026 run, when `user_clk` was 8 ns, and were not re-run. All of them used `vsim -suppress 7061`.

- `rq_memwr`: 64 bytes, 96 cycles, `rq_stall=0`, `mb_s=83.333`, `pct_gen2x4=4.167` (finite-credit peer, 8 ns user clock, not the payload curve)
- `rq_dw1` .. `rq_dw1024` (`perf_rq_sweep_gen2_x4`, 8 TLPs, infinite credits and ACK, 4 ns user clock): `mb_s` 250.000, 500.000, 800.000, 1122.807, 1333.333, 1570.552, 1723.906, 1851.718, 1923.005, 1959.809, 1979.700. `rq_stall` 0, 0, 0, 1, 8, 11, 17, 17, 17, 18, 18. `pct_gen2x4` 12.500, 25.000, 40.000, 56.140, 66.667, 78.528, 86.195, 92.586, 96.150, 97.990, 98.985. 0 errors
- `rq64_dw1` .. `rq64_dw1024` (`perf_rq_memwr64_gen2_x4`): same printed `mb_s` as MemWr32 except `rq64_dw16` = 1347.368 (`cycles=95`, `rq_stall=7`, `pct_gen2x4=67.368`). 4096-byte point 1979.700. 0 errors
- `rq_dw1` .. `rq_dw1024` (`perf_rq_sweep_gen3_x4`, 8 TLPs after Gen3 L0, 4 ns user clock, 24 Nov 2026): `mb_s` 250.000, 500.000, 800.000, 1084.746, 1280.000, 1488.372, 1651.613, 1815.603, 1896.296, 1943.074, 1967.339. `cycles` 32, 32, 40, 59, 100, 172, 310, 564, 1080, 2108, 4164. `rq_stall` 0, 0, 0, 3, 12, 20, 30, 28, 32, 36, 44. `pct_gen2x4` 12.500, 25.000, 40.000, 54.237, 64.000, 74.419, 82.581, 90.780, 94.815, 97.154, 98.367. 0 errors
- `rd_dw1` .. `rd_dw1024` and `rd64_dw1` .. `rd64_dw1024` (`perf_rq_memrd_gen2_x4`, 8 TLPs, infinite credits, 4 ns user clock, 23 Nov 2026): MemRd32 and MemRd64 printed the same `mb_s` 77.670, 146.789, 275.862, 444.444, 695.652, 973.384, 1207.547, 1378.197, 1480.839, 1538.115, 1568.447. `cycles` 103, 109, 116, 144, 184, 263, 424, 743, 1383, 2663, 5223. `rq_stall=0`, `credit_stall=0`, `tfc_nph_min=15`. 0 errors
- `rq_rc_lat`: `lat_n=8`, `lat_min=363`, `lat_avg=458`, `lat_max=714` at `user_clk_ns=8.0`
- `cq_cc`: 8 CQ and 8 CC, 32 bytes, 2876 cycles, `mb_s=1.391` at `user_clk_ns=8.0`
- `credit_stall`: `rq_stall=0`, `credit_stall=0`, `tfc_nph_min=4` at `user_clk_ns=8.0`

`vsim` without `-suppress 7061` stops in vopt (`vopt-7061` on the sim-only `tlp_ram` initial, then `vopt-2064`). The finite-credit posted-write burst is 16 TLPs so it stays inside the peer's 32 posted header credits. The payload sweep uses a peer that advertises infinite credits and ACKs every TLP.

ASPM requests are tied to 0 in `rivet_mac`; the ASPM smokes drive `rivet_link_status_if.aspm_l0s_req` / `aspm_l1_req`, and `rivet_tb_top` `force`s them onto `dut.u_mac.aspm_*_req`.

Phase 2 Full Gen2 EP (sim) **closed** when the table above is green @ ×4.

## Phase 3 Gen2 port roles (closed 2026-11-23)

The link partner for RC and DSP is the PG213 Endpoint model. UVM mode is the third argument of `sim_questa.ps1` (`RIVET_TB_MODE`).

| Gate | Command / token | Status |
|------|-----------------|--------|
| RC link, hot reset, disable | `.\scripts\sim_bfm_pg213_rc.ps1` | PASS |
| RC CfgRd0 vendor `16'h10EE` | same log, `PASS: Rivet RC + PG213 EP cfg rd0` | PASS |
| Type 1 header | `.\scripts\sim_questa.ps1 smoke_cfg_type1_gen2_rc_x4 4 1` | PASS |
| Config UR | `.\scripts\sim_questa.ps1 smoke_cfg_ur_gen2_rc_x4 4 1` | PASS |
| RC config wire bytes | `.\scripts\sim_questa.ps1 smoke_rc_cfg_gen2_x4 4 1` | PASS |
| Type 0 request alias | `.\scripts\sim_questa.ps1 smoke_cfg_type0_req_gen2_rc_x4 4 1` | PASS |
| USP L0 + Type 0 | `.\scripts\sim_questa.ps1 ltssm_l0_gen2_usp_x4 4 2` | PASS |
| DSP Type 1 + RQ stall | `.\scripts\sim_questa.ps1 ltssm_l0_gen2_dsp_x4 4 3` | PASS |
| DSP link, header, stall | `.\scripts\sim_bfm_pg213_rc.ps1 -Mode 3` | PASS |

## Phase 4 EP Gen3 (closed 2026-11-24)

Endpoint x4, `GEN=3`, 32-bit pipe. Each row printed `UVM_ERROR : 0` on that date. After the receive path accepted all four symbol times, `smoke_gen3_memwr_x4` and `smoke_gen3_cpld_x4` were run again and both printed `UVM_ERROR : 0` and `UVM_FATAL : 0`. The completion smoke printed `rc_match=1`.

A Gen3 TLP is STP, a 2-byte little-endian DLL length, then the DLL bytes, with no END token, in all four symbol times. The receive gearbox walks those four symbol times and writes two 8-byte RAM words when a cycle carries more than eight frame bytes. Playback toward the DLL is still eight bytes per cycle. The peer sends and counts the same length-prefixed frame, so a payload byte equal to STP, SDP, or END is not a token.

| Gate | Command | Status |
|------|---------|--------|
| L0 at 8 GT/s | `.\scripts\sim_questa.ps1 smoke_gen3_l0_x4 4 0` | PASS |
| RQ MemWr32 | `.\scripts\sim_questa.ps1 smoke_gen3_memwr_x4 4 0` | PASS |
| RQ MemRd + CplD | `.\scripts\sim_questa.ps1 smoke_gen3_cpld_x4 4 0` | PASS |

## Phase 5 EP Gen4 (closed 2026-11-25)

Endpoint x4, `GEN=4`, 64-bit pipe. Each row printed `UVM_ERROR : 0` on that date. `smoke_gen4_cpld_x4` also printed `UVM_FATAL : 0` and `rc_match=1`.

A Gen4 block is eight symbols. Gen3 on that elaboration still uses the low four symbols and still drops `rxstart_block == 2'b10`. The frame is the same STP, 2-byte little-endian DLL length, and DLL bytes used at Gen3. The descrambler takes a new seed on the first block after the electrical-idle gap.

| Gate | Command | Status |
|------|---------|--------|
| L0 at 16 GT/s | `.\scripts\sim_questa.ps1 smoke_gen4_l0_x4 4 0` | PASS |
| RQ MemWr32 | `.\scripts\sim_questa.ps1 smoke_gen4_memwr_x4 4 0` | PASS |
| RQ MemRd + CplD | `.\scripts\sim_questa.ps1 smoke_gen4_cpld_x4 4 0` | PASS |
| Perf MemWr64 sweep | `.\scripts\sim_questa.ps1 perf_rq_memwr64_gen4_x4 4 0` | PASS through 4096 B |
| Perf MemRd64 sweep | `.\scripts\sim_questa.ps1 perf_rq_memrd_gen4_x4 4 0` | PASS through 4096 B |

The user port and the DLL beat are 32 bytes at Gen4. `perf_rq_memwr64_gen4_x4` (8 TLPs after Gen4 L0, 4 ns user clock, 25 Nov 2026) printed `mb_s` 888.889, 1777.778, 3555.556, 3764.706, 5120.000, 6243.902, 7013.699, 7474.453, 7728.302, 7861.804, 7930.300. `cycles` 9, 9, 9, 17, 25, 41, 73, 137, 265, 521, 1033. `rq_stall=0`, `credit_stall=0`. `perf_rq_memrd_gen4_x4` printed MemRd64 `mb_s` 117.647, 231.884, 450.704, 876.712, 1542.169, 2612.245, 3580.420, 4970.874, 6150.150, 6965.986, 7447.273. `cycles` 68, 69, 71, 73, 83, 98, 143, 206, 333, 588, 1100. `rc_tlast=8` at every size. Both sweeps printed `UVM_ERROR : 0`, `UVM_FATAL : 0`.

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

Uses built-in `-L mtiUvm` (match `UVM_HOME` to uvm-1.1d). Lane width is compile-time `+define+RIVET_TB_LANES=N`. DUT mode is `+define+RIVET_TB_MODE=M` (third script argument, default 0 = EP).

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
