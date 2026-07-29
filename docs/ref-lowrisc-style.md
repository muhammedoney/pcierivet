# Reference: lowRISC style-guides

**Upstream:** https://github.com/lowRISC/style-guides  
**Local clone (gitignored):** `third_party/ref/style-guides`  
**License:** Creative Commons Attribution 4.0 (CC-BY-4.0)  
**Investigated:** 2026-07-29  

## Verdict

Authoritative open **SystemVerilog + DV coding style** used by lowRISC / OpenTitan. Rivet adopts a **condensed, Rivet-specific** subset in [rtl-style.md](rtl-style.md) with attribution — not a verbatim dump of their guide into product docs beyond what CC-BY allows with credit.

## Contents

| File | Use |
|------|-----|
| `VerilogCodingStyle.md` | Synthesizable + TB SV conventions |
| `DVCodingStyle.md` | UVM / DV conventions (Phase 1 TB polish) |
| `LICENSE` | CC-BY-4.0 |

## What Rivet takes

- `logic`, `always_ff` / `always_comb`, NBA vs BA rules  
- Active-low async reset style  
- `snake_case`, enum `*_e`, active-low `*_n`  
- Explicit widths, named port connects, no `#delay` in synth  
- Prefer no latches; FSM = registered state + comb next  

## What Rivet keeps different

| Topic | Rivet |
|-------|--------|
| Top / PIPE ports | Flat PG239-aligned names (`pipe_txdata`, `pclk`, `preset_n`) — not renamed to `*_i`/`*_o` |
| Internal MAC/DLL/TL | Prefer lowRISC `*_i` / `*_o` / `*_ni` on **new** submodule ports |
| Package names | `rivet_pkg`, `rivet_uvm_pkg` |
| Controller purity | No vendor cells under `rtl/pcie_ctrl/` |

## Confidence

**High** as coding-style reference for open SV IP. Not a PCIe protocol reference.
