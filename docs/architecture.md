# Rivet architecture

## Terminology (locked)

| Name | Module(s) | Role |
|------|-----------|------|
| **Controller** | `rivet_pcie_ctrl` | Soft PCIe controller. Parameter `MODE` selects EP, RC (root port), USP, or DSP. Ends at **PIPE**. No vendor cells. |
| **PHY** | `rivet_pcie_phy_*` | Family-specific wrapper around Xilinx **PCIe PHY (PG239)**. PIPE ↔ serial lanes. |
| **PCIe IP (full)** | `rivet_pcie` | Integrator-facing soft IP = **controller + PHY**. |

User application interface on the controller uses **AXI-ST CQ/CC/RQ/RC** naming conventions in the style of Xilinx **PG213**, plus **AXI-Lite** for config. That is the *user* boundary — not the PHY.

```text
  [ User PL ]
      |  AXI-ST (PG213-style) + AXI-Lite
      v
  +--------------------+
  | rivet_pcie_ctrl    |   MODE = EP | RC | USP | DSP
  | TL / DL / MAC      |
  +---------+----------+
            | PIPE
            v
  +--------------------+
  | rivet_pcie_phy_*   |   PG239 family wrap
  +---------+----------+
            | serial
```

`rivet_pcie` instantiates `u_ctrl` + `u_phy` for FPGA drop-in use. UVM primary DUT remains **`rivet_pcie_ctrl`** at PIPE.

## Modes

| Mode | `MODE` | Status |
|------|--------|--------|
| Endpoint (EP) | 0 | Active development |
| Root Complex / Root Port (RC) | 1 | Reserved |
| Switch Upstream Port (USP) | 2 | Reserved |
| Switch Downstream Port (DSP) | 3 | Reserved |

Generation roadmap: **Gen2 (active)** → Gen3 → Gen4 → Gen5.  
Every current development step targets **Gen2**; Gen3/4 deltas per module: [gen-evolution.md](gen-evolution.md).

## Parameters

| Parameter | Values | Notes |
|-----------|--------|-------|
| `MODE` | EP first | RC/USP/DSP compile-gated later |
| `GEN` | **`2` now** | Stub/checks enforce Gen2 until Phase 3+ |
| `LANES` | `1`, `2`, `4` | All first-class; smoke starts at 1 |
| `FPGA_FAMILY` | 0=US+, 1=US | On `rivet_pcie` / PHY only; primary bring-up **VCU128 / VU37P** (US+) |
| `PIPE_DATA_WIDTH` | `16` now | 32 Gen3 / 64 Gen4 US+ later |

## References (not redistributed)

- PCI Express Base Specification
- Intel **PIPE** (PHY Interface for PCI Express / SATA / USB architectures) — PG239 does **not** name a revision; Rivet targets the classic/original PIPE signal set. Prefer **PIPE 4.4.1** (Gen1–Gen4) and optionally **PIPE 5.x** for Gen5 notes. Keep under local `specs/`.
- Xilinx PG213 (AXI-ST interface conventions for the *user* side — not PIPE)
- Xilinx PG239 (PCIe PHY — wrapped by `rivet_pcie_phy_*`; authoritative for AMD assist/EQ ports)
