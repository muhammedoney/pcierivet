# Soft controller RTL layout

```text
rtl/pcie_ctrl/
  rivet_pkg.sv           Shared types/params (all layers)
  rivet_pcie_ctrl.sv     Controller top — integrates TL + DLL + MAC → PIPE
  mac/                   Media Access Control (LTSSM, OS TX/RX, PIPE adapter)
  dll/                   Data Link Layer (DLLP, ACK/NAK, LCRC, FC)
  tl/                    Transaction Layer + config space (AXI-ST toward user)
```

No vendor cells in this tree. See [docs/mac.md](../../docs/mac.md), [docs/architecture.md](../../docs/architecture.md).
