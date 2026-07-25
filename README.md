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
| Target FPGA | **VCU128** (VU37P, UltraScale+ HBM) — primary bring-up |
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

## Target hardware

| Kit | FPGA | Role |
|-----|------|------|
| **AMD Virtex UltraScale+ HBM VCU128** | **VU37P** | **Primary** FPGA evaluation / bring-up |
| AMD Virtex UltraScale+ 56G PAM4 VCU129-PP | — | Acceptable alternate if VCU128 is unavailable |

PHY path: UltraScale+ (`FPGA_FAMILY=0` → `rivet_pcie_phy_usplus`). Details: [Hardware](docs/hardware.md).

## Tools

| Tool | Role |
|------|------|
| QuestaSim | UVM regression (local license) |
| Verilator | Lint / smoke (CI) |
| Yosys | Open synth sanity |
| Vivado | PHY IP + optional BFM export + VCU128 flows |

## Quick start (Verilator)

```powershell
.\scripts\lint.ps1
.\scripts\sim_verilator.ps1
```

## Documentation

- [Architecture](docs/architecture.md)
- [Hardware](docs/hardware.md)
- [Roadmap](docs/roadmap.md)
- [Verification](docs/verification.md)
- [Contributing](CONTRIBUTING.md)

## License

Apache License 2.0 — see [LICENSE](LICENSE).

Specifications are not redistributed; obtain PCIe / PIPE / PG213 / PG239 yourself.

## Support / sponsors / hardware

Early-stage open interconnect IP. **Hardware sponsorship is a real blocker** for FPGA bring-up.

**Most needed:** an **AMD Virtex UltraScale+ HBM VCU128** evaluation kit (**VU37P**), or equivalent board loan / donation. VCU129-PP is a workable alternate; VCU128 is strongly preferred.

Also welcome:

- Sponsorship for simulation tooling (Questa) and related costs
- Review of UVM methodology and PIPE / AXI-ST fidelity
- Other UltraScale+ PCIe-capable boards if VCU128 is not available

If you can ship a board, fund a kit, or connect us to AMD/Xilinx university / open-source hardware programs — please open an issue or reach out. Thank you.
