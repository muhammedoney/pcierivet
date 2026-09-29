# Local reference trees

Investigation clones (gitignored under `third_party/ref/*`) stay local-only.

## Tracked git submodules

| Path | Upstream | License | Product RTL? |
|------|----------|---------|--------------|
| `common_cells/` | [pulp-platform/common_cells](https://github.com/pulp-platform/common_cells) | Solderpad SHL-0.51 | **Yes** — CDC (`cc_cdc_2phase`, `cc_rstgen`, …) |
| `tech_cells_generic/` | [pulp-platform/tech_cells_generic](https://github.com/pulp-platform/tech_cells_generic) | Solderpad | **Yes** — `tc_sync` |
| `verilog-axis/` | [alexforencich/verilog-axis](https://github.com/alexforencich/verilog-axis) | MIT | **Yes** — `axis_async_fifo` (CQ/CC) |
| `verilog-axi/` | [alexforencich/verilog-axi](https://github.com/alexforencich/verilog-axi) | MIT | Future AXI/AXI-lite helpers (`axil_cdc`); not in current filelist |
| `taxi/` | [fpganinja/taxi](https://github.com/fpganinja/taxi) | CERN-OHL-S-2.0 | **No** — reference only (incompatible with Apache-2.0 product without commercial license) |
| `litepcie/` | [enjoy-digital/litepcie](https://github.com/enjoy-digital/litepcie) | LiteX / Python | **No** — architecture reference only |

Clone / update:

```powershell
git submodule update --init --recursive
```

Rivet wrappers live in `rtl/pcie_ctrl/cdc/` and pull only the product rows above via `rtl/filelist_cdc.f`.
