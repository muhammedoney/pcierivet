# Reference report: PCI_Express_Gen7.0

**Upstream:** https://github.com/rkingsly2025/PCI_Express_Gen7.0  
**Local clone (gitignored):** `third_party/ref/PCI_Express_Gen7.0`  
**Investigated:** 2026-07-28  
**Author (headers):** Robert Kingsly Amalathas  

## Verdict

Educational toy (~4k LOC SV) with a plausible **layer diagram expressed as modules**. Not silicon-proven, not Gen7-real, not a model for Rivet RTL. Mine **structure and vocabulary** only; do **not** copy behavior or Gen7 claims.

## What it is

| Item | Finding |
|------|---------|
| Claim | “Complete” PCIe 7.0 controller: TL + DLL + PL, AXI4, DMA, MSI/MSI-X, AER |
| Reality | Gen1-like training shortcuts; TB often `MAX_GEN=PCIE_GEN5`; no Gen6/7 protocol |
| License | README says educational/evaluation; **no LICENSE file** in tree — unclear for reuse |
| Language | SystemVerilog only (`rtl/`, `tb/`, `uvm_tb/`) |
| FPGA | None (no synth flow, constraints, board) |
| Sim | `build/tb_pcie_top.vvp` present (iverilog compile); **no VCD / pass log** in tree |

## Layout (useful mental model)

```
rtl/   pcie_ltssm, pcie_dll_tx/rx, pcie_flow_ctrl, pcie_tlp_tx/rx,
       pcie_cfg_space, pcie_axi_bridge, pcie_dma, pcie_controller_top, pcie_pkg
tb/    iverilog + RC BFM that mirrors DUT LTSSM
uvm_tb/ AXI-centric smoke (not PIPE/LTSSM authority)
```

## MAC / LTSSM quality

| Module | Maturity |
|--------|----------|
| `pcie_ltssm.sv` | Toy: TS via fake `pipe_rx_status` codes, not OS symbols; Config width/lane = timer marches |
| DLL TX/RX | Toy: ACK CRC `16'hBEEF`; incomplete replay |
| Flow control | Instant local exchange; no real FC DLLPs on wire |
| TLP / CFG / DMA | Sketches / educational maps |
| PIPE IF | Per-lane ports + K-symbol constants; **no** scrambler, elastic buffer, CDC, real PHY |

RC BFM is **co-designed** with the toy LTSSM (mirrors DUT state) so training “works” without independent OS exchange.

## What Rivet can inspire

1. **Module boundary checklist** for soft ctrl after PIPE: LTSSM | PIPE MAC | DLL TX/RX | FC | TLP | cfg — map to Rivet without AXI memory as user IF.
2. **Classic LTSSM state names** for Gen2 EP: Detect / Polling / Configuration / Recovery / L0 (+ L0s/L1 later).
3. **PIPE as hard ctrl↔PHY contract** (rate, width, powerdown, per-lane data/K) — already Rivet’s model with PG239.
4. **Smoke shape:** wait for link + monitor LTSSM transitions — but Rivet must use an **independent** PIPE peer, not a BFM that peeks DUT state.
5. **Package vocabulary:** TLP fmt/type, DLLP types, OS K-codes — cross-check against specs; do not treat this pkg as authoritative.

## What Rivet must not copy

- Gen7/Gen5 branding while Gen2 is active  
- AXI4 memory-mapped user IF (Rivet = AXI-ST CQ/CC/RQ/RC + `cfg_mgmt_*`)  
- Fake TS training and DUT-mirroring BFM  
- Header lies (scrambler/CDC/BAR/timeout claimed, not implemented)  
- DLL toys (`BEEF` CRC, incomplete replay)  
- Unclear-license RTL into the product tree  
- iverilog compile as substitute for Questa UVM  

## Confidence

**~15–25%** as educational structure; **~0%** silicon/FPGA credibility. Fits the user’s note: far from real code; useful as a negative example of training shortcuts and IF mismatch.
