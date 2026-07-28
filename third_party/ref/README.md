# Local reference clones

Cloned under `third_party/ref/` for investigation only (**gitignored** — never commit).

| Repo | Path | Role for Rivet |
|------|------|----------------|
| [PCI_Express_Gen7.0](https://github.com/rkingsly2025/PCI_Express_Gen7.0) | `PCI_Express_Gen7.0/` | Educational layer diagram — see [docs/ref-pci-express-gen7.md](../docs/ref-pci-express-gen7.md) |
| [pcievhost](https://github.com/wyvernSemi/pcievhost) | `pcievhost/` | GPL-3 Gen1–2 VIP reference — see [docs/ref-pcievhost.md](../docs/ref-pcievhost.md) |

```powershell
git clone --depth 1 git@github.com:rkingsly2025/PCI_Express_Gen7.0.git third_party/ref/PCI_Express_Gen7.0
git clone --depth 1 git@github.com:wyvernSemi/pcievhost.git third_party/ref/pcievhost
```

Do not copy GPL-3 or license-unclear RTL into Rivet product sources.
