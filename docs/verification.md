# Verification

## Tracks

| Track | Tool | Role |
|-------|------|------|
| **Primary** | QuestaSim + UVM | Regression on **`rivet_pcie_ctrl`** at PIPE |
| **Fast smoke** | Verilator | Lint / elaborate controller |
| **Synth sanity** | Yosys | Open synth of controller stub |
| **Side-path** | Vivado BFM → Questa | Complementary; not a UVM substitute |

Primary DUT: **`rivet_pcie_ctrl`**. Full IP `rivet_pcie` is for FPGA / BFM bring-up.

## UVM Phase 0

- Agents: PIPE + AXI-ST CQ/CC/RQ/RC
- Smoke: `smoke_gen2_x1` (then ×2 / ×4)
- Empty scoreboard + coverage stubs

## QuestaSim (local)

Copy `scripts/local_paths.example.ps1` → `local_paths.ps1`, then `scripts/sim_questa.ps1`.

| Tool | Version |
|------|---------|
| QuestaSim | _TBD_ |
| UVM | _TBD_ |
| Verilator | _TBD_ |
| Yosys | _TBD_ |

## Spec policy

Do not commit PCIe / PIPE / PG213 / PG239 PDFs.
