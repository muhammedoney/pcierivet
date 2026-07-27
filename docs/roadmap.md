# Rivet roadmap

**Active generation for all current work: Gen2** (`MODE=EP`, `GEN=2`, lanes ×1/×2/×4).  
Gen3/4/5 are later phases — see [gen-evolution.md](gen-evolution.md) for per-module follow-ups.

## Phase 0 — Bootstrap (done / sustaining)

- Repo, Apache-2.0, docs, Cursor rules/skills
- Terminology: **`rivet_pcie_ctrl`** + **`rivet_pcie_phy_*`** + **`rivet_pcie`**
- PIPE (PG239-aligned ports) + AXI-ST + `cfg_mgmt` stubs
- UVM skeleton; Verilator CI; Questa scripts; Yosys hook
- Vivado BFM side-path docs; target hardware **VCU118 (XCVU9P)**

## Phase 1 — UVM environment first, then Gen2 link skeleton (current)

**Priority order (do not invert):**

1. **UVM environment** (primary) — make `tb/uvm` the place Gen2 RTL is proven  
   - PIPE agent: driver / monitor / sequencer + items covering Gen2 PIPE fields  
   - AXI-ST agents (CQ/CC/RQ/RC): same  
   - PG213 companion paths: CQ NP credits, RQ tags/sequence/credits, then config/interrupt agents ([audit](pg213-interface.md))  
   - Virtual sequencer, scoreboard hooks, coverage model stubs → real checks as RTL appears  
   - Runnable Questa smokes: `smoke_gen2_x1`, then ×2 / ×4  
   - Verilator remains lint/elaborate gate; UVM is the functional authority  
2. **Gen2 EP link RTL** (against that UVM)  
   - LTSSM Detect → Polling → Configuration (`MODE=EP`, Gen2 ×1)  
   - DLLP / credit stubs  
   - Grow sequences/scoreboard with each RTL slice  

Gen3/4 ports may already exist on PIPE; **do not implement Gen3/4 behavior in Phase 1**.

## Phase 2 — EP Gen2 functional

- TLP on AXI-ST; config via `cfg_mgmt_*`  
- Expand UVM (TLP scoreboard, config sequences, coverage)  
- FPGA bring-up with `rivet_pcie` + US+ PHY on **VCU118 (XCVU9P)**; PG239 generate for VU9P  

## Phase 3 — EP Gen3

- After Gen2 UVM + link proof (sim first; HW when board available)  
- 128b/130b path, Recovery.Equalization, PG239 EQ/assist usage  
- UVM Gen3 sequences / monitors; `PIPE_DATA_WIDTH` → 32  
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 4 — EP Gen4

- Gen4 rate / 64-bit US+ datapath; VCU118 constraints  
- UVM Gen4 smokes and EQ/rate-change coverage  
- Details: [gen-evolution.md](gen-evolution.md)

## Phase 5+ — Gen5 / other modes

- Gen5 as backlog (PIPE 5.x notes; device family may differ)  
- RC, USP, DSP via `MODE` (same controller)

## Backlog

- ASIC microarchitecture (deferred)
