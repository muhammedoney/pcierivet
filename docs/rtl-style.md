# Rivet RTL style (lowRISC-inspired)

**Normative for new RTL** under `rtl/`.  
**Derived from:** [lowRISC/style-guides](https://github.com/lowRISC/style-guides) `VerilogCodingStyle.md` (CC-BY-4.0).  
**Full local copy:** `third_party/ref/style-guides/` (gitignored). See [ref-lowrisc-style.md](ref-lowrisc-style.md).

This document is Rivet’s condensed ruleset, not a replacement for reading the upstream guide when unsure. Process / assurance practices: [do254-practices.md](do254-practices.md).

## Attribution

Portions of this style are adapted from the lowRISC Verilog Coding Style Guide, licensed under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/). Rivet remains Apache-2.0 for code.

## File and appearance

| Rule | Rivet |
|------|--------|
| Extension | `.sv` for SV |
| Indent | 2 spaces; **no tabs** |
| Line length | Prefer ≤ 100 characters |
| Comments | `//` preferred |
| Header | Copyright year + `SPDX-License-Identifier: Apache-2.0` |
| Language | English only |

## Naming

| Kind | Convention | Example |
|------|------------|---------|
| Module / signal | `lower_snake_case` | `rivet_ltssm` |
| Package | `*_pkg` | `rivet_pkg` |
| Enum type | `*_e` | `rivet_ltssm_state_e` |
| Other typedef | `*_t` | `rivet_dll_mac_tx_t` |
| Active-low | `*_n` / `*_ni` | `preset_n`, `rst_ni` |
| Parameters | `UpperSnake` or existing `MODE`/`GEN`/`LANES` | `PIPE_DATA_WIDTH` |
| Constants | `ALL_CAPS` in packages | `RIVET_LTSSM_L0` |

### Port suffixes (new submodules)

Prefer lowRISC-style on **internal** modules (`mac/`, `dll/`, `tl/`):

| Suffix | Meaning |
|--------|---------|
| `_i` | Input |
| `_o` | Output |
| `_ni` | Active-low input (e.g. `rst_ni`) |
| `_clk_i` | Clock input (or keep `pclk_i`) |

**Exception — controller / PHY / PIPE tops:** keep existing flat / PG239-aligned names (`pclk`, `preset_n`, `pipe_txdata`, AXI-ST `m_axis_*`). Do not rename the public IF for style alone.

## Language constructs

- Use `logic` for synthesizable signals (not `reg`/`wire` for new code).  
- Sequential: `always_ff @(posedge clk_i or negedge rst_ni)` with **non-blocking** `<=`.  
- Combinational: `always_comb` with **blocking** `=`. Never mix BA/NBA in one block.  
- No `#delay` in synthesizable modules.  
- Avoid latches; if unavoidable, `always_latch` + `<=`.  
- Explicit widths on literals (`6'h10`, not `'h10` where width matters).  
- Named port connections only (no positional).  
- No `defparam`; no recursive instantiation.  
- Endlabels: `endmodule : rivet_ltssm`.  
- Sim-only `$error` / asserts: `` `ifndef SYNTHESIS ``.

## FSM pattern

```systemverilog
rivet_ltssm_state_e state_q, state_d;

always_comb begin
  state_d = state_q;
  // next-state logic
end

always_ff @(posedge pclk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    state_q <= rivet_pkg::RIVET_LTSSM_DETECT_QUIET;
  end else begin
    state_q <= state_d;
  end
end
```

## Parameters and purity

- `MODE`, `GEN`, `LANES` (1/2/4), widths explicit.  
- No Xilinx primitives in `rtl/pcie_ctrl/`.  
- Gen2-first: do not implement Gen3/4 protocol in active slices ([gen-evolution.md](gen-evolution.md)).

## Clocks / CDC

- MAC on `pclk` only.  
- CDC only at `user_clk` ↔ `pclk` (TL/AXI), not inside `mac/`.

## Related

- Cursor rule: `.cursor/rules/sv-rtl-style.mdc`  
- UVM: `.cursor/rules/uvm-style.mdc` + lowRISC `DVCodingStyle.md` locally  
- MAC plan: [mac.md](mac.md)
