# Target FPGA / board

## Decision (locked)

| Item | Choice |
|------|--------|
| **Primary board** | AMD/Xilinx **VCU118** (EK-U1-VCU118-G) |
| **Primary FPGA** | **XCVU9P** (Virtex UltraScale+), package e.g. `xcvu9p-flga2104-2L-e` (Rev 2.0+, VCCINT 0.85 V) |
| **Transceivers** | **GTY** (52 on VCU118) |
| **PCIe on board** | Edge connector ×16 (Gen1/Gen2 ×16; Gen3 ×16 on Rev 2.0+) |
| **PG239** | Generate PHY for **VU9P** (official GTY generation target), then use on VCU118 |

VCU128 (**XCVU37P** HBM) is **not** a Rivet bring-up target: Vivado does not offer PG239 generation for VU37P, and soft-PHY instantiate/migrate is not a reliable path for this project.

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
| VCU128 | XCVU37P | **No** | Many GTY | ×16 (hard/integrated path; not PG239-first) |
| ZCU102/etc. | ZU* | ZU9EG (GTH) | Fewer | Often ×4 |

Larger US+ parts (VU13P, VU19P, VU37P, …) may have more GTs, but they are **not** PG239 generation targets. Rivet prioritizes **direct PG239 instantiate** over raw GT count on unsupported SKUs.

## PHY wrapper mapping

| Rivet module | Vivado PG239 generate part | Board |
|--------------|----------------------------|-------|
| `rivet_pcie_phy_usplus` | **VU9P** (GTY) | **VCU118** (primary) |
| `rivet_pcie_phy_us` | KU040 / KU115 / VU440 (GTH) | Secondary / legacy |

Default `FPGA_FAMILY` on `rivet_pcie` remains UltraScale+ (0) → US+ / VCU118.

## Bring-up notes

- Create Vivado project with part **XCVU9P** matching the physical VCU118 revision (2L vs 2LV).
- Generate **PCIe PHY (PG239)** with device **VU9P**, GTY, lane width matching Rivet `LANES` (start ×1, then ×2/×4).
- Wire `rivet_pcie` serial ports to the VCU118 PCIe edge GT quads (see UG1224).
- Gen2 ×1/×2/×4 soft-controller validation does not require Gen3 ×16; the ×16 edge still helps host bring-up later.
