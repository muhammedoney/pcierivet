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

### PG239 PHY / Rivet ctrl (BFM)

```powershell
.\scripts\sim_bfm_pg239.ps1              # phy_ctrl pattern
.\scripts\sim_bfm_pg239.ps1 -Dut rivet   # rivet EP + RC over PG239
```

### PG213 EP example (BFM)

Stock RP model ↔ Xilinx EP (+ PIO). Rivet EP swap is scaffolded — see [tb/bfm/pg213_ep/README.md](../tb/bfm/pg213_ep/README.md).

```powershell
.\scripts\sim_bfm_pg213.ps1
```

Known: PG239 stage-2 uses EP+RC shells; re-check link_up after Downstream Config lands. PIO/system BFM still needs TL.

## Phase 1 UVM build-out (priority)

| Step | Status |
|------|--------|
| PIPE agent + idle smoke | Done (`smoke_gen2_x1`) |
| AXI-ST CQ/CC/RQ/RC agents | Done |
| `cfg_mgmt` agent + companion monitor | Done |
| Virtual sequencer + shared idle vseq | Done |
| Smokes ×2 / ×4 | Done (`smoke_gen2_x2`, `smoke_gen2_x4`) |
| Coverage (PIPE idle + lanes) | Started |
| LTSSM / DLLP sequences as RTL lands | Next |

Do not block UVM progress on Gen3/4 features. Keep Gen3+ PIPE fields in the interface unused/idle in Gen2 tests.

## QuestaSim (local)

Copy `scripts/local_paths.example.ps1` → `local_paths.ps1`, then:

```powershell
.\scripts\sim_questa.ps1 smoke_gen2_x1 1
.\scripts\sim_questa.ps1 smoke_gen2_x2 2
.\scripts\sim_questa.ps1 smoke_gen2_x4 4
```

Uses built-in `-L mtiUvm` (match `UVM_HOME` to uvm-1.1d). Lane width is a **compile-time** `+define+RIVET_TB_LANES=N`.

| Tool | Version |
|------|---------|
| QuestaSim | 2024.1 (local) |
| UVM | mtiUvm / 1.1d |
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
