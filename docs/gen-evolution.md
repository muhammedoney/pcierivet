# Generation evolution (Gen4 x4 closed, Gen5 not started)

**Active sim target: Gen4 EP x4** (`GEN=4`, `PIPE_DATA_WIDTH=64`, 16 GT/s). Default elaboration stays `GEN=2` and a 16-bit pipe so every Gen2 smoke still builds unchanged. Gen5 is not started.

Keep Gen2 behavior when `rate` is Gen1 or Gen2. A Gen3 change that breaks a Gen2 smoke is not done.

Encoding reminder (PG239 UltraScale+ defaults — **fixed 2-byte datapath** for Gen1↔Gen2):

| Gen | Line rate | Encoding | PCLK | PIPE data / lane | Notes |
|-----|-----------|----------|------|------------------|-------|
| **1** | 2.5 GT/s | 8b/10b | **125 MHz** | **16 bits (2-byte)** | Not 8-bit @ 250 MHz. Same width as Gen2; only PCLK halves. |
| **2** | 5.0 GT/s | 8b/10b | **250 MHz** | **16 bits (2-byte)** | Active Rivet target (`PIPE_DATA_WIDTH=16`) |
| **3** | 8.0 GT/s | 128b/130b | 250 MHz | 32 bits (4-byte) | Fixed-PCLK rate change Gen3↔Gen4 |
| **4** | 16 GT/s | 128b/130b | 250 MHz | 64 bits (8-byte, US+) | |

**Gen1 vs Gen2 (important):** PG239 uses a **fixed datapath** between Gen1 and Gen2 (`txdatak[1:0]` / 16-bit symbols). Rate change changes **PCLK** (125 ↔ 250 MHz), not the byte width. So Rivet Gen1 (when enabled later) is **125 MHz × 16-bit/lane**, not 250 MHz × 8-bit/lane.

Throughput check (1 lane, after 8b/10b):  
16 × 125 MHz = 2.0 Gb/s ≡ Gen1; 16 × 250 MHz = 4.0 Gb/s ≡ Gen2.

---

## Per-area: Gen2 now vs Gen3/4 later

### `rtl/interfaces/rivet_pipe_if.sv`

| Now (Gen2) | Later (Gen3/4) |
|------------|----------------|
| Drive/observe classic 8b/10b path: `txdata`/`txdatak`, `rxdata`/`rxdatak`, `rxvalid`, `rxelecidle`, driver `txmargin`/`txswing`/`txdeemph` | **Use** already-present Gen3+ ports: `txdata_valid`, `txstart_block`, `txsync_header`, `rxdata_valid`, `rxstart_block`, `rxsync_header` |
| `PIPE_DATA_WIDTH=16` | Raise to 32 (Gen3) then 64 (Gen4 US+); keep unused MSBs ignored below those gens (PG239) |
| EQ / assist may idle | Drive AMD **custom** EQ (`txeq_*` / `rxeq_*`) per PG239 — not standard PIPE Local FS/LF EQ |
| Assist: Detect / CDR as needed for Gen2 LTSSM | Same assist model; ASPM L0s ports if enabled |

### `rtl/pcie_ctrl/` (`rivet_pcie_ctrl.sv` + `mac/` / `dll/` / `tl/`)

| Now (Gen2) | Later (Gen3/4) |
|------------|----------------|
| Stub top; layer folders ready for sources | Add Recovery.Equalization phases; Gen3/4 rate change |
| 8b/10b ordered sets, SKP, disparity (`mac/`) | 128b/130b OS / block sync; ignore DataK path |
| DLLP / credit (`dll/`) / TLP (`tl/`) for Gen2 | Same TL/DL with Gen3+ framing on PIPE; wider internal datapath |
| `pipe_rate = Gen2`; P1/`txelecidle` idle defaults | Dynamic `pipe_rate` Gen1↔Gen2↔Gen3↔Gen4; honor `phystatus` completion |
| EQ outputs tied off | Full PG239 TX/RX EQ sequences (see PG239 Ch.4) |
| `$error` if `GEN != 2` | Gate features by `GEN`; widen compile-time checks |

