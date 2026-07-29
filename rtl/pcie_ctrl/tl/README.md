# TL (`rtl/pcie_ctrl/tl`)

Transaction Layer and configuration-space sources.

| Planned area | Role |
|--------------|------|
| TLP assemble / decode | Toward DLL; user-facing AXI-ST CQ/CC/RQ/RC |
| Config space | Type 0 (EP) + caps; `cfg_mgmt_*` (PG213-style) |
| Completions / tags | Requester/completer tracking (grow with Phase 2) |

User boundary is PG213-style AXI-ST + `cfg_mgmt`, not AXI-Lite. See [docs/pg213-interface.md](../../../docs/pg213-interface.md).
