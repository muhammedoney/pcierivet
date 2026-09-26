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
        │◄──────────── serial ×4 ───────────────────►│
        │                                            │  rivet_pcie_ctrl ──PIPE── PG239
        │                                            │         ▲
        │                                            │         └── AXI-ST / cfg_mgmt (TL still stub)
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
# stepwise:
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Step compile
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Step elaborate
.\scripts\sim_bfm_pg213.ps1 -Dut rivet -Step simulate
```

Work dir: `tb/bfm/pg213_ep/work/`.

| Token in `simulate.log` | Script result |
|-------------------------|---------------|
| `PG213 RP + Rivet EP PIO 1DW` | PASS (BAR0 Mem32 write/readback) |
| `PIO 1DW incomplete` | FAIL (Cfg closed, Mem PIO not closed) |
| `Cfg Vendor/Device incomplete` | FAIL (link trained, Cfg path not closed) |
| `TIMEOUT` / Detect loop | FAIL |

## Observed bring-up (Rivet DUT)

L0 + InitFC + `dl_up` already proven. After `user_lnk_up` the board pulses RP `cfg_ltssm_state=0x0B` once so the PG213 usrapp Gen2 `wait(Recovery)` does not hang (Rivet has no speed-change Recovery yet). Type 0 Cfg and BAR scan close on the wire (Length in TLP byte 3). Link Cap/Status advertise Gen1 ×4 so the Gen1 RP BFM does not start a speed-change Recovery. Then the board waits for BAR0 Mem32 1 DW write/readback. 2 DW / 256 DW PIO and AXI-ST CQ/CC to a user app are still later.

## Known gaps

| Gap | Notes |
|-----|--------|
| LCRC vs PG213 | Proven on first CfgRd0 (`a1f45f41`, complement only) |
| AXI-ST CQ/CC user app | Internal BAR0 PIO first; CQ/CC export later |
| 256 DW PIO | Needs MAC/DLL slot > 1 KB (usrapp `dw_length`) |
| AXI width | RP usrapp expects wide AXI-ST; do not force 64-bit on RP |

## Layout

```text
tb/bfm/pg213_ep/
  README.md
  rtl/
    rivet_pg213_board.sv      # module board: RP BFM + Rivet EP
    rivet_pg213_ep_swap.sv    # EP pin shell → Rivet+PG239
    board_common_inc.v        # prelude for -mfcu usrapp macros
  questa/
    elaborate_rivet.do
    simulate_rivet.do
    simulate.do               # stock
  work/                       # gitignored

scripts/sim_bfm_pg213.ps1
```

UVM + Verilator remain primary gates; this BFM track is complementary.
