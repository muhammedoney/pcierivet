# Verification

## Principle

**Verification before features.** For Phase 1, the **top priority is building out the UVM environment** (`tb/uvm`) for **Gen2**. New Gen2 RTL lands in small slices only when the UVM path can exercise or at least compile/elaborate against it.

Active generation under test: **Gen2**. Gen3/4 TB work is deferred — tracked in [gen-evolution.md](gen-evolution.md).

## Tracks

| Track | Tool | Role |
|-------|------|------|
| **Primary** | QuestaSim + UVM | Regression on **`rivet_pcie_ctrl`** at PIPE |
| **Fast smoke** | Verilator | Lint / elaborate controller |
| **Synth sanity** | Yosys | Open synth of controller stub |
| **Side-path** | Vivado BFM → Questa | Complementary; not a UVM substitute |

Primary DUT: **`rivet_pcie_ctrl`**. Full IP `rivet_pcie` is for FPGA / BFM bring-up.

## Phase 1 UVM build-out (priority)

Skeleton exists; fill in this order:

1. PIPE agent — Gen2 driver/monitor/sequencer, interface binding to `rivet_pipe_if` / DUT ports  
2. AXI-ST agents — CQ/CC/RQ/RC  
3. Env connect — analysis ports → scoreboard / coverage  
4. Sequences — reset, idle PIPE, then LTSSM/DLLP as RTL appears  
5. Smokes — `smoke_gen2_x1` must run under Questa when available; then ×2 / ×4  
6. Scoreboard / coverage — grow with protocol; keep stubs until then  

Do not block UVM progress on Gen3/4 features. Keep Gen3+ PIPE fields in the interface unused/idle in Gen2 tests.

## QuestaSim (local)

Copy `scripts/local_paths.example.ps1` → `local_paths.ps1`, then `scripts/sim_questa.ps1`.

| Tool | Version |
|------|---------|
| QuestaSim | _TBD_ |
| UVM | _TBD_ |
| Verilator | _TBD_ |
| Yosys | _TBD_ |

If Questa is not installed: continue UVM source work and Verilator lint; note **UVM deferred — Questa not installed** in PRs.

## Spec policy

Do not commit PCIe / PIPE / PG213 / PG239 PDFs. Keep local copies under `specs/` (gitignored).

| Doc | Why |
|-----|-----|
| PG239 | PHY wrapper ports; AMD EQ/assist (authoritative for FPGA PHY) |
| PIPE **4.4.1** | Classic PIPE Gen1–Gen4 semantics (preferred next add) |
| PIPE **5.x** (optional) | Gen5 Rate / SerDes notes — PG239 stays classic-oriented |
| PG213 | User AXI-ST CQ/CC/RQ/RC and companion/config interfaces (not PIPE); see [PG213 interface audit](pg213-interface.md) |
| PCIe Base (Gen2 chapter focus now) | LTSSM / DLLP / TLP for current phase |
