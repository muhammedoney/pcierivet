# Rivet architecture

## Terminology (locked)

| Name | Module(s) | Role |
|------|-----------|------|
| **Controller** | `rivet_pcie_ctrl` | Soft PCIe controller. Parameter `MODE` selects EP, RC (root port), USP, or DSP. Ends at **PIPE**. No vendor cells. |
| **PHY** | `rivet_pcie_phy_*` | Family wrapper around Xilinx **PG239** (US/US+) or **PG345** (Versal). PIPE ↔ serial lanes. |
| **PCIe IP (full)** | `rivet_pcie` | Integrator-facing soft IP = **controller + PHY**. |

User application interface on the controller uses **AXI-ST CQ/CC/RQ/RC** and **`cfg_mgmt_*`** naming conventions in the style of Xilinx **PG213**. That is the *user* boundary — not the PHY. There is **no AXI-Lite** user port.

```text
  [ User PL ]
      |  AXI-ST (PG213-style) + cfg_mgmt
      v
  +--------------------+
  | rivet_pcie_ctrl    |   MODE = EP | RC | USP | DSP
  | TL / DL / MAC      |
  +---------+----------+
            | PIPE
            v
  +--------------------+
  | rivet_pcie_phy_*   |   PG239 (US/US+), PG345 (Versal)
  +---------+----------+
            | serial
```

`rivet_pcie` instantiates `u_ctrl` + `u_phy` for FPGA drop-in use. UVM primary DUT remains **`rivet_pcie_ctrl`** at PIPE.

## Modes

| Mode | `MODE` | Status |
|------|--------|--------|
| Endpoint (EP) | 0 | Active — Upstream Port, Type 0. Gen2 sim closed |
| Root Complex / Root Port (RC) | 1 | Next — Downstream LTSSM, then Type 1, then config requester |
| Switch Upstream Port (USP) | 2 | Alias of the Upstream port. Proved after RC |
| Switch Downstream Port (DSP) | 3 | Alias of the Downstream port. No config master |

Generation roadmap: **Gen2 (active)** → Gen3 → Gen4 → Gen5.

## Primary FPGA / board (locked)

| Item | Choice |
|------|--------|
| Board | **VCU118** (US+ primary), **VMK180** (Versal primary) |
| FPGA | **XCVU9P** (PG239 GTY), **XCVM1802** (PG345 GTY) |

Every current development step targets **Gen2**; Gen3/4 deltas per module: [gen-evolution.md](gen-evolution.md).

## Parameters

| Parameter | Values | Notes |
|-----------|--------|-------|
| `MODE` | EP / RC / USP / DSP | EP+USP Upstream Type 0; RC+DSP Downstream Type 1; RC requester is Phase 3 |
| `GEN` | **`2` now** | Stub/checks enforce Gen2 until Phase 3+ |
| `LANES` | `1`, `2`, `4` | All first-class; smoke starts at 1 |
| `FPGA_FAMILY` | 0=US+, 1=US, 2=Versal | On `rivet_pcie` / PHY only. US+ bring-up **VCU118 / XCVU9P**. Versal bring-up **VMK180 / XCVM1802**. |
| `PIPE_DATA_WIDTH` | `16` now | 32 Gen3 / 64 Gen4 US+ later |

## MAC and PIPE

Controller MAC (LTSSM, ordered sets, PIPE adapter) sits between DLL and PIPE. Implementation checklist: [mac.md](mac.md). PIPE TX/RX / elastic-buffer concepts for Rivet: [pipe-notes.md](pipe-notes.md). Data Link (DLLP, FC, LCRC): [dll.md](dll.md).

Layer sources live under `rtl/pcie_ctrl/mac/`, `dll/`, and `tl/`; `rivet_pcie_ctrl.sv` remains the integrating top.

## References (not redistributed)

- PCI Express Base Specification
- Intel **PIPE** (PHY Interface for PCI Express / SATA / USB architectures) — PG239 does **not** name a revision; Rivet targets the classic/original PIPE signal set. Prefer **PIPE 4.4.1** (Gen1–Gen4) and optionally **PIPE 5.x** for Gen5 notes. Keep under local `specs/`.
- Xilinx PG213 (AXI-ST interface conventions for the *user* side — not PIPE)
- Xilinx PG239 (PCIe PHY — wrapped by `rivet_pcie_phy_*`; authoritative for AMD assist/EQ ports)
