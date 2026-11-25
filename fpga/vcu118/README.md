# VCU118 Gen2 Endpoint project

Local Vivado project for a first lab check: does the Gen2 Endpoint reach **L0**, and can the host complete Type 0 config (and BAR0 Mem32 PIO).

The soft controller is the same RTL as simulation. This project generates a **PG239** `pcie_phy_0` at Gen2 ×4, so the bitstream stays Gen2. Gen3 and Gen4 x4 are closed in simulation and are not this board image. That netlist is not in git.

## Create

From the repo root, on a machine with Vivado and the XCVU9P / VCU118 device:

From `cmd.exe` (finds `vivado.bat` via `%VIVADO_PATH%`, `%XILINX_VIVADO%`, `PATH`, `C:\Xilinx\Vivado`, or `Program Files\Xilinx\Vivado`):

```text
fpga\vcu118\create_project.cmd
fpga\vcu118\synth.cmd
fpga\vcu118\impl.cmd
```

`create_project.cmd` only creates the project. `synth.cmd` opens `fpga/vcu118/build/rivet_vcu118.xpr` and runs `synth_1`. `impl.cmd` runs synthesis, implementation, and bitstream, and prints each Vivado step in the console. One-shot create-and-synth is still `create_project.cmd synth`.

Or call Vivado directly:

```text
vivado -mode batch -source fpga/vcu118/create_project.tcl
vivado -mode batch -source fpga/vcu118/synth.tcl
vivado -mode batch -source fpga/vcu118/impl.tcl
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

`` `include "common_cells/registers.svh" `` keeps the `common_cells/` prefix. The Vivado include directory is the parent of that folder (`fpga/vcu118/include` and `build/src`), not the directory that contains `registers.svh`. `create_project.tcl` copies the Vivado header (no default macro arguments) to `build/src/common_cells/registers.svh`. `FF` / `FFL` call sites are unchanged. `data_t'('0)` is rewritten to `'0` (HDL 9-1206). The upstream `common_cells/include` tree stays off the Vivado include path. Simulation still uses the upstream files.

## LEDs (DS37 down toward DS30)

| LED | Meaning |
|-----|---------|
| 0 | `link_up` |
| 1 | PHY out of reset (`phy_phystatus_rst` low) |
| 2 | Heartbeat from `pipe_clk` |
| 7:3 | `cfg_ltssm_state[4:0]`. **L0 is `6'h10`**, so LED 4 is the L0 bit |

`pcie_perst_n` is slot PERST# (AM17, active-low). `cpu_reset` is SW9 (L19, active-high).

## Transfer to a licensed machine

`pack_transfer` only zips sources. It does not call Vivado.

```text
fpga\vcu118\pack_transfer.cmd
fpga\vcu118\pack_transfer.cmd -OutDir D:\bags
fpga/vcu118/pack_transfer.sh
fpga/vcu118/pack_transfer.sh --out-dir ~/bags
```

Default zip, next to the repo: `rivet_transfer_vcu118_<timestamp>.zip`. The zip root folder is `rivet\`. Sim builds, `fpga/vcu118/build/`, `specs/`, local path files, and `.git` stay out. `-IncludeGit` / `--include-git` keeps history.

On the machine with an XCVU9P Vivado license, unzip, then:

```text
fpga\vcu118\create_project.cmd
fpga\vcu118\synth.cmd
```

## After it opens

1. Run `synth.cmd`, then implementation, then bitstream.
2. Program the VCU118 with the card in a host slot.
3. LED 1 should light after PHY reset. LED 0 and LTSSM `0x10` mean L0.
4. On the host, `lspci` is the config-TLP check. A BAR0 read/write is the PIO check.

An ILA on `link_up` and `cfg_ltssm_state` (both in `rivet_vcu118_ep`) is the next debug step if the LEDs never show L0.
