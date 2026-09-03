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
| `PG213 RP + Rivet EP link_up` | PASS |
| `Detect/Polling cycle` / `TIMEOUT` | FAIL (expected until LTSSM links) |

## Observed bring-up (Rivet DUT)

Compile + elaborate succeed (needs `xp4_usp_smsw_model_core_top.v` + `board_common` macros).

Simulation reaches EP `phy_ready`, then LTSSM cycles **Detect → Polling → (state 4) → Detect** with `link_up=0` and `RP.user_lnk_up=0`. Board finishes on the first return to Detect after seeing state 4 (~minutes wall-clock with dual GTY).

Same Detect/Polling pattern as the dual-Rivet PG239 board — next debug is LTSSM/PIPE vs RP, not the BFM harness.

## Known gaps

| Gap | Notes |
|-----|--------|
| Rivet LTSSM / link_up | Detect/Polling cycle; no stable L0 yet |
| Rivet TL / CFG | Stubs — after link_up, RP usrapp Cfg/PIO will still fail until TL lands |
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
