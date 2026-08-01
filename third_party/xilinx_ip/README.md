# Local Xilinx PHY (PG239) / PCIe (PG213) generated IP may live here for FPGA builds.

`scripts/sim_bfm_pg239.ps1` / `sim_bfm_pg213.ps1` create junctions:
- `pcie_phy_0_ex` → `RIVET_PG239_EX`
- `pcie4_uscale_plus_0_ex` → `RIVET_PG213_EX`

so examples appear under this tree without copying IP into git.

Do not commit encrypted netlists or `.xci` with proprietary payload to the public tree without review. Prefer documenting generation steps in `docs/` and regenerating IP in CI/board flows.
