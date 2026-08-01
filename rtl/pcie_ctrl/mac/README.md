# MAC (`rtl/pcie_ctrl/mac`)

Gen2 EP Media Access Control sources. Style: [docs/rtl-style.md](../../../docs/rtl-style.md).
Follow [docs/mac.md](../../../docs/mac.md).

| Module | Role |
|--------|------|
| `rivet_mac` | Wrapper: LTSSM + OS TX/RX + scramble + PIPE adapter |
| `rivet_ltssm` | LTSSM (PG213 encodings); Detect→…→L0 (M1) |
| `rivet_mac_os_tx` | OS/TS encode; DLL mux still tied off |
| `rivet_mac_os_rx` | OS/TS detect; Idle = descrambled `00h` |
| `rivet_mac_scrambler` | Gen2 TX LFSR (M2) |
| `rivet_mac_descrambler` | Gen2 RX LFSR (M2) |
| `rivet_mac_pipe_adapter` | Symbol/command ↔ flat PIPE ports |
| `rivet_mac_timer` | Shared LTSSM timeout counter |

DLL↔MAC IF: `../dll/rivet_dll_mac_if.sv`.
