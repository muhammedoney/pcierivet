# Rivet Gen2 x4 — measured results

Endpoint `rivet_pcie_ctrl` at PIPE, 4 lanes. QuestaSim 2024.1, 21 Nov 2026. `user_clk` in `rivet_tb_top` is 8.0 ns. Each row is one printed `PERF` line. UVM reported 0 errors on these four runs.

| Test | Printed result |
|---|---|
| Posted write, 16× 1DW | 64 payload bytes, 96 `user_clk` cycles, 48 RQ beats accepted, 0 cycles stalled on `tready`. **83.333 MB/s**, 4.167% of the 2000 MB/s Gen2 x4 symbol rate |
| Read latency, 8× RQ MemRd → RC CplD | min 363, avg 458, max 714 `user_clk` cycles. Includes the PIPE peer |
| Inbound, 8× CQ MemRd → CC CplD | 8 CQ packets and 8 CC completions, 32 payload bytes in 2876 `user_clk` cycles. **1.391 MB/s**. The window includes the wait for each peer MemRd |
| Credit stall, 12× RQ MemRd | 0 RQ stall cycles, 0 cycles with `pcie_tfc_nph_av = 0`. Lowest NPH credit scale observed: 4 |

VMK180 routed timing, from `fpga/vmk180/impl.log`, is a separate fact: WNS +0.143 ns, TNS 0, WHS +0.019 ns, THS 0. That is slack, not a data rate.

Gen2 x4 after 8b/10b is 2.000 GB/s of symbol data per direction. The MB/s figures above are payload bytes on the 8 ns user bus, not that line rate.
