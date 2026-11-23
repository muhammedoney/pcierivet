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
- **`rivet_pcie_phy_*`** covers **PCS + PMA** by wrapping the family PHY (Xilinx **PG239** / **PG345**).
- **`rivet_pcie`** = controller + PHY, the drop-in full IP.

`MODE` selects Endpoint, Root Complex/Port, Switch USP, or Switch DSP. Gen2 EP, RC, USP, and DSP are in simulation on lanes **×1 / ×2 / ×4**. Next: EP Gen3.

## Status

| Area | State |
|------|--------|
| Mode | Gen2 EP, RC, USP, and DSP closed in sim |
| Generation | **Gen2 port roles closed.** Next: Gen3 ([evolution notes](docs/gen-evolution.md)) |
| Lanes | Parametric ×1 / ×2 / ×4 |
| Target FPGA | **VMK180** preferred, **VCU118** also in tree. VPK180 is the later Premium path |
| Verification | Phase 1 MVP + Phase 2 Full Gen2 EP (sim) closed; Verilator CI; Vivado BFM side-path |

Phase 1/2 Gen2 EP sim gates and Phase 3 Gen2 port roles are closed (see [roadmap](docs/roadmap.md), [verification](docs/verification.md)). Next: Phase 4 EP Gen3.

## Measured throughput

Gen2 x4 posted writes. The blue line is Rivet MemWr32 and the green line is Rivet MemWr64: 8 TLPs per size, infinite credits, ACK on every TLP, printed `mb_s` on the 4 ns user clock. 1 DW is 4 bytes and 1024 DW is 4096 bytes. The two Rivet lines print the same rate at ten of the eleven sizes. At 64 bytes MemWr32 printed 1333.333 MB/s and MemWr64 printed 1347.368 MB/s. Quartus and Xilinx do not publish a Gen2 x4 curve with a number at each of these sizes. Both publish the same two references, drawn as the other lines. The flat line is the symbol rate after 8b/10b, 5 GT/s × 4 lanes × 8/10 = 2000 MB/s. The amber line is the posted-write formula in Xilinx WP350 and Intel AN 456: payload / (payload + 20) × 2000 MB/s. The 20 bytes are STP, the sequence number, a 3-dword header, LCRC, and END. At 256 bytes that formula is 1855 MB/s, the theoretical maximum AN 456 lists for Gen2 x4. On that link AN 456 measured a Stratix IV hard-IP DMA write at 1775 MB/s (64-bit application interface) and 1783 MB/s (128-bit). The square marks 1783 MB/s at 256 bytes. It is one operating point, not a sweep. Rivet’s user port is 64 bits at 4 ns, the same 2000 MB/s as that symbol rate. The 4096-byte point printed 1979.700 MB/s for both MemWr32 and MemWr64. The red line is requester MemRd32 and MemRd64, eight completions per size, CplD payload only. The two read types printed the same rate at every size: 77.670, 146.789, 275.862, 444.444, 695.652, 973.384, 1207.547, 1378.197, 1480.839, 1538.115, and 1568.447 MB/s. The 4096-byte read is 1568.447 MB/s, 78.422% of the symbol rate. That line is completion payload, and the eight-packet window includes one round trip. Detail is in the [performance poster](docs/perf-poster.md).

![Throughput versus payload size. Rivet MemWr32 rates are 250.000, 500.000, 800.000, 1122.807, 1333.333, 1570.552, 1723.906, 1851.718, 1923.005, 1959.809, and 1979.700 MB/s. MemWr64 matches those rates except 1347.368 MB/s at 64 bytes. MemRd32 and MemRd64 printed the same rates: 77.670, 146.789, 275.862, 444.444, 695.652, 973.384, 1207.547, 1378.197, 1480.839, 1538.115, and 1568.447 MB/s. The other lines are the 2000 MB/s Gen2 x4 symbol rate and the WP350 / AN 456 theoretical posted-write rate. The square is the AN 456 Quartus hard-IP DMA write at 1783 MB/s.](docs/perf-rq-sweep.svg)

