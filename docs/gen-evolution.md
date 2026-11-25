# Generation evolution (Gen4 x4 closed, Gen5 not started)

**Default elaboration: Gen2** (`GEN=2`, `PIPE_DATA_WIDTH=16`, `MODE=EP`). **In simulation: Gen3 and Gen4 x4** for EP, RC, USP, and DSP (`PIPE_DATA_WIDTH` 32 then 64, user AXI-ST 128 then 256 bits). Phase 8 added RC Type 0/1 config, CplD on USP/DSP/RC, Hot Reset and Link Disable from L0, the posted forwarder `rtl/switch/rivet_sw_posted_fwd`, and opt-in preset search plus one coefficient and a margin nibble. Gen5 is not started.

Keep Gen2 behavior when `rate` is Gen1 or Gen2. A Gen3 or Gen4 change that breaks a Gen2 smoke is not done.

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

## Per-area: Gen2 default vs Gen3/4 in simulation

### `rtl/interfaces/rivet_pipe_if.sv`

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| Classic 8b/10b path: `txdata`/`txdatak`, `rxdata`/`rxdatak`, `rxvalid`, `rxelecidle` | Block path is live: `txdata_valid`, `txstart_block`, `txsync_header`, and the RX twins |
| `PIPE_DATA_WIDTH=16` | 32 at Gen3, 64 at Gen4 US+. Widths below the elaboration stay in the low bits |
| `txmargin` stays 0 unless a test forces a margin message | High nibble `4'h1` on that message drives `txmargin[2:0]`. Preset search and one coefficient are opt-in on `txeq_*` |
| Assist: Detect / CDR for the Gen2 LTSSM | Same assist model through Recovery.Speed and Recovery.Equalization |

### `rtl/pcie_ctrl/` (`rivet_pcie_ctrl.sv` + `mac/` / `dll/` / `tl/`)

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| 8b/10b ordered sets, SKP, disparity | 128b/130b blocks. DataK is idle at block rate |
| 64-bit user AXI-ST and DLL beat | 128-bit at Gen3, 256-bit at Gen4. RC config headers are packed on all three widths |
| `pipe_rate` Gen1↔Gen2 with PhyStatus | Same handshake through Gen3 (`rate=2`) and Gen4 (`rate=3`) |
| Downstream EQ master sends `8'h0A` / preset 1 whenever `GEN>=3` | Opt-in `eq_search` offers preset 0 in EQ0, then preset 1. `eq_search` tied off keeps the preset-1 path |
| Hot Reset and Link Disable from L0 | Same two directions at 8 GT/s and 16 GT/s. The block-rate peer puts the training-control bit in TS byte 5 |

`rtl/switch/rivet_sw_posted_fwd` sits between two controllers. It rewrites a CQ MemWr into an RQ descriptor and drops config. It does not train a second link.

### `rtl/pcie_ctrl/rivet_pkg.sv`

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| `RIVET_GEN2` is the default parameter | `GEN=3` and `GEN=4` select pipe width, AXI width, and the block-rate LTSSM |

### `rtl/phy/rivet_pcie_phy_usplus.sv` / `rivet_pcie_phy_us.sv` / `rivet_pcie_phy_versal.sv`

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| Behavioral stub; serial tied | The soft controller speaks 32-bit and 64-bit PIPE. A generated PG239/PG345 for Gen3/4 is still a lab step |
| 16-bit logical width on the stub | Wrappers must pass the full 32/64-bit `phy_txdata`/`phy_rxdata` when a real PHY is bound |
| No GT/DRP on the behavioral stub | `rivet_pcie_phy_wrap` binds PG239 or PG345 from `BOARD` |

### `rtl/top/rivet_pcie.sv`

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| Pass-through PIPE between `u_ctrl` and `u_phy` | Same. The controller's `GEN` sets the PIPE width |
| `FPGA_FAMILY` select | 0=US+, 1=US, 2=Versal. Speed-grade constraints stay in the vendor project |

### `rtl/interfaces/rivet_axi_st_if.sv` / `rivet_cfg_mgmt_if.sv`

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| 64-bit AXI-ST | 128-bit at Gen3, 256-bit at Gen4. CQ/CC/RQ/RC names stay |
| `cfg_mgmt_*` for the local config image | Same pulse interface. RC config TLPs use the RQ channel, not `cfg_mgmt` |

### `tb/uvm/**`

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| PIPE + AXI-ST agents, scoreboard, coverage | Gen3/4 peers, equalization, rate change, config, CplD, Hot Reset, Link Disable |
| `smoke_gen2_*` | `smoke_gen3_*`, `smoke_gen4_*`, `smoke_eq_search_gen3_x4`, `smoke_eq_search_gen4_x4` |

### Scripts / CI

| Gen2 default | Gen3/4 in simulation |
|--------------|----------------------|
| `scripts/lint.ps1` on the Gen2 controller top | The same script also lints `tb/lint/rivet_gen3_lint_top.sv` and `rivet_gen4_lint_top.sv` |
| `sim_questa.ps1` defaults to Gen2, 16-bit PIPE | A test name containing `gen3` or `gen4` sets `GEN` and `PIPE_DATA_WIDTH` |

---

## Phase priority reminder

See [roadmap.md](roadmap.md). Phase 4 (Gen3 EP x4 L0, one MemWr32, one CplD) closed on 2026-11-24. Phase 5 (Gen4 EP x4 L0, one MemWr32, one CplD) closed on 2026-11-25. Phase 6 closed on 2026-11-25: at Gen3, USP is the upstream equalization slave (same machine as EP) and RC/DSP are the downstream master, transmitting EQ byte `8'h0A` and preset `8'h01`. Phase 7 closed on 2026-11-25: the same three modes reach L0 at 16 GT/s and post one RQ MemWr32. The master needs no new RTL. The upstream peer holds speed-change TS2 (rate byte `8'h9E`) across the Gen3-to-Gen4 recovery, then repeats the slave walk at rate 3. Phase 8 closed on 2026-11-25: RC config Type 0/1, CplD from USP/DSP/RC, Hot Reset, and Link Disable at both 8 GT/s and 16 GT/s; a posted CQ-to-RQ forwarder; and an opt-in preset search that falls through to preset 1, then one coefficient and a margin message. Next is the Gen5 backlog.
