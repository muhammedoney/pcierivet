# DLL (`rtl/pcie_ctrl/dll`)

Data Link Layer sources. Checklist / plan: [docs/dll.md](../../../docs/dll.md).

| Planned module | Role |
|----------------|------|
| `rivet_dll` | Top; wires FC + DLLP (+ later TLP/replay) |
| `rivet_dll_crc16` | DLLP 16-bit CRC (**present**) |
| `rivet_dll_lcrc32` | TLP 32-bit LCRC (after FC) |
| `rivet_dllp_tx` / `rivet_dllp_rx` | DLLP build / parse |
| `rivet_dll_fc` | InitFC1/2, UpdateFC, CA/CL/CC |
| `rivet_dll_tlp_*` / replay | Later — after FC + MAC framing |

DLL ↔ MAC: `rivet_dll_mac_if.sv` + beats/sideband in `rivet_pkg`.
Checklist: [docs/dll.md](../../../docs/dll.md).
