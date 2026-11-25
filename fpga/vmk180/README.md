# VMK180 Gen2 Endpoint project

Local Vivado project for a first lab check on the Versal primary board: does the Gen2 Endpoint reach **L0**, and can the host complete Type 0 config (and BAR0 Mem32 PIO).

No arguments still generate PG345 at Gen2 x4 into `fpga/vmk180/build/`. `create_project.cmd 4 ep` generates PG345 at `link_speed 4` into `fpga/vmk180/build/gen4_ep/` and the bitstream is `rivet_vmk180_gen4_ep.bit`. Gen3, RC, DSP, and USP images are a later plan. The vendor netlist is not in git.

Primary Versal part: **XCVM1802** on the **VMK180** (EK-VMK180-G). VPK180 (Premium, GTYP) is the later Gen5 path, not this project.

## Create

From the repo root, on a machine with Vivado and the XCVM1802 / VMK180 device:

From `cmd.exe` (finds `vivado.bat` via `%VIVADO_PATH%`, `%XILINX_VIVADO%`, `PATH`, `C:\Xilinx\Vivado`, or `Program Files\Xilinx\Vivado`):

```text
fpga\vmk180\create_project.cmd
fpga\vmk180\synth.cmd
fpga\vmk180\impl.cmd
```

`create_project.cmd` only creates the project. `synth.cmd` opens `fpga/vmk180/build/rivet_vmk180.xpr` and runs `synth_1`. `impl.cmd` runs synthesis, implementation, and bitstream, and prints each Vivado step in the console. The same three commands take `4 ep` for the Gen4 project. `synth.cmd` is the synth entry.

Or call Vivado directly:

```text
vivado -mode batch -source fpga/vmk180/create_project.tcl
vivado -mode batch -source fpga/vmk180/synth.tcl
vivado -mode batch -source fpga/vmk180/impl.tcl
vivado -mode batch -source fpga/vmk180/create_project.tcl -tclargs synth
```

Project file: `fpga/vmk180/build/rivet_vmk180.xpr` (gitignored).

Part: `xcvm1802-vsva2197-2MP-e-S` (kit marking XCVM1802-2MSEVSVA2197). The script tries VMK180 board parts `3.4` down to `1.2`. If none are installed it keeps the part and prints a warning.

## What the shell does

| Piece | Role |
|-------|------|
| `rivet_pcie_phy_wrap` | `BOARD=VMK180`. Pads 16-bit PIPE to the PG345 pins and replicates per-lane controls |
| GT quad | Block automation. LOC `GTY_QUAD_X0Y3` (quad 103, slot lanes 0–3). Refclk site `GTY_REFCLK_X0Y6` (package W39/W40) |
| `rivet_pcie_ctrl` | `MODE=EP`, `GEN=2`, `SPEED_CHANGE_EN=1`, hardware LTSSM timers |
| `rivet_tl_pio_app` | BAR0 Mem32 completions. Config space is answered inside the controller |
| RQ/RC | Tied idle. Host-memory TLP traffic is a later step |

PG345 x4 pin widths checked against `pcie_phy_versal` in Vivado 2024.2. The wrapper, not the shell, applies them:

- `phy_rate` is 3 bits, shared by the link.
- `phy_txdetectrx_loopback`, `phy_txswing`, `phy_txdeemph`, and `phy_rx_termination` are 4 bits (one per lane). The controller value is copied onto every lane. Termination is 1 only while `as_mac_in_detect` is 1.
- `phy_powerdown` is 8 bits and `phy_txmargin` is 12 bits. Each lane gets the controller's link-wide value.
- `phy_ready` holds the MAC in reset until the PHY clock is up. `phy_phystatus_rst` is a 1-bit PG345 output and is copied onto every controller lane. There is no `gt_gtpowergood` on this PHY.
- `pcie_ltssm_state` is driven from the controller. `pcie_link_reach_target` follows `link_up`.

If Vivado rejects a PG345 property or a port width, the script prints the legal values or the real pin list and stops. The widths in `create_project.tcl` are the contract with `rivet_pcie_phy_wrap`.

`` `include "common_cells/registers.svh" `` keeps the `common_cells/` prefix. The Vivado include directory is the parent of that folder (`fpga/vmk180/include` and `build/src`). `create_project.tcl` copies the Vivado header (no default macro arguments) to `build/src/common_cells/registers.svh`. Simulation still uses the upstream files.

## LEDs (DS6 down toward DS3)

The VMK180 has four PL GPIO LEDs, bank 306, 1.8 V.

| LED | Ref | Meaning |
|-----|-----|---------|
| 0 | DS6 | `link_up` |
| 1 | DS5 | `phy_ready` |
| 2 | DS4 | Heartbeat from `phy_pclk` |
| 3 | DS3 | LTSSM is L0 (`6'h10`) |

`cpu_reset` is SW4 (G37, GPIO_PB0, active-high). Pressing it holds the PHY and the controller in reset.

Slot PERST# is `PCIE_PERST_B` on PMC MIO38. This PL shell does not see it. A later CIPS hook can forward PERST into the fabric. Until then, release SW4 after the card is powered in the host slot.

## Transfer to a licensed machine

`pack_transfer` only zips sources. It does not call Vivado.

```text
fpga\vmk180\pack_transfer.cmd
fpga\vmk180\pack_transfer.cmd -OutDir D:\bags
fpga/vmk180/pack_transfer.sh
fpga/vmk180/pack_transfer.sh --out-dir ~/bags
```

Default zip, next to the repo: `rivet_transfer_vmk180_<timestamp>.zip`. The zip root folder is `rivet\`. Sim builds, `fpga/*/build/`, `specs/`, local path files, and `.git` stay out. `-IncludeGit` / `--include-git` keeps history.

On the machine with an XCVM1802 Vivado license, unzip, then:

```text
fpga\vmk180\create_project.cmd
fpga\vmk180\synth.cmd
```

## After it opens

1. Run `synth.cmd`, then implementation, then bitstream.
2. Program the VMK180 with the card in a host slot. Release SW4.
3. LED 1 should light after PHY ready. LED 0 and LED 3 mean L0.
4. On the host, `lspci` is the config-TLP check. A BAR0 read/write is the PIO check.

An ILA on `link_up` and `cfg_ltssm_state` (both in `rivet_vmk180_ep`) is the next debug step if the LEDs never show L0.