## Repository layout

```text
rtl/pcie_ctrl/        Soft controller top + rivet_pkg (to PIPE)
  mac/ dll/ tl/       Layer sources (LTSSM/OS, DLLP/FC, TLP/cfg)
rtl/phy/              PG239 / PG345 family PHY wrappers
rtl/top/              rivet_pcie = ctrl + phy
rtl/interfaces/       PIPE, AXI-ST, cfg_mgmt SV interfaces
tb/uvm/               Primary UVM (DUT = rivet_pcie_ctrl)
tb/bfm/               Vivado BFM side-path (PG239 PHY example first)
```

## Target hardware

The lab ask is a **VMK180** first. A **VCU118** still covers the UltraScale+ shell that is already in the tree.

| Kit | FPGA | Notes |
|-----|------|-------|
| **AMD Versal Prime VMK180** | **XCVM1802** | Preferred. PG345 GTY, Gen2 ×4 on quad 103 (`fpga/vmk180`) |
| **AMD Virtex UltraScale+ VCU118** | **XCVU9P** | Also in tree. PG239 GTY (`fpga/vcu118`) |
| **AMD Versal Premium VPK180** | Versal Premium | Later GTYP / Gen5 path. Not a bring-up request |

Sim / RTL default today still exercises the UltraScale+ (`FPGA_FAMILY=0` → `rivet_pcie_phy_usplus`) path. Versal is `FPGA_FAMILY=2` → `rivet_pcie_phy_versal`. Details: [Hardware](docs/hardware.md), [Boards](docs/boards.md).

## Tools

| Tool | Role |
|------|------|
| QuestaSim | UVM regression (local license) |
| Verilator | Lint / smoke (CI) |
| Yosys | Open synth sanity |
| Vivado | PHY IP + optional BFM export + board flows (US+ / Versal as available) |

## Quick start (Verilator)

```powershell
.\scripts\lint.ps1
.\scripts\sim_verilator.ps1
```

## Quick start (PG239 / PG213 BFM side-path)

Requires local Vivado example projects + Questa `compile_simlib`. See [tb/bfm/README.md](tb/bfm/README.md).

```powershell
.\scripts\sim_bfm_pg239.ps1
.\scripts\sim_bfm_pg213.ps1
```

## Archive

`scripts/zip_project.ps1` (or `scripts/zip_project.cmd`) packs the working tree and `.git`, so history stays in the zip. Gitignored files and other regenerable outputs stay out: sim `work/`, logs, waveforms, Vivado `fpga/vcu118/build/`, local BFM binaries, `specs/`, and ignored reference clones.

```powershell
.\scripts\zip_project.ps1
.\scripts\zip_project.cmd D:\rivet-src.zip
```

Default path is next to the repo: `../rivet-src-<timestamp>.zip`.

`fpga/vcu118/pack_transfer.ps1` is a separate zip for a machine that has a Vivado license. It leaves out `.git` unless `-IncludeGit` is set. On that machine, `fpga\vcu118\create_project.cmd` creates the project and `fpga\vcu118\synth.cmd` runs synthesis. See [fpga/vcu118/README.md](fpga/vcu118/README.md).

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

A loan or a donation of one of these kits unblocks the lab. The **VMK180** is the kit we want first.

- **AMD Versal Prime VMK180** (**XCVM1802**, EK-VMK180-G) — preferred. PG345 GTY, Gen2 ×4, project `fpga/vmk180`
- **AMD Virtex UltraScale+ VCU118** (**XCVU9P**, EK-U1-VCU118-G) — second choice. PG239 GTY, project `fpga/vcu118`

Also welcome:

- Sponsorship for simulation tooling (Questa) and related costs
- Review of UVM methodology and PIPE / AXI-ST fidelity
- Other AMD/Xilinx PCIe evaluation boards with a usable edge connector

If you can ship a board, fund a kit, or connect us to AMD/Xilinx university / open-source hardware programs — please open an issue or reach out. Thank you.
