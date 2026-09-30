# PG213 EP example — BFM side-path (stage 3)

Vivado **UltraScale+ PCIe Integrated Block (PG213)** example with stock **Root Port model** + usrapp PIO, and optional **Rivet EP+PG239** swap.

Local copy (gitignored): `third_party/xilinx_ip/pcie4_uscale_plus_0_ex/` — refresh via `.\scripts\sync_xilinx_examples.ps1`.

## Topology

### Stock (`-Dut stock`)

```text
  RP model (xilinx_pcie_uscale_rp + usrapp_*)     EP (xilinx_pcie4_uscale_ep)
        │  serial ×N                                      │
        │◄───────────────────────────────────────────────►│
        │                                           pcie4_uscale_plus_0 (PG213)
        │                                           + pcie_app_uscale / PIO
        └─ cfg / mem R/W tests (pio_writeReadBack_…)
```

### Rivet (`-Dut rivet`) — current bring-up target

Soft Rivet RC is **not** used. Partner is the **PG213 RP BFM**:

```text
  RP = xilinx_pcie4_uscale_rp (+ usrapp_*)     EP = rivet_pg213_ep_swap
        │                                            │
        │◄──────────── serial ×N (N=1/2/4) ─────────►│
        │                                            │  rivet_pcie_ctrl (GEN=2, SpeedChange=0)
        │                                            │       ──PIPE── PG239 (PHY fixed ×4)
        │                                            │         ▲
        │                                            │         └── CQ/CC/RQ/RC + cfg_mgmt (dual_app)
```

Board module name is `board` and RP instance is `RP` (usrapp hierarchical refs).

## How to run

### Prerequisites

Questa + Vivado `compile_simlib`. In `scripts/local_paths.ps1`:

```powershell
$env:RIVET_PG213_EX = "...\pcie4_uscale_plus_0_ex"
$env:RIVET_PG239_EX = "...\pcie_phy_0_ex"          # Rivet DUT only
$env:RIVET_QUESTA_SIMLIB = "...\compile_simlib\questa"
```

### Stock PG213 (RP ↔ Xilinx EP)

```powershell
.\scripts\sim_bfm_pg213.ps1 -Dut stock
```

### Rivet EP under PG213 RP

```powershell
.\scripts\sim_bfm_pg213.ps1 -Dut rivet
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Lanes 1   # Gen1 x1
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Lanes 2   # Gen1 x2
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Lanes 4   # Gen1 x4 (default)
# stepwise:
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Step compile
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Step elaborate
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Step simulate
```

Work dir: `tb/bfm/pg213_ep/work/`.

| Token in `simulate.log` | Script result |
|-------------------------|---------------|
| `Class A+C+E` / `Class E PASS` | PASS (Gen1 ×N + MemWr/MemRd app) |
| `Class A PASS` / `Class A+C` / `PIO 1DW` | PASS (BAR0 Mem32; Class C = EP RQ MemWr) |
| `Class A FAIL` / `PIO 1DW incomplete` | FAIL |
| `Cfg Vendor/Device incomplete` | FAIL (link trained, Cfg path not closed) |
| `TIMEOUT` / Detect loop | FAIL |

## Traffic classes (Questa RC↔EP apps)

| Class | Meaning | Status |
|-------|---------|--------|
| A | RP Cfg + BAR0 MemWr/Rd 1 DW | PASS |
| B | Multi-DW BAR0 PIO | **WAIVE** — usrapp 1DW-only; MAC TLP buf=160 + multi-DW PIO ready; UVM CQ/CC @×4 is MVP gate |
| C | EP BME MemWr on RQ | PASS (wire accept) |
| D | EP BME MemRd + RP CplD (DATA_STORE) | PASS when host preload matches |
| E | EP MemWr+MemRd app score vs RP DATA_STORE | PASS |

Lane matrix (`-Lanes 1|2|4`): RP `PL_LINK_CAP_MAX_LINK_WIDTH` + serial pairs; EP+PG239 PHY stays ×4
and negotiates down when possible. **Gen1 ×4 Class A+C+E is the BFM app gate.** Gen1 ×1/×2 on this
serial pad currently times out in Config (RP stays Polling); use UVM
`smoke_gen2_x1` / `smoke_linkwidth_peer_x2_dut_x4` for width. Gen1-only (`RP` speed cap 1, EP `SPEED_CHANGE_EN=0`).

| Lanes | Gen1 link + Class A+C+E (Questa BFM) |
|-------|--------------------------------------|
| ×4    | **PASS** |
| ×2    | Config timeout (UVM width gate) |
| ×1    | Config timeout (UVM width gate) |

EP dual-role app: `rtl/rivet_ep_dual_app.sv` (CQ/CC completer + RQ/RC bus-master).

## Observed bring-up (Rivet DUT)

L0 + InitFC + `dl_up` already proven. EP is **GEN=2** with `SPEED_CHANGE_EN=0` (TS rate ID Gen1) so the Gen1-capped RP stays stable; negotiated Gen2 / Recovery.Speed remains a UVM gate (`smoke_recovery_speed_gen2_x4`). After `user_lnk_up` the board forces RP `cfg_ltssm_state` **0x0B → 0x10** once so the PG213 usrapp Gen2 `wait(Recovery)` does not hang. Type 0 Cfg and BAR scan close; then Class A PIO, Class C EP RQ MemWr, and Class D/E MemRd scored against RP `DATA_STORE`. Class B prints `Class B WAIVE`.

## Known gaps

| Gap | Notes |
|-----|--------|
| Class B multi-DW usrapp | Wire PG213 usrapp multi-DW stimulus; RTL window ready |
| AXI width | RP usrapp expects wide AXI-ST; do not force 64-bit on RP |
| Negotiated Gen2 on serial | EP GEN=2 but `SPEED_CHANGE_EN=0` + RP max Gen1; enable Speed Change after PG239 rate-change bring-up |
| BFM Gen1 ×1/×2 train | RP×N + EP PHY×4 pad times out in Config; UVM covers width |

## Layout

```text
tb/bfm/pg213_ep/
  README.md
  rtl/
    rivet_pg213_board.sv      # module board: RP BFM + Rivet EP (Class A/C)
    rivet_pg213_ep_swap.sv    # EP pin shell → Rivet+PG239
    rivet_ep_dual_app.sv      # CQ/CC completer + RQ/RC bus-master
    board_common_inc.v        # prelude for -mfcu usrapp macros
  questa/
    elaborate_rivet.do
    simulate_rivet.do
    simulate.do               # stock
  work/                       # gitignored

scripts/sim_bfm_pg213.ps1
```

UVM + Verilator remain primary gates; this BFM track is complementary.
