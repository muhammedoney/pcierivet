# Rivet architecture

## Terminology (locked)

| Name | Module(s) | Role |
|------|-----------|------|
| **Controller** | `rivet_pcie_ctrl` | Soft PCIe controller. Parameter `MODE` selects EP, RC (root port), USP, or DSP. Ends at **PIPE**. No vendor cells. |
| **PHY** | `rivet_pcie_phy_soft` on VCU118; `rivet_pcie_phy_versal` on VMK180 | VCU118 PMA is `GTYE4_CHANNEL` / `GTYE4_COMMON`. Versal stays **PG345**. PIPE ↔ serial lanes. |
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
  | rivet_pcie_phy_soft|   VCU118 GTYE4. Versal stays PG345.
  +---------+----------+
            | serial
```

`rivet_pcie` instantiates `u_ctrl` + `u_phy` for FPGA drop-in use. UVM primary DUT remains **`rivet_pcie_ctrl`** at PIPE.

## Modes

| Mode | `MODE` | Status |
|------|--------|--------|
| Endpoint (EP) | 0 | Upstream Port, Type 0. Gen2 through Gen4 x4 sim closed |
| Root Complex / Root Port (RC) | 1 | Downstream Port, Type 1, config requester. Gen2 through Gen4 x4 sim closed |
| Switch Upstream Port (USP) | 2 | Same Upstream port as EP. Gen2 through Gen4 x4 sim closed. Posted MemWr forwarder is `rtl/switch/` |
| Switch Downstream Port (DSP) | 3 | Same Downstream port as RC, without the config master. Gen2 through Gen4 x4 sim closed |

Generation roadmap: **Gen2 (default elaboration)** → Gen3 x4 in simulation → **Gen4 x4 in simulation** → Gen5 not started.

## Primary FPGA / board (locked)

| Item | Choice |
|------|--------|
| Board | **VCU118** (US+ primary), **VMK180** (Versal primary) |
| FPGA | **XCVU9P** (soft PHY, GTYE4), **XCVM1802** (PG345 GTY) |

Default elaboration stays **Gen2**. Gen3 and Gen4 x4 (EP, RC, USP, DSP) are in simulation; Gen5 is not started. Deltas: [gen-evolution.md](gen-evolution.md).

## Parameters

| Parameter | Values | Notes |
|-----------|--------|-------|
| `MODE` | EP / RC / USP / DSP | EP+USP Upstream Type 0; RC+DSP Downstream Type 1; RC is the config requester |
| `GEN` | **`2` default** | `3` and `4` elaborate in simulation. Gen5 is not started. |
| `LANES` | `1`, `2`, `4` | All first-class; smoke starts at 1 |
| `FPGA_FAMILY` | 0=US+, 1=US, 2=Versal | On `rivet_pcie` / PHY only. US+ bring-up **VCU118 / XCVU9P**. Versal bring-up **VMK180 / XCVM1802**. |
| `PIPE_DATA_WIDTH` | `16` at Gen2 | `32` at Gen3, `64` at Gen4 US+. User AXI-ST is 64 / 128 / 256 bits on that same step |

## MAC and PIPE

Controller MAC (LTSSM, ordered sets, PIPE adapter) sits between DLL and PIPE. Implementation checklist: [mac.md](mac.md). PIPE TX/RX / elastic-buffer concepts for Rivet: [pipe-notes.md](pipe-notes.md). Data Link (DLLP, FC, LCRC): [dll.md](dll.md).

Layer sources live under `rtl/pcie_ctrl/mac/`, `dll/`, and `tl/`; `rivet_pcie_ctrl.sv` remains the integrating top.

## References (not redistributed)

- PCI Express Base Specification
- Intel **PIPE** (PHY Interface for PCI Express / SATA / USB architectures) — PG239 does **not** name a revision; Rivet targets the classic/original PIPE signal set. Prefer **PIPE 4.4.1** (Gen1–Gen4) and optionally **PIPE 5.x** for Gen5 notes. Keep under local `specs/`.
- Xilinx PG213 (AXI-ST interface conventions for the *user* side — not PIPE)
- Xilinx PG239 (PCIe PHY — wrapped by `rivet_pcie_phy_*`; authoritative for AMD assist/EQ ports)
