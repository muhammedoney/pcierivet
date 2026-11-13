# Cyclone 10 GX Gen2 Endpoint (DK-DEV-10CX220-B)

Intel primary for Rivet. The kit is the production **Cyclone 10 GX FPGA Development Kit**, ordering code **DK-DEV-10CX220-B**, device **10CX220YF780E5G**.

The edge connector is PCIe Gen2 x4. That is the active Rivet generation, and this device still has a **Native PHY PIPE** mode so the soft controller stays the MAC. Agilex 5 kits are newer, and some are cheaper, but Agilex 5 has no PIPE mode: only the hard IP, which would replace `rivet_pcie_ctrl`. They are not this path.

## Buy

Checked while this tree was added:

| Kit | Device | PIPE for a soft MAC | Edge | Street price | Stock |
|-----|--------|---------------------|------|--------------|-------|
| **DK-DEV-10CX220-B** | **10CX220YF780E5G** | **Yes, Native PHY Gen2 x4** | **Gen2 x4** | **$2,999** | DigiKey (34), Mouser (9) |
| Terasic DE5a-Net-DDR4 | Arria 10 GX | Yes, same PHY IP | Gen3 x8 | $5,000 | Terasic |
| Terasic Atum A5 / Agilex 5 E-series kits | Agilex 5 | No | Gen3/Gen4 | about $2,000–$4,200 | Varies |
| DK-DEV-10CX220-A | same family | Yes | Gen2 x4 | discontinued | none (replaced by -B) |

Quartus Prime Pro is the tool. Generated IP stays in `fpga/c10gx/build/` and is not committed.

## What the shell does

`fpga/c10gx/rtl/rivet_c10gx_ep.sv` is the project top. It instantiates `rivet_pcie_ctrl` (Gen2, x4, PIO on BAR0) and `rivet_c10gx_link`. The link wrapper is written by `create_project.tcl` after Platform Designer generates the ATX PLL, the Native PHY, and the reset controller. That wrapper is not in git.

Gen2 PIPE with the simplified data interface **off** uses a 128-bit word per lane. The shell packs Rivet's 16-bit symbols into that word the way the Arria 10 / Cyclone 10 GX PHY user guide specifies (byte serializer x2):

- low byte `[7:0]`, K `[8]`, compliance `[9]`, elecidle `[10]`
- high byte `[29:22]`, K `[30]`, compliance `[31]`, elecidle `[32]`
- detectrx `[46]`, powerdown `[48:47]`, margin `[51:49]`, deemph `[52]`, swing `[53]`
- RX data `[7:0]` and `[39:32]`, K `[8]` and `[40]`, phystatus `[65]`, rxvalid `[66]`, rxstatus `[69:67]`

Logical lane 0 is edge lane 0, which is physical channel 4 of bank 1C. That channel is a legal PCS bonding master, so the IP is told to use master 0. `create_project.tcl` aborts if the generated `tx_parallel_data` / `rx_parallel_data` width is not 512, and it writes the real port list to `fpga/c10gx/build/ip/ports.txt`.

Gen3 equalization ports are tied off. `pipe_rate[1:0]` follows the controller. Bit `[2]` is unused while Gen2 is the active generation.

## Pins

From the kit `golden_top.qsf` and UG-20105. Complements are `(n)` assignments, not extra HDL ports.

| Signal | Pin | Bank |
|--------|-----|------|
| refclk | R24 / R23 | 1D bottom refclk, 100 MHz |
| lane 0 TX / RX | W28/W27, V26/V25 | 1C ch4 |
| lane 1 | U28/U27, T26/T25 | 1C ch5 |
| lane 2 | R28/R27, P26/P25 | 1D ch0 |
| lane 3 | N28/N27, M26/M25 | 1D ch1 |
| clk50 | J23 | free-running 50 MHz, reset sequencer and heartbeat |
| PERST# | AB11 | active-low, 1.8 V, from the edge |
| FPGA_RESETn | AC12 | active-low, from the MAX 10 |
| USER_PB0 (S8) | AE4 | treated as active-low |
| LED0..3 | AF6, AE6, AC6, AC7 | D19..D22, '1' lights the LED |

On-chip refclk termination is `AC_COUPLING`, matching the kit golden project. The board route of the 100 MHz HCSL clock is DC-coupled; that is the connector, not this Quartus setting. Transceiver VCCR/VCCT assignment is `1_0V`, also from the golden project. The kit ships with the x4 width resistor fitted (R507). R506 is the x1 option.

Reset is the AND of PERST#, FPGA_RESETn, and USER_PB0. All three are active-low. If S8 is held and the link never leaves reset, that button is being seen as pressed; release it.

## LEDs

| LED | Meaning |
|-----|---------|
| 0 | `link_up` |
| 1 | PHY reset-controller ready |
| 2 | heartbeat from the 50 MHz clock |
| 3 | LTSSM is L0 (`6'h10`) |

The silkscreen order of D19 and D21 looks swapped relative to a left-to-right count. The pins follow the user-guide net names (D19 = USER_LED0).

## Build

On a machine with Quartus Prime Pro that includes Cyclone 10 GX:

```text
fpga\c10gx\create_project.cmd
fpga\c10gx\synth.cmd
```

`create_project.cmd` looks for `quartus_sh` via `QUARTUS_ROOTDIR`, then PATH, then `C:\intelFPGA_pro\<version>\quartus\bin64`. The project file is `fpga/c10gx/build/rivet_c10gx.qpf`.

The first licensed run can stop inside `gen_xcvr.tcl` if a parameter name differs, or inside the glue step if two exported ports match one pattern. `build/ip/ports.txt` is the list to fix against. Do not check the generated IP in.

`FPGA_FAMILY=3` on `rivet_pcie` selects `rivet_pcie_phy_c10gx`, which is the behavioral stub used in simulation. The lab image does not go through that stub; it uses the generated Native PHY.
