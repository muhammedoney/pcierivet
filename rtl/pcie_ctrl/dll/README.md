# DLL (`rtl/pcie_ctrl/dll`)

Data Link Layer sources. Checklist / plan: [docs/dll.md](../../../docs/dll.md).

| Module | Role |
|--------|------|
| `rivet_dll` | Top; FC + DL SM + TL stream + TLP/ACK/NAK/replay (D5) |
| `rivet_dll_sm` | Inactive / Init / Active (+ replay busy); `dl_up` |
| `rivet_dll_crc16` | DLLP 16-bit CRC |
| `rivet_dll_lcrc32` | TLP LCRC-32 |
| `rivet_dllp_tx` / `rivet_dllp_rx` | DLLP build / parse + CRC |
| `rivet_dll_fc` | InitFC/UpdateFC + CL/CC/av gate |
| `rivet_dll_tl_pack` / `rivet_dll_tl_unpack` | TL stream ↔ whole payload |
| `rivet_dll_tlp_tx` / `rivet_dll_tlp_rx` | Seq# + LCRC frame / check + ACK/NAK |
| `rivet_dll_replay` | Retry buffer (parametric slots) |

DLL ↔ MAC: `rivet_dll_mac_if.sv` + beats/sideband in `rivet_pkg`.  
DLL ↔ TL TLP: 64-bit AXI-ST-like stream (`RIVET_TL_DLL_DATA_W`); not user CQ/CC/RQ/RC.
