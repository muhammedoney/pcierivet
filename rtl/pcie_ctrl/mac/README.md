# MAC (`rtl/pcie_ctrl/mac`)

Gen2 EP Media Access Control sources. Style: [docs/rtl-style.md](../../../docs/rtl-style.md).

| Module | Role |
|--------|------|
| `rivet_mac` | Wrapper: LTSSM + OS TX/RX + PIPE adapter |
| `rivet_ltssm` | LTSSM (PG213 encodings); M0 holds Detect.Quiet |
| `rivet_mac_os_tx` | OS/TS encode + DLL mux (stub) |
| `rivet_mac_os_rx` | OS/TS detect + classify (stub) |
| `rivet_mac_pipe_adapter` | Symbol/command ↔ flat PIPE ports |

DLL↔MAC IF: `../dll/rivet_dll_mac_if.sv`. Follow [docs/mac.md](../../../docs/mac.md).
