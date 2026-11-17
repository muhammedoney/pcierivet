# Stratix 10 GX Gen2 Endpoint (DK-DEV-1SGX-L-A)

Additional Intel board for Rivet. The kit is the **Stratix 10 GX FPGA Development Kit** sold by Terasic (archive No. 1068) and by Altera as **DK-DEV-1SGX-L-A**. Device **1SG280LU2F50E2VG** (L-tile). The older user-guide photograph lists 1SG280LU3F50E3VGS1; the pinout is the same L-tile board.

The edge connector is PCIe Gen3 x16. This project uses Gen2 x4, which is the active Rivet generation. The soft controller stays the MAC. The PHY is the L/H-tile Native PHY in PIPE mode (`altera_xcvr_native_s10_htile`), not the hard IP.

Cyclone 10 GX remains the Intel primary. This tree is the lab project for the Stratix 10 kit.

## What the shell does

`fpga/s10gx/rtl/rivet_s10gx_ep.sv` is the project top. It instantiates `rivet_pcie_ctrl` (Gen2, x4, PIO on BAR0) and `rivet_s10gx_link`. The link wrapper is written by `create_project.tcl` after Platform Designer generates the ATX PLL, the Native PHY, and the reset controller.

Gen2 PIPE with the simplified data interface off uses an 80-bit word per lane. The L-tile map is not the Arria 10 128-bit map: the second byte starts at bit 11, rate is bits [33:32], and rxpolarity is bit 34. Logical lane 0 is edge lane 0 and the PCS bonding master.

Set the presence-detect DIP **SW2** to x4 or x16 before inserting the card. x1 leaves the link narrower than this endpoint.

## Pins

From UG-683674 and the Intel `s10_pcie_devkit_pr.qsf`.

| Signal | Pin | Note |
|--------|-----|------|
| refclk | AK41 / AK40 | Slot 100 MHz HCSL |
| lane 0 TX / RX | BJ46, BH41 | |
| lane 1 | BF45, BJ43 | |
| lane 2 | BG47, BG43 | |
| lane 3 | BE47, BE43 | |
| clk50 | BH33 | CLK_FPGA_50M, reset sequencer and heartbeat |
| PERST# | AJ34 | active-low, 3.0 V |
| CPU_RESETn | A20 | S4, active-low |
| USER_PB0 | B20 | S5, active-low |
| LED G0..G3 | B19, E17, D18, D19 | light when driven low |

VCCR_GXB / VCCT_GXB are set to 1.1 V in both the PHY and the pin assignments. The kit can be strapped to 1.0 V; if the fitter reports a supply mismatch, change both to `1_0V`.

## LEDs

| LED | Meaning |
|-----|---------|
| G0 | `link_up` |
| G1 | PHY reset-controller ready |
| G2 | heartbeat from the 50 MHz clock |
| G3 | LTSSM is L0 |

## Build

Quartus Prime Pro with Stratix 10 device support:

```text
fpga\s10gx\create_project.cmd
fpga\s10gx\impl.cmd
```

The project file is `fpga/s10gx/build/rivet_s10gx.qpf`. The bitstream is `fpga/s10gx/build/output_files/rivet_s10gx.sof`. Generated IP is not committed.

Program over the on-board USB Blaster II. The SOF includes the kit SmartVID settings (LTM4677 at PMBus address 0x4F). Power the board from the slot with the ATX auxiliaries, or from the brick, not both.
