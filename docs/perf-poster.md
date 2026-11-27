# Rivet x4 — measured results

Endpoint `rivet_pcie_ctrl` at PIPE, 4 lanes. The chart is the 27 Nov 2026 rerun of MemWr64 and MemRd64 at Gen2, Gen3, and Gen4. `user_clk` on those sweeps is 4.0 ns. The tables under the chart are those points, then the earlier MemWr32 and read runs that are not the curves. The read-latency, inbound, and credit-stall rows still print `user_clk_ns=8.0` and were not re-run.

![Rivet x4 throughput versus payload. Gen4 is in front; Gen3 and Gen2 are lighter on the same scale.](perf-rq-sweep.svg)

| Line | Rate |
|---|---|
| Gen2 x4 symbol data after 8b/10b | 2000 MB/s |
| Gen3 x4, 8 GT/s, 128b/130b | 3938 MB/s |
| Gen4 x4, 16 GT/s, 128b/130b | 7877 MB/s |

A full beat every 4 ns user clock is 2000 MB/s on the Gen2 64-bit port, 4000 MB/s on the Gen3 128-bit port, and 8000 MB/s on the Gen4 256-bit port. Payload sizes are 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, and 4096 bytes.

## Plotted sweeps

Eight TLPs per size, Questa 2024.1, 27 Nov 2026. The chart is MemWr64 and MemRd64. Gen4 RQ/RC is 256 bits and the DLL beat is 32 bytes. Every sweep printed every size through 4096 bytes.

| Bytes | Gen2 MemWr64 | Gen2 MemRd64 | Gen3 MemWr64 | Gen3 MemRd64 | Gen4 MemWr64 | Gen4 MemRd64 |
|---:|---:|---:|---:|---:|---:|---:|
| 4 | 250.000 | 88.889 | 333.333 | 87.912 | 888.889 | 101.266 |
| 8 | 500.000 | 158.416 | 666.667 | 172.043 | 1777.778 | 205.128 |
| 16 | 800.000 | 285.714 | 1333.333 | 320.000 | 3555.556 | 359.551 |
| 32 | 1142.857 | 444.444 | 2000.000 | 576.577 | 4923.077 | 703.297 |
| 64 | 1454.545 | 711.111 | 2666.667 | 914.286 | 6095.238 | 1280.000 |
| 128 | 1684.211 | 1007.874 | 3200.000 | 1462.857 | 6918.919 | 2015.748 |
| 256 | 1828.571 | 1286.432 | 3555.556 | 2081.301 | 7420.290 | 3200.000 |
| 512 | 1910.448 | 1492.711 | 3764.706 | 2639.175 | 7699.248 | 4612.613 |
| 1024 | 1954.198 | 1622.821 | 3878.788 | 3029.586 | 7846.743 | 5851.429 |
| 2048 | 1976.834 | 1696.769 | 3938.462 | 3271.565 | 7846.743 | 6759.076 |
| 4096 | 1988.350 | 1736.329 | 3968.992 | 3407.654 | 7922.631 | 7327.370 |

Gen4 MemWr64 (`perf_rq_memwr64_gen4_x4`, 8 TLPs after Gen4 L0) printed `credit_stall=0` and `tfc_nph_min=15`. `rq_stall` was 0 through 1024 bytes and 5 at 2048 and 4096 bytes. The 2048-byte point printed the same `mb_s` as 1024 bytes because the window grew from 261 cycles to 522. From 32 bytes up, each TLP ends 16 bytes into a beat and the burst packs the next descriptor into that half.

| Payload | Bytes / TLP | Bytes, 8 TLPs | user cycles | RQ stalls | MB/s |
|---:|---:|---:|---:|---:|---:|
| 1 DW | 4 | 32 | 9 | 0 | 888.889 |
| 2 DW | 8 | 64 | 9 | 0 | 1777.778 |
| 4 DW | 16 | 128 | 9 | 0 | 3555.556 |
| 8 DW | 32 | 256 | 13 | 0 | 4923.077 |
| 16 DW | 64 | 512 | 21 | 0 | 6095.238 |
| 32 DW | 128 | 1024 | 37 | 0 | 6918.919 |
| 64 DW | 256 | 2048 | 69 | 0 | 7420.290 |
| 128 DW | 512 | 4096 | 133 | 0 | 7699.248 |
| 256 DW | 1024 | 8192 | 261 | 0 | 7846.743 |
| 512 DW | 2048 | 16384 | 522 | 5 | 7846.743 |
| 1024 DW | 4096 | 32768 | 1034 | 5 | 7922.631 |

