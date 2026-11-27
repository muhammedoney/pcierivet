# Target hardware

Preferred bring-up kit:

| Item | Value |
|------|-------|
| Kit | AMD Versal Prime Series **VMK180** Evaluation Kit (EK-VMK180-G) |
| FPGA | **XCVM1802** (Versal Prime, GTY) |
| Example Vivado part | `xcvm1802-vsva2197-2MP-e-S` |
| PHY IP | **PG345** generated for XCVM1802 GTY, Gen2 ×4. `create_project.cmd 4 ep` asks for `link_speed 4` |
| Edge | ×8 PCIe, lanes 0–3 on quad 103 (`GTY_QUAD_X0Y3`) |

VPK180 is the later Premium / GTYP / Gen5 kit. The no-argument project is still Gen2 x4. `fpga/build_gen4_ep.ps1` builds the Gen4 EP x4 lab image for both kits. Gen3 and the other port roles stay a later plan.

| Command | Image |
|---------|--------|
| no arguments | Gen2 x4 EP, `fpga/<board>/build/` |
| `4 ep` | Gen4 x4 EP, `fpga/<board>/build/gen4_ep/` |

## UltraScale+ (second choice)

| Item | Value |
|------|-------|
| Kit | AMD Virtex UltraScale+ FPGA **VCU118** Evaluation Kit (EK-U1-VCU118-G) |
| FPGA | **XCVU9P** (UltraScale+, GTY) |
| Example Vivado part | `xcvu9p-flga2104-2L-e` (Rev 2.0+, VCCINT 0.85 V) |
| PHY | `rivet_pcie_phy_soft` on GTYE4 quad 227. PG239 is not the VCU118 PHY. |
| Board GTs | 52 GTY (16 on PCIe ×16 edge) |

Full rationale, PG239 device list, and PHY mapping: [boards.md](boards.md). The project for this kit is `fpga/vcu118/`.

`fpga/agi027/` is a Quartus compile check of the soft controller on a DK-DEV-AGI027-RA-B (AGIB027R29A1E1VB). It is not a board PHY: the kit edge is R-tile PIPE SerDes.

## Sponsorship / lab status

The kit we need first is a **VMK180** (EK-VMK180-G, **XCVM1802**), on loan or as a donation. A **VCU118** (EK-U1-VCU118-G, **XCVU9P**) is the second choice and still covers the UltraScale+ shell.

**FPGA lab is backlogged** until a board is available. Sim gates (UVM + PG213/PG239 BFM) do not wait on hardware. When the kit arrives:

1. On a VMK180, generate PG345 for XCVM1802 and use `fpga/vmk180`. On a VCU118, use `fpga/vcu118` with `rivet_pcie_phy_soft` (GTYE4). PG239 is not generated for that project.
2. Board gates: `link_up`, BAR0 PIO, optional DMA/RQ.
3. Keep behavioral PHY stub + pad for CI; board project stays out of the soft-IP MVP tag.
