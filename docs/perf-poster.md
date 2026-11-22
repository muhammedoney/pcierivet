# Rivet Gen2 x4 — measured results

Endpoint `rivet_pcie_ctrl` at PIPE, 4 lanes. The posted-write sweep is QuestaSim 2024.1, 22 Nov 2026. The requester-read sweep is QuestaSim 2024.1, 23 Nov 2026. Both use `user_clk` at 4.0 ns. The read-latency, inbound, and credit-stall rows in the first table are the 21 Nov 2026 runs and still print `user_clk_ns=8.0`. Each row is printed `PERF` output. UVM reported 0 errors on each run.

| Test | Printed result |
|---|---|
| Posted write vs payload, 8 TLPs each | See the table below. Peer advertises infinite credits and ACKs each TLP. Largest point is 1024 DW (4096 bytes): **1979.700 MB/s**, 98.985% of the 2000 MB/s Gen2 x4 symbol rate |
| Requester read vs payload, 8 TLPs each | MemRd32 and MemRd64 printed the same CplD-payload rate. Largest point is 1024 DW (4096 bytes): **927.221 MB/s**, 46.361% of 2000 MB/s |
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

`perf_rq_memrd_gen2_x4` sends eight MemRd32 at each size, then the same sizes as MemRd64. The byte count is CplD payload on RC. The peer returns one completion per request, with the request's tag, and advertises infinite credits. UVM reported 0 errors and 0 fatals. MemRd64 printed the same `cycles`, `mb_s`, and latency as MemRd32 at every size. Every size printed `rq_stall=0`, `credit_stall=0`, `tfc_zero=0`, and `tfc_nph_min=15`.

| Payload | Bytes / TLP | Bytes, 8 TLPs | user cycles | MB/s | % of 2000 MB/s | lat min / avg / max |
|---:|---:|---:|---:|---:|---:|---:|
| 1 DW | 4 | 32 | 114 | 70.175 | 3.509 | 51 / 67 / 82 |
| 2 DW | 8 | 64 | 132 | 121.212 | 6.061 | 54 / 77 / 100 |
| 4 DW | 16 | 128 | 148 | 216.216 | 10.811 | 56 / 86 / 116 |
| 8 DW | 32 | 256 | 203 | 315.271 | 15.764 | 63 / 117 / 171 |
| 16 DW | 64 | 512 | 271 | 472.325 | 23.616 | 75 / 158 / 239 |
| 32 DW | 128 | 1024 | 404 | 633.663 | 31.683 | 98 / 235 / 372 |
| 64 DW | 256 | 2048 | 676 | 757.396 | 37.870 | 147 / 395 / 644 |
| 128 DW | 512 | 4096 | 1219 | 840.033 | 42.002 | 242 / 714 / 1187 |
| 256 DW | 1024 | 8192 | 2307 | 887.733 | 44.387 | 434 / 1354 / 2275 |
| 512 DW | 2048 | 16384 | 4483 | 913.674 | 45.684 | 818 / 2634 / 4451 |
| 1024 DW | 4096 | 32768 | 8835 | 927.221 | 46.361 | 1586 / 5194 / 8803 |

1024 DW is 4096 bytes on each completion. The wire length field is 0 for that size. `bytes=32768` is eight completions. The window closes when `rc_tlast` reaches 8, so the drain between sizes is not inside the cycle count. Capture of the next completion does not overlap playback of the current one, so a large read stays near half the symbol rate. The amber posted-write formula is not this curve.

An earlier 16× 1DW run with a finite-credit peer and a one-cycle bubble between beats printed 83.333 MB/s. That number is not this curve.

Routed timing below is the streaming-TX image from 22 Nov 2026, before the completion-path RAM. Those logs are not the current netlist. The figures are the run properties after place and route, not a data rate.

| Board | WNS | TNS | WHS | Image |
|---|---:|---:|---:|---|
| VCU118 | +0.029814 ns | 0 | +0.011372 ns | bitstream, progress 100% |
| VMK180 | +0.052571 ns | 0 | +0.025194 ns | PDI, progress 100%, DRC 0 errors |

Gen2 x4 after 8b/10b is 2.000 GB/s of symbol data per direction. The sweep MB/s figures are payload bytes on the 4 ns user bus. The 4096-byte posted write is 1979.700 MB/s. The 4096-byte requester read is 927.221 MB/s. The latency, inbound, and credit-stall figures above the timing table stay on the 8 ns clock they were measured with.
