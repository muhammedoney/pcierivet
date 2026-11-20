# Target FPGA / board

## Decision (locked)

| Item | Choice |
|------|--------|
| **Primary board** | AMD/Xilinx **VCU118** (EK-U1-VCU118-G) |
| **Primary FPGA** | **XCVU9P** (Virtex UltraScale+), package e.g. `xcvu9p-flga2104-2L-e` (Rev 2.0+, VCCINT 0.85 V) |
| **Transceivers** | **GTY** (52 on VCU118) |
| **PCIe on board** | Edge connector ×16 (Gen1/Gen2 ×16; Gen3 ×16 on Rev 2.0+) |
| **PG239** | Generate PHY for **VU9P** (official GTY generation target), then use on VCU118 |

## Why VCU118 / VU9P

PG239 (PCI Express PHY) can only be *generated* in Vivado for a short list of parts ([PG239 Introduction](https://docs.amd.com/r/en-US/pg239-pcie-phy/Introduction)):

| Family | Generation part | Transceiver |
|--------|-----------------|-------------|
| UltraScale+ | **VU9P**, VU3P | GTY |
| UltraScale+ | ZU9EG | GTH |
| UltraScale | KU040, KU115, VU440 | GTH |

Among **official GTY generation** devices, **VU9P** has the largest transceiver budget and a production eval kit with a real PCIe edge connector:

| Board | FPGA | PG239 native generate? | GT (board) | PCIe edge |
|-------|------|-------------------------|------------|-----------|
| **VCU118** | **XCVU9P** | **Yes (VU9P)** | **52 GTY** | ×16 |
| — | VU3P | Yes | Fewer GTY | No common ×16 kit like VCU118 |
| ZCU102/etc. | ZU* | ZU9EG (GTH) | Fewer | Often ×4 |

Larger US+ parts may have more GTs, but Rivet prioritizes **direct PG239 instantiate** on official generation targets.

## PHY wrapper mapping

| Rivet module | Vivado PG239 generate part | Board |
|--------------|----------------------------|-------|
| `rivet_pcie_phy_usplus` | **VU9P** (GTY) | **VCU118** (primary) |
| `rivet_pcie_phy_us` | KU040 / KU115 / VU440 (GTH) | Secondary / legacy |

Default `FPGA_FAMILY` on `rivet_pcie` remains UltraScale+ (0) → US+ / VCU118.

## Versal primary (locked)

| Item | Choice |
|------|--------|
| **Primary board** | AMD **VMK180** (EK-VMK180-G) |
| **Primary FPGA** | **XCVM1802** (Versal Prime), Vivado part `xcvm1802-vsva2197-2MP-e-S` |
| **Transceivers** | **GTY** (44 on VMK180, 11 quads) |
| **PCIe on board** | Edge connector ×8 (Gen1–Gen4). Gen2 ×4 uses quad 103, lanes 0–3 |
| **PHY IP** | **PG345** (`pcie_phy_versal`). The GT quad sits outside the PHY |
| **Quad LOC** | `GTY_QUAD_X0Y3` (quad 103). Refclk `GTY_REFCLK_X0Y6` (W39/W40, 100 MHz) |

VPK180 (Versal Premium, GTYP) remains the Gen5 kit. Gen2 ×4 on VMK180 GTY matches the active generation, and PG345 on GTY already reaches Gen4 ×8.

Lab project: `fpga/vmk180/create_project.tcl` (part **XCVM1802-VSVA2197-2MP-E-S**, PG345 Gen2 ×4). Generated IP stays in `fpga/vmk180/build/` (gitignored). Slot PERST# is PMC MIO38, so the PL shell uses SW4 as the lab reset until a CIPS forward exists.

`FPGA_FAMILY`: 0 = UltraScale+, 1 = UltraScale, 2 = Versal. Simulation default stays 0.

| Rivet module | Vendor PHY | Board |
|--------------|------------|-------|
| `rivet_pcie_phy_usplus` | PG239, VU9P (GTY) | **VCU118** |
| `rivet_pcie_phy_us` | PG239, KU040 / KU115 / VU440 (GTH) | Secondary / legacy |
| `rivet_pcie_phy_versal` | PG345, XCVM1802 (GTY) | **VMK180** |

`rivet_pcie_phy_wrap` is the board select (`RIVET_BOARD_VCU118` or `RIVET_BOARD_VMK180`), in the same role as Wupper `pcie_ep_wrap` / `CARD_TYPE`. The controller still presents 16-bit Gen2 PIPE. PG345's per-lane controls are expanded in that wrapper.

## Bring-up notes

- Create the VCU118 project with `fpga/vcu118/create_project.tcl` (part **XCVU9P-FLGA2104-2L-E**, PG239 Gen2 ×4 on edge lanes 0–3). See `fpga/vcu118/README.md`.
- Create the VMK180 project with `fpga/vmk180/create_project.tcl` (part **XCVM1802-VSVA2197-2MP-E-S**, PG345 Gen2 ×4 on quad 103). See `fpga/vmk180/README.md`.
- Generated IP and the vendor projects stay local (`fpga/vcu118/build/`, `fpga/vmk180/build/`, gitignored).
- Gen2 ×1/×2/×4 soft-controller validation does not require Gen3 ×16; the ×16 edge still helps host bring-up later.

## Agilex compile check (not a PIPE board)

`fpga/agi027/` targets the **DK-DEV-AGI027-RA-B** (device **AGIB027R29A1E1VB**) only to elaborate `rivet_pcie_ctrl`. The kit PCIe edge is R-tile 14C PIPE 5.1 SerDes, not 16-bit Gen2 PIPE, so the project assigns no edge pins. See `fpga/agi027/README.md`. The Quartus project directory is `fpga/agi027/build/` (gitignored).
