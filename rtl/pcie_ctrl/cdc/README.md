# CDC (`rtl/pcie_ctrl/cdc`)

User-boundary clock crossing: `user_clk` ↔ `pclk`.

| Wrapper | Upstream cell |
|---------|----------------|
| `rivet_cdc_axis` | `axis_async_fifo` (verilog-axis) |
| `rivet_cdc_cfg_mgmt` | `cc_cdc_2phase` ×2 (common_cells) |
| `rivet_cdc_sync_bus` | `tc_sync` (tech_cells_generic) |
| (in controller) | `cc_rstgen` for POR sync deassert |

See [third_party/ref/README.md](../../../third_party/ref/README.md) for licenses and submodule policy.
