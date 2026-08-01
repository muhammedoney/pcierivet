# third_party/xilinx_ip

**Local only — gitignored** (`third_party/xilinx_ip/**` except this README).

Place Vivado example / generated IP trees here so BFM sims can run from the Rivet repo without depending on `C:\Users\...\vivado\...` paths. **Do not push** these trees.

## Expected layout (after copy)

```text
third_party/xilinx_ip/
  README.md                          ← tracked
  pcie_phy_0_ex/                     ← gitignored (PG239 example)
    imports/                         board.v, phy_ctrl, …
    sim/questa/                      compile.do, …
    pcie_phy_0_ex.gen/
    pcie_phy_0_ex.ip_user_files/
  pcie4_uscale_plus_0_ex/            ← gitignored (PG213 EP example)
    imports/                         board.v, EP, RP, PIO, …
    questa/                          compile.do, …
    pcie4_uscale_plus_0_ex.gen/
    pcie4_uscale_plus_0_ex.ip_user_files/
```

`compile_simlib` output stays outside (or under a local cache path via `RIVET_QUESTA_SIMLIB`) — it is large and machine-specific.

## Refresh from your Vivado trees

```powershell
.\scripts\sync_xilinx_examples.ps1
```

Or set `RIVET_PG239_EX` / `RIVET_PG213_EX` in `scripts/local_paths.ps1` to either this folder or the original Vivado project.
