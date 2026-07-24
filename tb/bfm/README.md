# Vivado BFM side-path (non-UVM)

This track is **complementary** to the UVM environment. It does not replace UVM.

## Endpoint development

1. In Vivado, generate / export the **Root Port BFM** for simulation.
2. Place proprietary sources under `third_party/bfm/` (gitignored binaries).
3. Build a QuestaSim project that connects:
   - Vivado RP BFM (host side)
   - `rivet_pcie_ctrl` (PIPE) or `rivet_pcie` (full IP) as DUT
4. Keep scripts and file lists under `tb/bfm/` once the export flow is proven.

## Root Complex development (later)

Mirror the flow with the **Endpoint BFM** against Rivet RC (`MODE=RC`).

## Rules

- Do **not** commit Xilinx encrypted IP, BFM netlists, or Vivado project caches.
- Document exact Vivado version and export steps when first brought up.
- Any BFM failure that indicates a DUT bug should also be tracked in UVM.
