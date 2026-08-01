# PG213 EP example — BFM side-path (stage 3)

Vivado **UltraScale+ PCIe Integrated Block (PG213)** example configured as **Endpoint**, with the stock **Root Port model** and **PIO** app.

Local copy (gitignored): `third_party/xilinx_ip/pcie4_uscale_plus_0_ex/` — refresh via `.\scripts\sync_xilinx_examples.ps1`.

Original export also lives under e.g. `C:\Users\tosba\vivado\pcie4_uscale_plus_0_ex` if you prefer `RIVET_PG213_EX` there.

## Topology (stock)

```text
  RP model (xilinx_pcie_uscale_rp + usrapp_*)     EP (xilinx_pcie4_uscale_ep)
        │  serial ×N                                      │
        │◄───────────────────────────────────────────────►│
        │                                           pcie4_uscale_plus_0 (PG213)
        │                                           + pcie_app_uscale / PIO
        └─ cfg / mem R/W tests (pio_writeReadBack_…)
```

Default example knobs (from `imports/board.v` / EP): **AXI-ST 64-bit**, Gen2-class link speed parameter, PIO slave.

## Swap plan (Rivet DUT)

Replace **only the EP PG213 core** with **`rivet_pcie_ctrl` + PG239** (same serial + PIO / RP tests):

```text
  RP model (unchanged)     EP shell = rivet_pg213_ep_swap
        │                         │
        │◄──── serial ───────────►│  rivet_pcie_ctrl ──PIPE── PG239 (pcie_phy_0)
        │                         │         ▲
        │                         │         └── AXI-ST + cfg_mgmt ← pcie_app / PIO
```

WIP RTL: `rtl/rivet_pg213_ep_swap.sv` (drop-in pin-compatible shell).  
Full PIO PASS needs working LTSSM/L0 + TL — tracked separately (see Known gaps).

## Known gaps (do not block scaffolding)

| Gap | Notes |
|-----|--------|
| Rivet LTSSM | PG239 dual-EP BFM saw Detect/Polling cycle (state ~5) without stable `link_up` |
| Rivet TL / CFG | Stubs — PIO BAR / CfgRd will not complete until TL lands |
| `simulate.do` | Vivado export uses `run 1000ns`; stock tests need `run -all` |
| `compile_simlib` | Reuse `RIVET_QUESTA_SIMLIB` or compile under this project |

Work order: fix LTSSM on PG239 BFM → enable Rivet swap here → grow PIO / system RP tests.

## How to run

### Prerequisites

Same Questa + Vivado `compile_simlib` as PG239 BFM. In `scripts/local_paths.ps1`:

```powershell
$env:RIVET_PG213_EX = "C:\Users\tosba\vivado\pcie4_uscale_plus_0_ex"
# Prefer shared simlib (already built for PG239):
$env:RIVET_QUESTA_SIMLIB = "...\compile_simlib\questa"
```

### Stock PG213 example (RP model ↔ Xilinx EP)

```powershell
.\scripts\sim_bfm_pg213.ps1
# or
.\scripts\sim_bfm_pg213.ps1 -Dut stock
```

### Rivet EP swap (experimental)

```powershell
.\scripts\sim_bfm_pg213.ps1 -Dut rivet
```

Expect **link / PIO failures** until soft-ctrl LTSSM+TL catch up. Use for elaborate / bring-up only.

## Layout

```text
tb/bfm/pg213_ep/
  README.md                 ← this file
  rtl/
    rivet_pg213_ep_swap.sv  ← EP pin shell: Rivet+PG239 (+ PIO hook)
    rivet_pg213_board.sv    ← board using swap EP + stock RP (rivet mode)
  questa/
    simulate.do             ← run -all
    elaborate_stock.do
    elaborate_rivet.do
  work/                     ← gitignored

scripts/sim_bfm_pg213.ps1
```

## Future tests (both BFM tracks)

| Track | Near-term | Later |
|-------|-----------|--------|
| `pg239_phy` | PHY pattern; Rivet dual-shell LTSSM debug | Directed LTSSM / Recovery sequences |
| `pg213_ep` | Stock PIO green; Rivet swap elaborate | PIO / Cfg after link_up; then RP↔Rivet system |

UVM + Verilator remain primary gates; these BFM tracks are complementary.