Suggested MAC modules under `mac/` (still Gen2-first): `rivet_ltssm`, `rivet_mac_os_tx` / `_rx`, `rivet_mac_pipe_adapter` — each gets a Gen3/4 section in this doc when created.

### `rtl/pcie_ctrl/rivet_pkg.sv`

| Now | Later |
|-----|-------|
| `RIVET_GEN2` active | Use `RIVET_GEN4` / enums in params; helpers for legal `PIPE_DATA_WIDTH` vs `GEN` |

### `rtl/phy/rivet_pcie_phy_usplus.sv` / `rivet_pcie_phy_us.sv` / `rivet_pcie_phy_versal.sv`

| Now (Gen2) | Later (Gen3/4) |
|------------|----------------|
| Behavioral stub; serial tied | Real PHY instance; map Rivet PIPE ↔ `phy_*` |
| 16-bit logical width | Connect full 32/64-bit `phy_txdata`/`phy_rxdata` per family table |
| US and Versal wrappers share the US+ stub packing | Honor US 1-bit `rxstart_block` vs US+ 2-bit if wrapping real IP |
| No GT/DRP on the behavioral stub | `rivet_pcie_phy_wrap` binds PG239 (`gt_gtpowergood`) or PG345 (`phy_ready`, `phy_phystatus_rst`, external GT quad) from `BOARD`. |

### `rtl/top/rivet_pcie.sv`

| Now | Later |
|-----|-------|
| Pass-through PIPE between `u_ctrl` and `u_phy` | Same; optional width/adapters if ctrl logical width ≠ PHY pin width |
| `FPGA_FAMILY` select | Gen4 speed-grade / part constraints live in the vendor project (not in soft RTL). 0=US+, 1=US, 2=Versal |

### `rtl/interfaces/rivet_axi_st_if.sv` / `rivet_cfg_mgmt_if.sv`

| Now (Gen2) | Later (Gen3/4) |
|------------|----------------|
| 64-bit AXI-ST stub (PG213-style) | May widen AXI data/user widths with gen/lanes; CQ/CC/RQ/RC stay |
| `cfg_mgmt_*` stub (PG213 Table 26) | Same pulse IF; extended regs / IDs as capabilities grow |

### `tb/uvm/**` (Phase 1 priority)

| Now (Gen2) | Later (Gen3/4) |
|------------|----------------|
| **Build out** PIPE + AXI-ST agents, sequences, scoreboard, coverage for Gen2 | Extend agents for Gen3+ PIPE fields; EQ monitors; rate-change sequences |
| Smoke `smoke_gen2_x1` / ×2 / ×4 | `smoke_gen3_*`, `smoke_gen4_*`; EQ / Recovery tests |
| Scoreboard: Gen2 OS/DLLP/TLP when RTL exists | 128b/130b checkers; Gen3/4 ordered-set models |

### Scripts / CI

| Now | Later |
|-----|-------|
| Lint/smoke Gen2 top | Plusargs / defines for `GEN` and `PIPE_DATA_WIDTH`; optional Gen3/4 lint tops |

---

## Phase priority reminder

See [roadmap.md](roadmap.md). Phase 4 (Gen3 EP x4 L0, one MemWr32, one CplD) closed on 2026-11-24. Phase 5 (Gen4 EP x4 L0, one MemWr32, one CplD) closed on 2026-11-25. Phase 6 closed on 2026-11-25: at Gen3, USP is the upstream equalization slave (same machine as EP) and RC/DSP are the downstream master, transmitting EQ byte `8'h0A` and preset `8'h01`. Phase 7 closed on 2026-11-25: the same three modes reach L0 at 16 GT/s and post one RQ MemWr32. The master needs no new RTL. The upstream peer holds speed-change TS2 (rate byte `8'h9E`) across the Gen3-to-Gen4 recovery, then repeats the slave walk at rate 3. Phase 8 closed on 2026-11-25: RC config Type 0/1, CplD from USP/DSP/RC, Hot Reset, and Link Disable at both 8 GT/s and 16 GT/s; a posted CQ-to-RQ forwarder; and an opt-in preset search that falls through to preset 1, then one coefficient and a margin message. Next is the Gen5 backlog.
