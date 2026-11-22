# Rivet Gen2 x4 — measured results

Endpoint `rivet_pcie_ctrl` at PIPE, 4 lanes. The posted-write sweep below is QuestaSim 2024.1, 22 Nov 2026, with `user_clk` at 4.0 ns. Read latency, inbound, and the credit-stall row are the 21 Nov 2026 runs and still print `user_clk_ns=8.0`. Each row is printed `PERF` output. UVM reported 0 errors on each run.

| Test | Printed result |
|---|---|
| Posted write vs payload, 8 TLPs each | See the table below. Peer advertises infinite credits and ACKs each TLP. Largest point is 1024 DW (4096 bytes): **1982.095 MB/s**, 99.105% of the 2000 MB/s Gen2 x4 symbol rate |
| Read latency, 8× RQ MemRd → RC CplD | min 363, avg 458, max 714 `user_clk` cycles on the 8.0 ns bench. Includes the PIPE peer. Not re-run at 4 ns |
| Inbound, 8× CQ MemRd → CC CplD | 8 CQ packets and 8 CC completions, 32 payload bytes in 2876 `user_clk` cycles. **1.391 MB/s** at `user_clk_ns=8.0`. The window includes the wait for each peer MemRd |
| Credit stall, 12× RQ MemRd | 0 RQ stall cycles, 0 cycles with `pcie_tfc_nph_av = 0`. Lowest NPH credit scale observed: 4. Measured at `user_clk_ns=8.0` |

Posted-write payload sweep, test `perf_rq_sweep_gen2_x4`, 8 MemWr32 TLPs per size, 0 UVM errors. Sizes are the PCIe Max Payload Size steps through 4096 bytes, plus the smaller points. Each size waits 8000 `pclk` cycles so the previous burst's replay is finished. `mb_s` is payload bytes on the 4 ns user bus (`bytes * 250 / cycles`). A full 64-bit beat every user clock is 2000 MB/s, the same as the Gen2 x4 symbol rate. LCRC rides the beat that leaves, and the MAC starts STP after a 16-byte head while later beats of the same TLP are still arriving.

| Payload | Bytes / TLP | Bytes, 8 TLPs | user cycles | RQ stalls | MB/s | % of 2000 MB/s |
|---:|---:|---:|---:|---:|---:|---:|
| 1 DW | 4 | 32 | 32 | 0 | 250.000 | 12.500 |
| 2 DW | 8 | 64 | 32 | 0 | 500.000 | 25.000 |
| 4 DW | 16 | 128 | 40 | 0 | 800.000 | 40.000 |
| 8 DW | 32 | 256 | 57 | 1 | 1122.807 | 56.140 |
| 16 DW | 64 | 512 | 95 | 7 | 1347.368 | 67.368 |
| 32 DW | 128 | 1024 | 161 | 9 | 1590.062 | 79.503 |
| 64 DW | 256 | 2048 | 293 | 13 | 1747.440 | 87.372 |
| 128 DW | 512 | 4096 | 549 | 13 | 1865.209 | 93.260 |
| 256 DW | 1024 | 8192 | 1061 | 13 | 1930.254 | 96.513 |
| 512 DW | 2048 | 16384 | 2085 | 13 | 1964.508 | 98.225 |
| 1024 DW | 4096 | 32768 | 4133 | 13 | 1982.095 | 99.105 |

1024 DW is 4096 bytes on each TLP. The wire length field is 0 for that size. The "Bytes, 8 TLPs" column is the `bytes=` field from the PERF line, which sums all 8 packets. From 64 DW up the window shows 13 RQ stall cycles, `credit_stall=0`, and `tfc_nph_min=15`. Reads are not in this table: the completer and requester-completion paths still pack 1 DW.

An earlier 16× 1DW run with a finite-credit peer and a one-cycle bubble between beats printed 83.333 MB/s. That number is not this curve.

VMK180 routed timing, from `fpga/vmk180/impl.log`, is a separate fact: WNS +0.143 ns, TNS 0, WHS +0.019 ns, THS 0. That slack is from the netlist before the 4 KB transmit slot. It is not a data rate and it does not apply to this RTL.

Gen2 x4 after 8b/10b is 2.000 GB/s of symbol data per direction. The sweep MB/s figures are payload bytes on the 4 ns user bus. The 4096-byte point is 1982.095 MB/s. The latency, inbound, and credit-stall figures above that table stay on the 8 ns clock they were measured with.
