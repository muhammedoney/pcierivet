# DLL (`rtl/pcie_ctrl/dll`)

Data Link Layer sources.

| Planned area | Role |
|--------------|------|
| DLL TX / RX | DLLP and TLP framing toward MAC payload streams |
| ACK/NAK + replay | Retry buffer, sequence numbers |
| LCRC | Generate / check |
| Flow control | InitFC / UpdateFC, credit counters |

DLL ↔ MAC uses payload streams **plus** control sideband (not config space). See [docs/mac.md](../../../docs/mac.md) §4.
