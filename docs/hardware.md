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

## Sponsorship / lab status

Rivet needs a **VCU118** (or loan/donation). Prefer VU9P-class boards with a PCIe edge connector and native PG239 GTY generation.

**FPGA lab is backlogged** until a board is available. Sim gates (UVM + PG213/PG239 BFM) do not wait on hardware. When the kit arrives:

1. Generate PG239 for XCVU9P Gen2 ×4; wire `rivet_pcie` + constraints ([boards.md](boards.md)).
2. Board gates: `link_up`, BAR0 PIO, optional DMA/RQ.
3. Keep behavioral PHY stub + pad for CI; board project stays out of the soft-IP MVP tag.
