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
.\scripts\sim_bfm_pg213_rc.ps1 -Mode 3
.\scripts\sim_bfm_pg213_rc.ps1 -Step compile
```

`-Mode 1` (default) is the Root Port. `-Mode 3` is the Downstream Port against the same Endpoint model.

Work dir: `tb/bfm/pg213_rc/work/`.

| Token in `simulate.log` | Result |
|-------------------------|--------|
| `PASS: Rivet RC + PG213 EP link_up` | Both ports in L0 (`DSP` when `-Mode 3`) |
| `PASS: Rivet RC + PG213 EP hot reset` | After L0, Rivet holds Hot Reset until the Endpoint is in `6'h27`, then both return to L0 |
| `PASS: Rivet RC + PG213 EP link disable` | After that, Rivet holds Disabled until the Endpoint is in `6'h20`, stays there while the request is high, then both return to L0 |
| `PASS: Rivet RC + PG213 EP cfg rd0` | Root Port CfgRd0 of the Endpoint returns status 0 and vendor `16'h10EE` |
| `PASS: Rivet DSP + PG213 EP type1` | Downstream Port config header is class `24'h060400`, header type `8'h01` |
| `PASS: Rivet DSP + PG213 EP rq stall` | Downstream Port holds RQ `tready` low on a CfgWr1 descriptor beat |
| `FAIL: Rivet RC + PG213 EP link training timeout` | Sequence did not finish before the bench timeout |
