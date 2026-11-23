# PG213 Endpoint model — Rivet Root Port

The link partner is the Vivado **PG213 Endpoint** example (`xilinx_pcie4_uscale_ep` + PIO). Rivet is the Root Port (`MODE=RC`) on the PG239 shell. This is the same split used the other way for the Endpoint: there the partner is the PG213 Root Port model.

```text
  EP = xilinx_pcie4_uscale_ep          RC = rivet_pg239_ep (MODE=RC)
        │  serial ×4                          │
        │◄───────────────────────────────────►│
        │                                rivet_pcie_ctrl + PG239
```

Local example (gitignored): `third_party/xilinx_ip/pcie4_uscale_plus_0_ex`.

```powershell
.\scripts\sim_bfm_pg213_rc.ps1
.\scripts\sim_bfm_pg213_rc.ps1 -Step compile
```

Work dir: `tb/bfm/pg213_rc/work/`.

| Token in `simulate.log` | Result |
|-------------------------|--------|
| `PASS: Rivet RC + PG213 EP link_up` | Both ports in L0 |
| `FAIL: Rivet RC + PG213 EP link training timeout` | No L0 within 500 us |

The first gate is link-up only. Config TLPs from the Root Port come after the Type 1 header and the requester.
