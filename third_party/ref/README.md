# Local reference clones

Cloned under `third_party/ref/` for investigation only (**gitignored** — never commit sources; only this README is tracked).

| Repo | Path | Role for Rivet |
|------|------|----------------|
| [PCI_Express_Gen7.0](https://github.com/rkingsly2025/PCI_Express_Gen7.0) | `PCI_Express_Gen7.0/` | Educational layer diagram — [docs/ref-pci-express-gen7.md](../../docs/ref-pci-express-gen7.md) |
| [pcievhost](https://github.com/wyvernSemi/pcievhost) | `pcievhost/` | GPL-3 Gen1–2 VIP — [docs/ref-pcievhost.md](../../docs/ref-pcievhost.md) |
| [lowRISC/style-guides](https://github.com/lowRISC/style-guides) | `style-guides/` | SV + DV coding style (CC-BY-4.0) — [docs/ref-lowrisc-style.md](../../docs/ref-lowrisc-style.md), [docs/rtl-style.md](../../docs/rtl-style.md) |

```powershell
git clone --depth 1 git@github.com:rkingsly2025/PCI_Express_Gen7.0.git third_party/ref/PCI_Express_Gen7.0
git clone --depth 1 git@github.com:wyvernSemi/pcievhost.git third_party/ref/pcievhost
git clone --depth 1 git@github.com:lowRISC/style-guides.git third_party/ref/style-guides
```

If `git clone` fails (TLS/proxy), fetch the style-guide markdown files from  
`https://raw.githubusercontent.com/lowRISC/style-guides/master/` into `third_party/ref/style-guides/`.

Do not copy GPL-3 or license-unclear RTL into Rivet product sources.  
lowRISC guides are **style reference** (CC-BY-4.0) — Rivet’s condensed rules live in-repo with attribution; do not vendor the full guide as product IP.
