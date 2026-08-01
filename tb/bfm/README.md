# Vivado BFM side-path (non-UVM)

Complementary to UVM / Verilator. Proprietary IP stays under `third_party/xilinx_ip/` (junctions) or external Vivado trees — **never committed**.

## Tracks

| Dir | Role | Run |
|-----|------|-----|
| [pg239_phy](pg239_phy/README.md) | PG239 PHY example → Rivet ctrl on PIPE | `.\scripts\sim_bfm_pg239.ps1` / `-Dut rivet` |
| [pg213_ep](pg213_ep/README.md) | PG213 EP example + RP model → swap EP for Rivet+PG239 | `.\scripts\sim_bfm_pg213.ps1` |

## Roadmap

1. **PG239 pattern** — stock phy_ctrl Gen1/Gen2 traffic (done).
2. **PG239 + Rivet ctrl** — dual EP shells; LTSSM debug (in progress; state~5 loop known).
3. **PG213 stock** — RP model ↔ Xilinx EP + PIO (scaffold; run stock first).
4. **PG213 EP swap** — same RP/PIO, EP = Rivet+PG239 (`rivet_pg213_ep_swap`).
5. **System** — Xilinx RP PG213 ↔ Rivet+PG239 (later).

Fix Rivet LTSSM / TL before expecting PIO or system PASS on tracks 4–5.

## Rules

- Do **not** commit Xilinx encrypted IP, BFM netlists, or Vivado project caches.
- Keep Rivet-owned scripts under `tb/bfm/` and `scripts/sim_bfm_*.ps1`.
- BFM failures that show DUT bugs should also get UVM coverage.
