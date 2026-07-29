# DO-254-inspired practices for Rivet

**Status:** Process / quality practices only. Rivet does **not** claim DO-254 certification or avionics compliance.

[DO-254](https://en.wikipedia.org/wiki/DO-254) is a hardware design assurance standard (process), not an RTL coding style. Rivet borrows **lightweight** practices that improve open-IP quality without the full certification burden.

## Practices we adopt now

| Practice | Rivet mapping |
|----------|----------------|
| Requirements traceability (lite) | Feature work tied to [roadmap.md](roadmap.md) / [mac.md](mac.md) milestones (M0, M1, …); PR describes which milestone |
| Configuration management | Git + conventional commits; no secrets / `specs/` / proprietary IP in tree |
| Design reviews | PR review; keep slices small (change → lint → commit) |
| Independent verification intent | UVM is primary functional authority; Verilator lint gate; BFM is optional side-path |
| Tool use awareness | Document which tools ran (Verilator / Questa / Yosys) in PR or commit notes when relevant |
| Coding standards | Locked [rtl-style.md](rtl-style.md) (lowRISC-inspired) |
| Problem reporting | GitHub issues for defects; fix in follow-up commits (no silent force-push) |

## Practices deferred (later maturity)

| Practice | When |
|----------|------|
| Formal req IDs (REQ-MAC-001 …) linked in RTL comments | After MAC M1 proves useful |
| Coverage goals / DO-254 DAL mapping | If a partner requires assurance evidence |
| Tool qualification packages | Not planned for open soft IP |
| Full bidirectional req ↔ test matrix | Expand with Phase 2 functional |
| Independent SOI audits | N/A unless commercial assurance program |

## What this is not

- Not a substitute for PCIe Base / PIPE / PG239 correctness  
- Not permission to skip UVM or lint  
- Not a claim that Rivet is flight-certifiable  

## Related

- [rtl-style.md](rtl-style.md) — how we write RTL  
- [verification.md](verification.md) — how we prove it  
- [roadmap.md](roadmap.md) — what we build next  
