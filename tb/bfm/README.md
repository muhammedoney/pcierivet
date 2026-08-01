# Vivado BFM side-path (non-UVM)

This track is **complementary** to the UVM environment. It does not replace UVM.

## Stage 1 — PG239 PHY example (current)

Bring-up of the Vivado **PCIe PHY (PG239)** example in Questa: real PHY IP + serial partner model, Gen1 then Gen2 traffic.

**How to run and what it tests:** [pg239_phy/README.md](pg239_phy/README.md)

```powershell
.\scripts\sim_bfm_pg239.ps1
```

## Later stages

1. Connect `rivet_pcie_ctrl` to PG239 PIPE (replace example `phy_ctrl`).
2. PG213 EP example → swap EP for Rivet+PG239 (full EP functional tests).
3. PG213 RP ↔ Rivet+PG239 (system-level).

## Endpoint / RP BFM (generic notes)

1. Place proprietary sources under `third_party/bfm/` or `third_party/xilinx_ip/` (gitignored).
2. Keep Rivet-owned scripts under `tb/bfm/`.
3. Document Vivado version and export steps when first brought up.

## Rules

- Do **not** commit Xilinx encrypted IP, BFM netlists, or Vivado project caches.
- Any BFM failure that indicates a DUT bug should also be tracked in UVM.
