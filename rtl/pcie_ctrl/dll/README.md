# DLL (`rtl/pcie_ctrl/dll`)

Data Link Layer sources. Checklist / plan: [docs/dll.md](../../../docs/dll.md).

| Module | Role |
|--------|------|
| `rivet_dll` | Top; FC + DL SM (TLP/replay wire = D4b) |
| `rivet_dll_sm` | Inactive / Init / Active / Replay |
| `rivet_dll_crc16` | DLLP 16-bit CRC |
| `rivet_dll_lcrc32` | TLP LCRC-32 |
| `rivet_dllp_tx` / `rivet_dllp_rx` | DLLP build / parse + CRC |
| `rivet_dll_fc` | InitFC/UpdateFC + CL/CC/av gate |
| `rivet_dll_replay` | Retry buffer (parametric slots) |

DLL ↔ MAC: `rivet_dll_mac_if.sv` + beats/sideband in `rivet_pkg`.
