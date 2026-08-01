# Rivet

**Rivet** is an open PCIe soft IP: a multi-mode **controller** plus family **PHY** wrappers, delivered as a full **`rivet_pcie`** soft IP for FPGA (ASIC later, backlog).

## Terminology

| Layer | Module | Boundary |
|-------|--------|----------|
| Controller | `rivet_pcie_ctrl` | AXI-ST + `cfg_mgmt` (PG213-style) ↔ **PIPE** |
| PHY | `rivet_pcie_phy_*` | PIPE ↔ serial (Xilinx **PG239**) |
| Full IP | `rivet_pcie` | Controller + PHY for integrators |

### PCIe stack and Rivet boundaries

Where each layer, interface, and vendor product sits in the stack:

```text
                        ┌───────────────────────────────────────┐
                        │            User application            │
                        │            (FPGA PL logic)             │
                        └───────────────────────────────────────┘
      user boundary ===== AXI-ST CQ/CC/RQ/RC + cfg_mgmt (PG213-style) =====
   (Xilinx PG213 IP is    │                                       │
    the equivalent of     ▼                                       ▼
    this Rivet boundary) ┌─────────────────────────────────────────┐  ┐
                         │ TL  — Transaction Layer                 │  │
                         │      TLP assembly, flow control,        │  │
                         │      ┌───────────────────────────────┐  │  │
                         │      │ Config Space (Type 0 for EP)  │  │  │
                         │      └───────────────────────────────┘  │  │
                         ├─────────────────────────────────────────┤  │  rivet_pcie_ctrl
                         │ DLL — Data Link Layer                   │  │  (soft controller,
                         │      DLLP, ACK/NAK, LCRC, credits       │  │   MODE = EP/RC/USP/DSP,
                         ├─────────────────────────────────────────┤  │   no vendor cells)
                         │ MAC — Media Access Control              │  │
                         │      LTSSM, ordered sets, lane control  │  │
                         └─────────────────────────────────────────┘  ┘
      PHY boundary ======================= PIPE =======================
     (MAC ↔ PHY, per                       │
      Intel PIPE spec)                      ▼
                         ┌─────────────────────────────────────────┐  ┐
                         │ PCS — Physical Coding Sublayer          │  │  rivet_pcie_phy_*
                         │      8b/10b (Gen1/2) or 128b/130b       │  │  wraps
                         │      (Gen3+), scramble, elastic buffer  │  │  ┌────────────────┐
                         ├─────────────────────────────────────────┤  │  │ Xilinx PG239   │
                         │ PMA — Physical Media Attachment         │  │  │ PCIe PHY       │
                         │      SerDes, CDR, TX/RX drivers (GT)    │  │  │ (PCS + PMA)    │
                         └─────────────────────────────────────────┘  ┘  └────────────────┘
                                                │
                                                ▼
                                    serial lanes  ×1 / ×2 / ×4
                                        (pci_exp_tx/rx)

   rivet_pcie = rivet_pcie_ctrl + rivet_pcie_phy_*  (full integrator-facing soft IP)
```

- **AXI-ST + `cfg_mgmt` (PG213-style)** — user boundary. Xilinx **PG213** IP is the closest **functional equivalent to the complete Rivet soft IP**; Rivet aligns config access to PG213 Table 26 (`cfg_mgmt_*`), not AXI-Lite. See the [PG213 interface audit](docs/pg213-interface.md).
- **PIPE** — MAC ↔ PHY boundary (Intel PIPE spec). Rivet's controller talks PIPE; it does not embed the PHY.
- **`rivet_pcie_ctrl`** covers **TL + DLL + MAC** (incl. Config Space), ending at PIPE — no vendor primitives.
- **`rivet_pcie_phy_*`** covers **PCS + PMA** by wrapping Xilinx **PG239** (PIPE ↔ serial).
- **`rivet_pcie`** = controller + PHY, the drop-in full IP.

`MODE` selects Endpoint, Root Complex/Port, Switch USP, or Switch DSP. Current focus: **Endpoint**, **Gen2**, lanes **×1 / ×2 / ×4**. Phase 1 priority: **UVM environment**, then Gen2 link RTL.

## Status

