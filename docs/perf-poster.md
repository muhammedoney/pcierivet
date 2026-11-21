# Rivet Gen2 x4 — measured results

Endpoint, `rivet_pcie_ctrl` at PIPE, 4 lanes. Throughput rows stay blank until a Questa run prints a `PERF` line. Timing is from the VMK180 route, not from the simulator.

| What | Result |
|---|---|
| Posted-write payload | not measured — `vsim` license checkout failed (21 Nov 2026) |
| RQ `tready` stall cycles | not measured |
| RQ MemRd → RC CplD latency | not measured |
| Inbound CC CplD payload | not measured |
| Cycles stalled with `pcie_tfc_nph_av = 0` | not measured |
| VMK180 routed setup | WNS +0.143 ns, TNS 0 |
| VMK180 routed hold | WHS +0.019 ns, THS 0 |

Source for the timing row: `fpga/vmk180/impl.log` post-route summary `WNS=0.143` and the property print `WNS=0.142599 ns  TNS=0.000000 ns  WHS=0.018743 ns`.

Gen2 x4 symbol data rate is 2.000 GB/s per direction. That figure is the line rate, not a measured payload rate.
