# third_party/xilinx_ip

Local Xilinx PHY (PG239) generated IP may live here for FPGA builds.

`scripts/sim_bfm_pg239.ps1` creates a junction `pcie_phy_0_ex` → your Vivado example project (`RIVET_PG239_EX`) so the example appears under this tree without copying IP into git.

Do not commit encrypted netlists or `.xci` with proprietary payload to the public tree without review. Prefer documenting generation steps in `docs/` and regenerating IP in CI/board flows.
