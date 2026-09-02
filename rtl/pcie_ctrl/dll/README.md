# DLL (`rtl/pcie_ctrl/dll`)

Data Link Layer sources. Checklist / plan: [docs/dll.md](../../../docs/dll.md).

| Module | Role |
|--------|------|
| `rivet_dll` | Top; codec + InitFC / UpdateFC |
| `rivet_dll_crc16` | DLLP 16-bit CRC |
| `rivet_dllp_tx` / `rivet_dllp_rx` | DLLP build / parse + CRC |
| `rivet_dll_fc` | InitFC1/2 → UpdateFC; CL sticky-inf |
| `rivet_dll_lcrc32` / tlp / replay | Later |

DLL ↔ MAC: `rivet_dll_mac_if.sv` + beats/sideband in `rivet_pkg`.