| Area | State |
|------|--------|
| Mode | EP development first (RC / USP / DSP reserved on `MODE`) |
| Generation | **Gen2 active** → Gen3 → Gen4 → Gen5 ([evolution notes](docs/gen-evolution.md)) |
| Lanes | Parametric ×1 / ×2 / ×4 |
| Target FPGA | **VCU118** (**XCVU9P**, UltraScale+ GTY) — primary bring-up |
| Verification | **UVM first** (Phase 1); Verilator CI; Vivado BFM side-path |

Phase 0 stubs + PG239-aligned PIPE ports. Phase 1: grow `tb/uvm`, then Gen2 LTSSM — not Gen3/4 protocol yet.

## Repository layout

```text
rtl/pcie_ctrl/        Soft controller top + rivet_pkg (to PIPE)
  mac/ dll/ tl/       Layer sources (LTSSM/OS, DLLP/FC, TLP/cfg)
rtl/phy/              PG239 family PHY wrappers
rtl/top/              rivet_pcie = ctrl + phy
rtl/interfaces/       PIPE, AXI-ST, cfg_mgmt SV interfaces
tb/uvm/               Primary UVM (DUT = rivet_pcie_ctrl)
tb/bfm/               Vivado BFM side-path (PG239 PHY example first)
```

## Target hardware

| Kit | FPGA | Role |
|-----|------|------|
| **AMD Virtex UltraScale+ VCU118** | **XCVU9P** | **Primary** — native PG239 GTY generate + 52 GTY + PCIe ×16 |
| — | VU3P | PG239 GTY generate OK; fewer GTs / no preferred kit |

PHY path: UltraScale+ (`FPGA_FAMILY=0` → `rivet_pcie_phy_usplus`, PG239 for **VU9P**). Details: [Hardware](docs/hardware.md), [Boards](docs/boards.md).

## Tools

| Tool | Role |
|------|------|
| QuestaSim | UVM regression (local license) |
| Verilator | Lint / smoke (CI) |
| Yosys | Open synth sanity |
| Vivado | PHY IP (PG239 on VU9P) + optional BFM export + VCU118 flows |

## Quick start (Verilator)

```powershell
.\scripts\lint.ps1
.\scripts\sim_verilator.ps1
```

## Quick start (PG239 BFM side-path)

Requires local Vivado `pcie_phy_0_ex` + Questa `compile_simlib`. See [tb/bfm/pg239_phy/README.md](tb/bfm/pg239_phy/README.md).

```powershell
.\scripts\sim_bfm_pg239.ps1
```

## Documentation

- [Architecture](docs/architecture.md)
- [MAC follow-guide](docs/mac.md) — LTSSM, OS, DLL↔MAC, PIPE duties, milestones
- [PIPE notes](docs/pipe-notes.md) — MAC↔PHY digest (Original PIPE / PG239)
- [RTL style](docs/rtl-style.md) — lowRISC-inspired coding rules
- [DO-254 practices](docs/do254-practices.md) — lightweight assurance (no cert claim)
- [Hardware](docs/hardware.md)
- [Boards / PG239 targets](docs/boards.md)
- [Roadmap](docs/roadmap.md)
- [Gen2 → Gen3/4 evolution](docs/gen-evolution.md)
- [PG213-style interface audit](docs/pg213-interface.md)
- [Verification](docs/verification.md)
- [Reference: lowRISC style-guides](docs/ref-lowrisc-style.md) (CC-BY-4.0; local clone)
- [Reference: PCI_Express_Gen7.0](docs/ref-pci-express-gen7.md) (educational; do not copy)
- [Reference: pcievhost](docs/ref-pcievhost.md) (GPL-3 VIP; inspire only)
- [Contributing](CONTRIBUTING.md)

## License

Apache License 2.0 — see [LICENSE](LICENSE).

Specifications are not redistributed; obtain PCIe / PIPE / PG213 / PG239 yourself.

## Support / sponsors / hardware

Early-stage open interconnect IP. **Hardware sponsorship is a real blocker** for FPGA bring-up.

**Most needed:** an **AMD Virtex UltraScale+ VCU118** evaluation kit (**XCVU9P**), or equivalent board loan / donation. VU9P is required so PG239 can be generated and instantiated for the soft PHY path.

Also welcome:

- Sponsorship for simulation tooling (Questa) and related costs
- Review of UVM methodology and PIPE / AXI-ST fidelity
- Other **VU9P-class** UltraScale+ PCIe boards (native PG239 GTY)

If you can ship a board, fund a kit, or connect us to AMD/Xilinx university / open-source hardware programs — please open an issue or reach out. Thank you.
