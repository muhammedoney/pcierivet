# Contributing to Rivet

## Principles

- **English only** for code, comments, commits, issues, and docs.
- **Verification before features** — do not land RTL that breaks the smoke path.
- **Controller purity** — no Xilinx primitives inside `rtl/pcie_ctrl/`; vendor PHY only under `rtl/phy/` / `rivet_pcie`.
- **Specs stay outside the repo** — cite documents; never commit proprietary PDFs or encrypted IP.

## Development loop

1. Change RTL or TB
2. Run Verilator lint / smoke (`scripts/lint.*`, `scripts/sim_verilator.*`)
3. Run Questa UVM smoke when available (`scripts/sim_questa.*`)
4. Optional Yosys synth check
5. Only then add the next feature slice

## Commit style

Conventional commits:

```text
feat|fix|test|docs|build|chore|refactor(scope): short summary
```

Examples:

```text
feat(ep): add Gen2 LTSSM Detect state stub
test(uvm): Gen2 x1 smoke compiles under Questa
docs(readme): clarify dual delivery forms
```

## Coding standards

See `.cursor/rules/` and keep:

- SystemVerilog `lower_snake` for modules/signals
- Packages: `rivet_pkg`, `rivet_uvm_pkg`
- Parameters: `GEN`, `LANES` (1/2/4), `MODE` (`EP` first)
- AXI-ST channels CQ/CC/RQ/RC always present on `rivet_pcie_ctrl`
- AXI-Lite for configuration (stub ports in Phase 0)
- Module names: controller / phy / `rivet_pcie` — not `*_ep` for the soft core

## Pull requests

- Keep PRs focused
- Include how you ran lint / smoke
- Do not commit Vivado project caches, PHY netlists, or BFM binaries
