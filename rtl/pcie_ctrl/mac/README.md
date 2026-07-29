# MAC (`rtl/pcie_ctrl/mac`)

Gen2 EP Media Access Control sources.

| Planned module | Role |
|----------------|------|
| `rivet_ltssm` | LTSSM (PG213 `cfg_ltssm_state` encodings) |
| `rivet_mac_os_tx` | Ordered-set / TS encode, SKP insert, lane pack toward PIPE |
| `rivet_mac_os_rx` | Lane unpack, OS/TS detect, classify to DLL + LTSSM events |
| `rivet_mac_pipe_adapter` | `LANES` × `PIPE_DATA_WIDTH` ↔ `rivet_pipe_if` |

Follow [docs/mac.md](../../../docs/mac.md) and [docs/pipe-notes.md](../../../docs/pipe-notes.md).
