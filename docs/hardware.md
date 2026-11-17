# Target hardware

Primary bring-up platform (locked):

| Item | Value |
|------|-------|
| Kit | AMD Virtex UltraScale+ FPGA **VCU118** Evaluation Kit (EK-U1-VCU118-G) |
| FPGA | **XCVU9P** (UltraScale+, GTY) |
| Example Vivado part | `xcvu9p-flga2104-2L-e` (Rev 2.0+, VCCINT 0.85 V) |
| PG239 generate part | **VU9P** (official GTY target) |
| Board GTs | 52 GTY (16 on PCIe ×16 edge) |

Full rationale, PG239 device list, and PHY mapping: [boards.md](boards.md).

## Versal primary

| Item | Value |
|------|-------|
| Kit | AMD Versal Prime Series **VMK180** Evaluation Kit (EK-VMK180-G) |
| FPGA | **XCVM1802** (Versal Prime, GTY) |
| Example Vivado part | `xcvm1802-vsva2197-2MP-e-s` |
| PHY IP | **PG345** generated for XCVM1802 GTY, Gen2 ×4 |
| Edge | ×8 PCIe, lanes 0–3 on quad 103 (`GTY_QUAD_X0Y3`) |

VPK180 is the later Premium / GTYP / Gen5 kit. The in-tree Versal project is `fpga/vmk180/`.

## Intel primary

| Item | Value |
|------|-------|
| Kit | Altera Cyclone 10 GX FPGA Development Kit (**DK-DEV-10CX220-B**) |
| FPGA | **10CX220YF780E5G** |
| PHY IP | Quartus Native PHY in PIPE Gen2 ×4 (not the hard IP) |
| Edge | Gen2 ×4, lanes 0–3 on banks 1C/1D, refclk R24/R23 |

Agilex 5 is not this target: it has no PIPE mode, so the soft controller cannot drive it. The in-tree project is `fpga/c10gx/`. DK-DEV-10CX220-B was in stock at DigiKey and Mouser at $2,999 when this board was locked.

## Sponsorship / lab status

Rivet needs a **VCU118**, a **VMK180**, or a **DK-DEV-10CX220-B** (or loan/donation). Prefer a VU9P-class board with a PCIe edge and native PG239 GTY generation, the VMK180 for the PG345 path, or the Cyclone 10 GX kit for the Native PHY PIPE path. The Stratix 10 GX kit (**DK-DEV-1SGX-H-A**) is an additional lab target in `fpga/s10gx/`; it uses the same soft controller on the H-tile Native PHY.

**FPGA lab is backlogged** until a board is available. Sim gates (UVM + PG213/PG239 BFM) do not wait on hardware. When the kit arrives:

1. Generate the PHY for the board in hand: PG239 on XCVU9P, PG345 on XCVM1802, or the Native PHY on 10CX220. Wire the matching shell (`fpga/vcu118`, `fpga/vmk180`, or `fpga/c10gx`).
2. Board gates: `link_up`, BAR0 PIO, optional DMA/RQ.
3. Keep behavioral PHY stub + pad for CI; board project stays out of the soft-IP MVP tag.