Gen4 MemRd64 (`perf_rq_memrd_gen4_x4`) counts CplD payload on RC. Every size printed `rq_stall=0`, `credit_stall=0`, `rc_tlast=8`. `UVM_ERROR : 0`, `UVM_FATAL : 0`. MemRd32 matched MemRd64 from 512 bytes up. Below that, MemRd32 printed 102.564, 205.128, 359.551, 703.297, 1254.902, 2000.000, and 3180.124.

| Payload | Bytes / TLP | Bytes, 8 TLPs | user cycles | MB/s |
|---:|---:|---:|---:|---:|
| 1 DW | 4 | 32 | 79 | 101.266 |
| 2 DW | 8 | 64 | 78 | 205.128 |
| 4 DW | 16 | 128 | 89 | 359.551 |
| 8 DW | 32 | 256 | 91 | 703.297 |
| 16 DW | 64 | 512 | 100 | 1280.000 |
| 32 DW | 128 | 1024 | 127 | 2015.748 |
| 64 DW | 256 | 2048 | 160 | 3200.000 |
| 128 DW | 512 | 4096 | 222 | 4612.613 |
| 256 DW | 1024 | 8192 | 350 | 5851.429 |
| 512 DW | 2048 | 16384 | 606 | 6759.076 |
| 1024 DW | 4096 | 32768 | 1118 | 7327.370 |

Gen2 MemWr64 printed `rq_stall=0`, `credit_stall=0`, and `tfc_nph_min=15` at every size. The 4096-byte point is 1988.350 MB/s in 4120 user cycles. Gen3 MemWr64 printed the same three fields, and 3968.992 MB/s at 4096 bytes in 2064 cycles. Those MemWr64 logs contained no `UVM_ERROR` through the last `PERF` line. The ready-hold after the sweep is two million cycles, so the runs were stopped there and have no report banner.

Gen2 MemRd64 printed `rq_stall=0`, `credit_stall=0`, `rc_tlast=8`, and `tfc_nph_min=15` at every size. The 4-byte point was `lat_min=50`, `lat_avg=53`, `lat_max=58`. The 4096-byte point was `lat_min=1074`, `lat_avg=2880`, `lat_max=4686` and 1736.329 MB/s. MemRd32 matched MemRd64 except at 4 bytes (87.912, 91 cycles) and 16 bytes (290.909, 110 cycles). A later run the same day printed no `UVM_ERROR` through the last `PERF` line, and the 8-byte points had `rc_accept=32`. `mb_s` did not change. The ready-hold was stopped before the report banner. Gen3 MemRd64 printed `UVM_ERROR : 0` and `UVM_FATAL : 0`. MemRd32 matched it except at 4 bytes (85.106) and 128 bytes (1430.168). The 4096-byte Gen3 read is 3407.654 MB/s in 2404 cycles, `lat_min=561`, `lat_avg=1474`, `lat_max=2388`.

## Gen2 posted write, 22 Nov 2026

`perf_rq_sweep_gen2_x4`, 8 MemWr32 TLPs per size, 0 UVM errors. This is not the plotted Gen2 MemWr64 column. Each size waits 8000 `pclk` cycles so the previous burst's replay is finished. `mb_s` is payload bytes on the 4 ns user bus (`bytes * 250 / cycles`). Every size printed `credit_stall=0` and `tfc_nph_min=15`.

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

1024 DW is 4096 bytes on each TLP. The wire length field is 0 for that size. The "Bytes, 8 TLPs" column is the `bytes=` field from the PERF line.

`perf_rq_memwr64_gen2_x4` on that 22 Nov bench is MemWr64 (`addr[63:32]=1`, TLP type 0x60). UVM reported 0 errors. Ten sizes printed the same cycles, stalls, and `mb_s` as the MemWr32 table. The 64-byte point printed `cycles=95`, `rq_stall=7`, `mb_s=1347.368`, `pct_gen2x4=67.368`. The 4096-byte point is again 1979.700 MB/s. The plotted Gen2 MemWr64 column is the 27 Nov rerun and ends at 1988.350 MB/s, with `rq_stall=0` at every size.

