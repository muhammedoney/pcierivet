# Vivado BFM side-path (non-UVM)

Complementary to UVM / Verilator. Example `board.v` / IP trees sit under `third_party/xilinx_ip/` (**gitignored**, never push). Sync: `.\scripts\sync_xilinx_examples.ps1`.

## Tracks

| Dir | Role | Run |
|-----|------|-----|
| [pg239_phy](pg239_phy/README.md) | PG239 PHY example → Rivet ctrl on PIPE | `.\scripts\sim_bfm_pg239.ps1` / `-Dut rivet` |
| [pg213_ep](pg213_ep/README.md) | PG213 EP example + RP model → swap EP for Rivet+PG239 | `.\scripts\sim_bfm_pg213.ps1` |

## Roadmap

1. **PG239 pattern** — stock phy_ctrl Gen1/Gen2 traffic (done).
2. **PG239 + Rivet ctrl** — EP + RC shells; dual `link_up` @ ×4 (**PASS** — Stage 2).
3. **PG213 stock** — RP model ↔ Xilinx EP + PIO.
4. **PG213 EP swap** — Class A+C PASS; Class B WAIVE; Class D PASS/WAIVE ([pg213_ep](pg213_ep/README.md)).
5. **System** — Xilinx RP PG213 ↔ Rivet+PG239 (later).
6. **FPGA lab** — VCU118 board bring-up (**backlogged** until hardware available).

### MVP checklist (sim)

```powershell
.\scripts\sim_bfm_pg213.ps1 -Dut rivet   # Class A+C; look for Class B WAIVE / Class D PASS|WAIVE
.\scripts\sim_bfm_pg239.ps1 -Dut rivet   # "Test Completed Successfully (Rivet+PG239 link_up)"
```

UVM ×4 gates in [docs/verification.md](../../docs/verification.md) remain authoritative for the MVP tag.

## Rules

- Do **not** commit Xilinx encrypted IP, BFM netlists, or Vivado project caches.
- Keep Rivet-owned scripts under `tb/bfm/` and `scripts/sim_bfm_*.ps1`.
- BFM failures that show DUT bugs should also get UVM coverage.
