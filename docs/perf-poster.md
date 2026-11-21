# Rivet Gen2 x4 — measured results

Endpoint `rivet_pcie_ctrl` at PIPE, 4 lanes. QuestaSim 2024.1, 21 Nov 2026. `user_clk` in `rivet_tb_top` is 8.0 ns. Each row is printed `PERF` output. UVM reported 0 errors on each run.

| Test | Printed result |
|---|---|
| Posted write vs payload, 32 TLPs each | See the table below. Peer advertises infinite credits and ACKs each TLP. Largest point is 32 DW: **825.806 MB/s**, 41.290% of the 2000 MB/s Gen2 x4 symbol rate |
| Read latency, 8× RQ MemRd → RC CplD | min 363, avg 458, max 714 `user_clk` cycles. Includes the PIPE peer |
| Inbound, 8× CQ MemRd → CC CplD | 8 CQ packets and 8 CC completions, 32 payload bytes in 2876 `user_clk` cycles. **1.391 MB/s**. The window includes the wait for each peer MemRd |
| Credit stall, 12× RQ MemRd | 0 RQ stall cycles, 0 cycles with `pcie_tfc_nph_av = 0`. Lowest NPH credit scale observed: 4 |

Posted-write payload sweep, test `perf_rq_sweep_gen2_x4`, 32 MemWr32 TLPs per size, 0 UVM errors. Each size waits 8000 `pclk` cycles so the previous burst's replay is finished. `mb_s` is payload bytes on the 8 ns user bus (`bytes * 125 / cycles`). A full 64-bit beat every user clock is 1000 MB/s, so that bus is the ceiling.

| Payload (DW) | Payload bytes | user cycles | RQ stalls | MB/s | % of 2000 MB/s |
|---:|---:|---:|---:|---:|---:|
| 1 | 128 | 127 | 0 | 125.984 | 6.299 |
| 2 | 256 | 129 | 2 | 248.062 | 12.403 |
| 4 | 512 | 173 | 14 | 369.942 | 18.497 |
| 8 | 1024 | 231 | 8 | 554.113 | 27.706 |
| 16 | 2048 | 361 | 10 | 709.141 | 35.457 |
| 32 | 4096 | 620 | 13 | 825.806 | 41.290 |

32 DW is the largest MemWr32 that fits the 154-byte TLP limit (12-byte header + 128-byte payload). Reads are not in this table: the completer and requester-completion paths still pack 1 DW.

An earlier 16× 1DW run with a finite-credit peer and a one-cycle bubble between beats printed 83.333 MB/s. That number is not this curve.

VMK180 routed timing, from `fpga/vmk180/impl.log`, is a separate fact: WNS +0.143 ns, TNS 0, WHS +0.019 ns, THS 0. That is slack, not a data rate.

Gen2 x4 after 8b/10b is 2.000 GB/s of symbol data per direction. The MB/s figures above are payload bytes on the 8 ns user bus, not that line rate.
