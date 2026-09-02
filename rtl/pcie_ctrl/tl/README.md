# TL (`rtl/pcie_ctrl/tl`)

Transaction Layer and configuration-space sources.

| Planned area | Role |
|--------------|------|
| `rivet_tl_fc_stub` | CA / free / consume inject toward DLL (**D3**) |
| TL↔DLL TLP stream | 64b pack/unpack inside DLL (**D5**); user AXI-ST still stubbed |
| TLP assemble / decode | Toward user CQ/CC/RQ/RC (after D5 stream) |
| Config space | Type 0 (EP) + caps; `cfg_mgmt_*` (PG213-style) |
| Completions / tags | Requester/completer tracking (grow with Phase 2) |

User boundary is PG213-style AXI-ST + `cfg_mgmt`, not AXI-Lite. See [docs/pg213-interface.md](../../../docs/pg213-interface.md).
