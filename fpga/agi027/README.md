# DK-DEV-AGI027-RA-B controller compile

Quartus project for a compile check of the Gen2 ×4 soft controller on the Agilex 7 FPGA I-Series Development Kit, Rev B.

| Item | Value |
|------|-------|
| Kit | DK-DEV-AGI027-RA-B |
| Device | AGIB027R29A1E1VB |
| Top | `rivet_agi027_ep` |
| What is compiled | `rivet_pcie_ctrl` (`MODE=EP`, `GEN=2`, `LANES=4`) plus `rivet_tl_pio_app` |

The kit PCIe edge is R-tile **14C** (Gen5 ×16, PIPE 5.1 SerDes). That PMA is not the controller's 16-bit Gen2 PIPE, so this project does not assign those pins and does not instantiate an R-tile PHY. `clk`, `reset_n`, and `led` are virtual pins. `clk` is constrained at 4.000 ns, the Gen2 16-bit PIPE period. RX PIPE is held in electrical idle.

This is not a bitstream for the slot. A licensed machine is expected to fail the fitter until a license that covers this device is present. The script does not edit `license.dat`.

## Create and compile

From `cmd.exe`, at the repo root:

```text
fpga\agi027\create_project.cmd
fpga\agi027\impl.cmd
```

`create_project.cmd` writes `fpga/agi027/build/rivet_agi027.qpf` (gitignored). `impl.cmd` runs synthesis, fit, timing, and assembly, and prints each step in the console. Quartus also writes its own logs under `fpga/agi027/build/`.
