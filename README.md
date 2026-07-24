# Rivet

**Rivet** is an open PCIe soft IP: a multi-mode **controller** plus family **PHY** wrappers, delivered as a full **`rivet_pcie`** soft IP for FPGA (ASIC later, backlog).

## Terminology

| Layer | Module | Boundary |
|-------|--------|----------|
| Controller | `rivet_pcie_ctrl` | AXI-ST (PG213-style) + AXI-Lite ↔ **PIPE** |
| PHY | `rivet_pcie_phy_*` | PIPE ↔ serial (Xilinx **PG239**) |
| Full IP | `rivet_pcie` | Controller + PHY for integrators |

`MODE` selects Endpoint, Root Complex/Port, Switch USP, or Switch DSP. Current focus: **Endpoint**, **Gen2**, lanes **×1 / ×2 / ×4**.

## Status

| Area | State |
|------|--------|
| Mode | EP development first (RC / USP / DSP reserved on `MODE`) |
| Generation | Gen2 now → Gen4 → Gen5 |
| Lanes | Parametric ×1 / ×2 / ×4 |
| Verification | UVM on controller @ PIPE; Verilator CI; Vivado BFM side-path |

Phase 0: stubs, interfaces, UVM skeleton, tool hooks — not full protocol RTL yet.

## Repository layout

```text
rtl/pcie_ctrl/   Soft controller (to PIPE)
rtl/phy/         PG239 family PHY wrappers
rtl/top/         rivet_pcie = ctrl + phy
rtl/interfaces/  PIPE, AXI-ST, AXI-Lite SV interfaces
tb/uvm/          Primary UVM (DUT = rivet_pcie_ctrl)
tb/bfm/          Vivado RP/EP BFM side-path
```

## Tools

| Tool | Role |
|------|------|
| QuestaSim | UVM regression (local license) |
| Verilator | Lint / smoke (CI) |
| Yosys | Open synth sanity |
| Vivado | PHY IP + optional BFM export |

## Quick start (Verilator)

```powershell
.\scripts\lint.ps1
.\scripts\sim_verilator.ps1
```

## Documentation

- [Architecture](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Verification](docs/verification.md)
- [Contributing](CONTRIBUTING.md)

## License

Apache License 2.0 — see [LICENSE](LICENSE).

Specifications are not redistributed; obtain PCIe / PIPE / PG213 / PG239 yourself.

## Support / sponsors / hardware

Early-stage project. Help welcome:

- Spare UltraScale or UltraScale+ PCIe boards
- Sponsorship for tooling and hardware
- Review of UVM methodology and PIPE / AXI-ST fidelity

Thank you for supporting open interconnect IP.