An earlier 16× 1DW run with a finite-credit peer and a one-cycle bubble between beats printed 83.333 MB/s. That number is not either posted-write curve.

## Gen3 posted write, 24 Nov 2026

`perf_rq_sweep_gen3_x4`, 8 MemWr32 TLPs after L0 at 8 GT/s, 0 UVM errors. `pct_gen2x4` is still the fraction of 2000 MB/s, not of the 3938 MB/s Gen3 line. This MemWr32 sweep is not the plotted Gen3 MemWr64 column.

| Payload | Bytes / TLP | Bytes, 8 TLPs | user cycles | RQ stalls | MB/s | % of 2000 MB/s |
|---:|---:|---:|---:|---:|---:|---:|
| 1 DW | 4 | 32 | 32 | 0 | 250.000 | 12.500 |
| 2 DW | 8 | 64 | 32 | 0 | 500.000 | 25.000 |
| 4 DW | 16 | 128 | 40 | 0 | 800.000 | 40.000 |
| 8 DW | 32 | 256 | 59 | 3 | 1084.746 | 54.237 |
| 16 DW | 64 | 512 | 100 | 12 | 1280.000 | 64.000 |
| 32 DW | 128 | 1024 | 172 | 20 | 1488.372 | 74.419 |
| 64 DW | 256 | 2048 | 310 | 30 | 1651.613 | 82.581 |
| 128 DW | 512 | 4096 | 564 | 28 | 1815.603 | 90.780 |
| 256 DW | 1024 | 8192 | 1080 | 32 | 1896.296 | 94.815 |
| 512 DW | 2048 | 16384 | 2108 | 36 | 1943.074 | 97.154 |
| 1024 DW | 4096 | 32768 | 4164 | 44 | 1967.339 | 98.367 |

## Gen2 requester read, 23 Nov 2026

`perf_rq_memrd_gen2_x4` on 23 Nov 2026 sent eight MemRd32 at each size, then the same sizes as MemRd64. The byte count is CplD payload on RC. The peer returns one completion per request and advertises infinite credits. That run reported 0 errors and 0 fatals. MemRd64 printed the same `cycles`, `mb_s`, and latency as MemRd32 at every size. Every size printed `rq_stall=0`, `credit_stall=0`, `tfc_zero=0`, and `tfc_nph_min=15`. This table is the 23 Nov run. The dashed Gen2 curve on the chart is the 27 Nov MemRd64 rerun and ends at 1736.329 MB/s.

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

1024 DW is 4096 bytes on each completion. The window closes when `rc_tlast` reaches 8, so the drain between sizes is not inside the cycle count. At 4096 bytes, `lat_max - lat_min` is 3605 cycles across the seven gaps after the first completion, 515 cycles each. The printed 1568.447 MB/s still includes that first round trip (`lat_min=1586`).

## Other Gen2 prints

| Test | Printed result |
|---|---|
| Read latency, 8× RQ MemRd → RC CplD | min 363, avg 458, max 714 `user_clk` cycles on the 8.0 ns bench. Includes the PIPE peer. Not re-run at 4 ns |
| Inbound, 8× CQ MemRd → CC CplD | 8 CQ packets and 8 CC completions, 32 payload bytes in 2876 `user_clk` cycles. **1.391 MB/s** at `user_clk_ns=8.0`. The window includes the wait for each peer MemRd |
| Credit stall, 12× RQ MemRd | 0 RQ stall cycles, 0 cycles with `pcie_tfc_nph_av = 0`. Lowest NPH credit scale observed: 4. Measured at `user_clk_ns=8.0` |

Routed timing below is the streaming-TX image from 22 Nov 2026, before the completion-path RAM. Those logs are not the current netlist. The figures are the run properties after place and route, not a data rate.

| Board | WNS | TNS | WHS | Image |
|---|---:|---:|---:|---|
| VCU118 | +0.029814 ns | 0 | +0.011372 ns | bitstream, progress 100% |
| VMK180 | +0.052571 ns | 0 | +0.025194 ns | PDI, progress 100%, DRC 0 errors |
