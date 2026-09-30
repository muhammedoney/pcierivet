# TL (`rtl/pcie_ctrl/tl`)

Transaction Layer: config space, fabric Cfg completer, AXI-ST CQ/CC (Mem32/Mem64).

| Module | Role |
|--------|------|
| `rivet_tl_cfg_space` | PF0 4 KiB Type 0 + PM/MSI/PCIe caps; write masks / BAR sizing; shared by fabric Cfg and `cfg_mgmt_*` |
| `rivet_tl_cfg` | Fabric CfgRd0/CfgWr0 → Cpl/CplD (no PIO RAM) |
| `rivet_tl_rx_route` | Demux DLL RX: Cfg vs Mem32/64 / IO / Msg vs Cpl |
| `rivet_tl_cq` | BAR0 Mem32/Mem64 (+ IO/Msg) → PG213 64-bit CQ |
| `rivet_tl_cc` | PG213 64-bit CC → wire Cpl/CplD |
| `rivet_tl_tx_mux` | Cfg TX priority over CC TX toward DLL |
| `rivet_tl_pio_app` | Tiny BAR0 Mem32 RAM on CQ/CC (BFM / smoke) |
| `rivet_tl_credit` | Classify TLP Fmt/Type → free (RX) / consume (TX) |
| `rivet_tl_fc_stub` | Finite RX buffer CA (PH/PD/NPH/NPD) + UpdateFC free / TX consume toward DLL |

RQ/RC remain stubbed at the controller. User boundary is PG213-style AXI-ST + live `cfg_mgmt`, not AXI-Lite. See [docs/pg213-interface.md](../../../docs/pg213-interface.md).

Packed CQ/CC descriptor and `tuser` helpers live in `rivet_pkg`.
