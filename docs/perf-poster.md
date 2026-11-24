# Rivet Gen2 x4 — measured results

Endpoint `rivet_pcie_ctrl` at PIPE, 4 lanes. The posted-write sweep is QuestaSim 2024.1, 22 Nov 2026. The requester-read sweep is QuestaSim 2024.1, 23 Nov 2026. Both use `user_clk` at 4.0 ns. The read-latency, inbound, and credit-stall rows in the first table are the 21 Nov 2026 runs and still print `user_clk_ns=8.0`. Each row is printed `PERF` output. UVM reported 0 errors on each run.

| Test | Printed result |
|---|---|
| Posted write vs payload, 8 TLPs each | See the table below. Peer advertises infinite credits and ACKs each TLP. Largest point is 1024 DW (4096 bytes): **1979.700 MB/s**, 98.985% of the 2000 MB/s Gen2 x4 symbol rate |
| Requester read vs payload, 8 TLPs each | MemRd32 and MemRd64 printed the same CplD-payload rate. Largest point is 1024 DW (4096 bytes): **1568.447 MB/s**, 78.422% of 2000 MB/s |
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
| 16 DW | 64 | 512 | 96 | 8 | 1333.333 | 66.667 |
| 32 DW | 128 | 1024 | 163 | 11 | 1570.552 | 78.528 |
| 64 DW | 256 | 2048 | 297 | 17 | 1723.906 | 86.195 |
| 128 DW | 512 | 4096 | 553 | 17 | 1851.718 | 92.586 |
| 256 DW | 1024 | 8192 | 1065 | 17 | 1923.005 | 96.150 |
| 512 DW | 2048 | 16384 | 2090 | 18 | 1959.809 | 97.990 |
| 1024 DW | 4096 | 32768 | 4138 | 18 | 1979.700 | 98.985 |

1024 DW is 4096 bytes on each TLP. The wire length field is 0 for that size. The "Bytes, 8 TLPs" column is the `bytes=` field from the PERF line, which sums all 8 packets. From 64 DW through 256 DW the window printed 17 RQ stall cycles. 512 DW and 1024 DW printed 18. Every size printed `credit_stall=0` and `tfc_nph_min=15`.

`perf_rq_memwr64_gen2_x4` is the same sweep with `addr[63:32]=1`, so the TLP type is MemWr64 (0x60). UVM reported 0 errors. Ten sizes printed the same cycles, stalls, and `mb_s` as the MemWr32 table. The 64-byte point printed `cycles=95`, `rq_stall=7`, `mb_s=1347.368`, `pct_gen2x4=67.368`. The 4096-byte point is again 1979.700 MB/s.

`perf_rq_sweep_gen3_x4` is the same 8-TLP MemWr32 sweep after L0 at 8 GT/s. UVM reported 0 errors. Printed `mb_s`: 250.000, 500.000, 800.000, 1084.746, 1280.000, 1488.372, 1651.613, 1815.603, 1896.296, 1943.074, 1967.339. The 4096-byte point is 1967.339 MB/s (`cycles=4164`, `rq_stall=44`, `pct_gen2x4=98.367`). Those points are the teal squares on the same chart.

`perf_rq_memrd_gen2_x4` sends eight MemRd32 at each size, then the same sizes as MemRd64. The byte count is CplD payload on RC. The peer returns one completion per request, with the request's tag, and advertises infinite credits. UVM reported 0 errors and 0 fatals. MemRd64 printed the same `cycles`, `mb_s`, and latency as MemRd32 at every size. Every size printed `rq_stall=0`, `credit_stall=0`, `tfc_zero=0`, and `tfc_nph_min=15`.

| Payload | Bytes / TLP | Bytes, 8 TLPs | user cycles | MB/s | % of 2000 MB/s | lat min / avg / max |
|---:|---:|---:|---:|---:|---:|---:|
| 1 DW | 4 | 32 | 103 | 77.670 | 3.883 | 51 / 61 / 71 |
| 2 DW | 8 | 64 | 109 | 146.789 | 7.339 | 54 / 66 / 77 |
| 4 DW | 16 | 128 | 116 | 275.862 | 13.793 | 56 / 70 / 84 |
| 8 DW | 32 | 256 | 144 | 444.444 | 22.222 | 63 / 87 / 112 |
| 16 DW | 64 | 512 | 184 | 695.652 | 34.783 | 75 / 113 / 152 |
| 32 DW | 128 | 1024 | 263 | 973.384 | 48.669 | 98 / 164 / 231 |
| 64 DW | 256 | 2048 | 424 | 1207.547 | 60.377 | 147 / 269 / 392 |
| 128 DW | 512 | 4096 | 743 | 1378.197 | 68.910 | 242 / 476 / 711 |
| 256 DW | 1024 | 8192 | 1383 | 1480.839 | 74.042 | 434 / 892 / 1351 |
| 512 DW | 2048 | 16384 | 2663 | 1538.115 | 76.906 | 818 / 1724 / 2631 |
| 1024 DW | 4096 | 32768 | 5223 | 1568.447 | 78.422 | 1586 / 3388 / 5191 |

1024 DW is 4096 bytes on each completion. The wire length field is 0 for that size. `bytes=32768` is eight completions. The window closes when `rc_tlast` reaches 8, so the drain between sizes is not inside the cycle count. At 4096 bytes, `lat_max - lat_min` is 3605 cycles across the seven gaps after the first completion, 515 cycles each, which is the frame on the wire. The printed 1568.447 MB/s still includes that first round trip (`lat_min=1586`). The amber posted-write formula is not this curve.

An earlier 16× 1DW run with a finite-credit peer and a one-cycle bubble between beats printed 83.333 MB/s. That number is not this curve.

Routed timing below is the streaming-TX image from 22 Nov 2026, before the completion-path RAM. Those logs are not the current netlist. The figures are the run properties after place and route, not a data rate.

| Board | WNS | TNS | WHS | Image |
|---|---:|---:|---:|---|
| VCU118 | +0.029814 ns | 0 | +0.011372 ns | bitstream, progress 100% |
| VMK180 | +0.052571 ns | 0 | +0.025194 ns | PDI, progress 100%, DRC 0 errors |

Gen2 x4 after 8b/10b is 2.000 GB/s of symbol data per direction. The sweep MB/s figures are payload bytes on the 4 ns user bus. The 4096-byte posted write is 1979.700 MB/s. The 4096-byte requester read is 1568.447 MB/s. The latency, inbound, and credit-stall figures above the timing table stay on the 8 ns clock they were measured with.
