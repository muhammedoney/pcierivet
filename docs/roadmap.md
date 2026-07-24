# Rivet roadmap

## Phase 0 — Bootstrap (current)

- Repo, Apache-2.0, docs, Cursor rules/skills
- Terminology: **`rivet_pcie_ctrl`** + **`rivet_pcie_phy_*`** + **`rivet_pcie`**
- PIPE + AXI-ST (CQ/CC/RQ/RC) + AXI-Lite stubs
- UVM skeleton; Verilator CI; Questa scripts; Yosys hook
- Vivado BFM side-path docs

## Phase 1 — EP Gen2 link skeleton

- LTSSM Detect → Polling → Configuration (`MODE=EP`, Gen2 ×1)
- DLLP / credit stubs; grow UVM
- **×2 and ×4** smoke immediately after ×1

## Phase 2 — EP Gen2 functional

- TLP on AXI-ST; config via AXI-Lite
- FPGA bring-up with `rivet_pcie` + US/US+ PHY

## Phase 3–4 — Gen4 then Gen5

- After Gen2 hardware proof

## Later modes

- RC, USP, DSP via `MODE` (same controller)

## Backlog

- ASIC microarchitecture (deferred)
