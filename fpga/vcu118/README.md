# VCU118 Gen2 Endpoint project

Local Vivado project for a first lab check: does the Gen2 Endpoint reach **L0**, and can the host complete Type 0 config (and BAR0 Mem32 PIO).

The soft controller is the same RTL as simulation. The PHY is a generated **PG239** `pcie_phy_0` (GTY, Gen2, ×4). That netlist is not in git.

## Create

From the repo root, on a machine with Vivado and the XCVU9P / VCU118 device:

From `cmd.exe` (finds `vivado.bat` on `PATH`, under `%VIVADO_PATH%`, or under `Program Files\Xilinx\Vivado`):

```text
fpga\vcu118\create_project.cmd
fpga\vcu118\create_project.cmd synth
```

Or call Vivado directly:

```text
vivado -mode batch -source fpga/vcu118/create_project.tcl
vivado -mode batch -source fpga/vcu118/create_project.tcl -tclargs synth
```

Project file: `fpga/vcu118/build/rivet_vcu118.xpr` (gitignored).

Part: `xcvu9p-flga2104-2L-e`. If the installed board-part version is not `xilinx.com:vcu118:part0:2.4`, the script keeps the part and prints a warning.

## What the shell does

| Piece | Role |
|-------|------|
| `pcie_phy_0` | PG239, max speed 5.0 GT/s, ×4, 100 MHz refclk, lane 0 at `GTYE4_CHANNEL_X1Y35` (slot lane 0, quad 227) |
| `rivet_pcie_ctrl` | `MODE=EP`, `GEN=2`, `SPEED_CHANGE_EN=1`, hardware LTSSM timers |
| `rivet_tl_pio_app` | BAR0 Mem32 completions. Config space is answered inside the controller |
| RQ/RC | Tied idle. Host-memory TLP traffic is a later step |

If Vivado rejects a PG239 enum (`lane0_gt_bank`, `refclk1_location`), the script prints the legal values. Set lane 0 to slot lane 0 and refclk to `MGTREFCLK0` of that quad, then regenerate.

## LEDs (DS37 down toward DS30)

| LED | Meaning |
|-----|---------|
| 0 | `link_up` |
| 1 | PHY out of reset (`phy_phystatus_rst` low) |
| 2 | Heartbeat from `pipe_clk` |
| 7:3 | `cfg_ltssm_state[4:0]`. **L0 is `6'h10`**, so LED 4 is the L0 bit |

`pcie_perst_n` is slot PERST# (AM17, active-low). `cpu_reset` is SW9 (L19, active-high).

## After it opens

1. Run synthesis, then implementation, then bitstream.
2. Program the VCU118 with the card in a host slot.
3. LED 1 should light after PHY reset. LED 0 and LTSSM `0x10` mean L0.
4. On the host, `lspci` is the config-TLP check. A BAR0 read/write is the PIO check.

An ILA on `link_up` and `cfg_ltssm_state` (both in `rivet_vcu118_ep`) is the next debug step if the LEDs never show L0.
