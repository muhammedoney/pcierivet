# PG239 PHY example — BFM side-path (stage 1)

This is **not** a full PCIe Root Port BFM and **not** a Rivet LTSSM test.
It brings the Vivado **PCIe PHY (PG239)** example into Rivet’s regression side-path so we can prove:

1. Questa + Vivado `compile_simlib` work for UltraScale+ GTY / PG239
2. Real `pcie_phy_0` talks to the Xilinx PHY serial **model** over ×4 lanes
3. Gen1 then Gen2 rate / PHY traffic completes (`Test Completed Successfully`)

UVM and Verilator remain the primary DUT gates. This track is complementary.

Later stages (not this README):

| Stage | What |
|-------|------|
| **1 (this)** | PG239 + `phy_ctrl` pattern ↔ PHY model |
| **2** | Replace `phy_ctrl` with `rivet_pcie_ctrl` on PIPE |
| **3** | PG213 EP example → swap EP for Rivet+PG239 (full EP functions) |
| **4** | PG213 RP ↔ Rivet+PG239 (system-level) |

## What the test does

Top: `board.v` (Vivado example).

```text
  refclk + reset
        │
        ├──────────────────────────────┐
        ▼                              ▼
 ┌──────────────────┐         ┌─────────────────────┐
 │ xilinx_pcie_phy  │ serial  │ xilinx_pcie_phy_    │
 │ _top             │◄───────►│ model               │
 │  = pcie_phy_0    │  ×4     │  (partner PHY)      │
 │  + phy_ctrl      │         │  + phy_ctrl         │
 │  (pattern / rate)│         │                     │
 └──────────────────┘         └─────────────────────┘
```

Stimulus sequence (see example `imports/board.v`):

1. Assert / deassert `sys_rst_n`
2. Wait both sides **phy_ready** (LED)
3. Enable Gen1 on both sides → wait traffic-good LED → Gen1 off
4. Enable Gen2 → wait traffic-good → print success → `$finish`

PASS string in the log:

```text
Test Completed Successfully
```

IP configuration in the current example project: **×4**, **max Gen2**, **PIPE data width 64** (`PHY_DATA_WIDTH=64`). Rivet soft-ctrl today assumes 16-bit/lane PIPE — stage 2 must reconcile that (regenerate IP or add an adapter).

## Prerequisites

| Item | Notes |
|------|--------|
| Questa | e.g. `C:\questasim64_2024.1` |
| Vivado | 2024.2 (example was exported from 2024.2) |
| Example project | Local Vivado `pcie_phy_0_ex` (proprietary — **not** in git) |
| `compile_simlib` | Questa libs for UltraScale+ under a local directory |

Proprietary sources stay outside git (or under gitignored `third_party/xilinx_ip/`).

## One-time setup

### 1. `scripts/local_paths.ps1` (gitignored)

Copy from `scripts/local_paths.example.ps1` and set:

```powershell
$env:QUESTA_HOME = "C:\questasim64_2024.1"
$env:PATH = "$env:QUESTA_HOME\win64;$env:PATH"
$env:XILINX_VIVADO = "C:\Xilinx\Vivado\2024.2"
$env:RIVET_PG239_EX = "C:\Users\tosba\vivado\pcie_phy_0_ex"
$env:RIVET_QUESTA_SIMLIB = "$env:RIVET_PG239_EX\pcie_phy_0_ex.cache\compile_simlib\questa"
```

### 2. Compile simulation libraries (once, long)

If `RIVET_QUESTA_SIMLIB\modelsim.ini` is missing:

```powershell
.\scripts\compile_simlib_pg239.ps1
```

### 3. Example project

You should already have generated **PCIe PHY** example design for VU9P / Gen2 / ×4. Point `RIVET_PG239_EX` at that project root (contains `imports\`, `sim\questa\`, `pcie_phy_0_ex.gen\`, …).

## How to run

From the Rivet repo root:

```powershell
# Stage 1 — Vivado phy_ctrl pattern example (default)
.\scripts\sim_bfm_pg239.ps1

# Stage 2 — rivet_pcie_ctrl + PG239 on both serial sides
.\scripts\sim_bfm_pg239.ps1 -Dut rivet
```

Options:

```powershell
.\scripts\sim_bfm_pg239.ps1 -Dut rivet -Step compile
.\scripts\sim_bfm_pg239.ps1 -Dut rivet -Step elaborate
.\scripts\sim_bfm_pg239.ps1 -Dut rivet -Step simulate
.\scripts\sim_bfm_pg239.ps1 -ResetRun
.\scripts\sim_bfm_pg239.ps1 -Gui
```

### Stage 2 topology ( `-Dut rivet` )

```text
  rivet_pcie_ctrl ──16b── pad ──64b── pcie_phy_0  ══serial══  pcie_phy_0 ──64b── pad ──16b── rivet_pcie_ctrl
       (EP)                                                    (peer shell; same EP RTL until RC MODE)
```

Gen2 uses only `[15:0]` of each lane's 64-bit PHY word (`rivet_pipe_pg239_pad`).

PASS string:

```text
Test Completed Successfully (Rivet+PG239 link_up)
```

Work products (logs, `questa_lib`, generated `compile.do`) land in:

```text
tb/bfm/pg239_phy/work/     (gitignored)
```

The runner also creates a junction (if missing):

```text
third_party/xilinx_ip/pcie_phy_0_ex  →  %RIVET_PG239_EX%
```

so the example appears under the repo tree without copying IP into git.

### Alternate: Vivado’s own script

You can still run from the example:

```text
cd %RIVET_PG239_EX%\sim\questa
# Fix simulate.do: use "run -all" (not "run 1000ns") or board.v never finishes
./board.sh -lib_map_path <path-to-compile_simlib/questa>
```

On Windows, prefer `.\scripts\sim_bfm_pg239.ps1`.

## Layout in this repo

```text
tb/bfm/pg239_phy/
  README.md
  rtl/
    rivet_pg239_ep.sv       ← pcie_phy_0 + rivet_pcie_ctrl + pad
    rivet_pg239_board.sv    ← two EP shells over serial ×4
  questa/
    elaborate.do            ← pattern DUT
    elaborate_rivet.do      ← Rivet DUT
    simulate.do             ← run -all until $finish
    wave.do
  work/                     ← local only (gitignored)

rtl/phy/rivet_pipe_pg239_pad.sv   ← Gen2 16-in-64 map

scripts/sim_bfm_pg239.ps1
scripts/compile_simlib_pg239.ps1
```

Do **not** commit `pcie_phy_0` netlists, encrypted IP, or `compile_simlib` outputs.

## Pass / fail

| Result | Meaning |
|--------|---------|
| Script exit 0 + `PASS: Test Completed Successfully` | Pattern DUT Gen1+Gen2 traffic OK, or Rivet both-sides `link_up` |
| Exit 2 | Sim ran but success string missing |
| Compile / elaborate errors | Paths, simlib, or IP regenerate issue |

## Relation to Rivet soft controller

`-Dut rivet` replaces Xilinx `phy_ctrl` with `rivet_pcie_ctrl` on both sides of the serial link (peer is a second EP-shaped shell until `MODE=RC` exists). Pattern mode remains the PHY bring-up gate.
