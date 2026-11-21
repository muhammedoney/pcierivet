# Rivet Gen2 x4 — measured results

Endpoint `rivet_pcie_ctrl` at PIPE, 4 lanes. QuestaSim 2024.1, 21 Nov 2026. `user_clk` in `rivet_tb_top` is 8.0 ns. Each row is printed `PERF` output. UVM reported 0 errors on each run.

| Test | Printed result |
|---|---|
| Posted write vs payload, 8 TLPs each | See the table below. Peer advertises infinite credits and ACKs each TLP. Largest point is 1024 DW (4096 bytes): **994.416 MB/s**, 49.721% of the 2000 MB/s Gen2 x4 symbol rate |
| Read latency, 8× RQ MemRd → RC CplD | min 363, avg 458, max 714 `user_clk` cycles. Includes the PIPE peer |
| Inbound, 8× CQ MemRd → CC CplD | 8 CQ packets and 8 CC completions, 32 payload bytes in 2876 `user_clk` cycles. **1.391 MB/s**. The window includes the wait for each peer MemRd |
| Credit stall, 12× RQ MemRd | 0 RQ stall cycles, 0 cycles with `pcie_tfc_nph_av = 0`. Lowest NPH credit scale observed: 4 |

Posted-write payload sweep, test `perf_rq_sweep_gen2_x4`, 8 MemWr32 TLPs per size, 0 UVM errors. Sizes are the PCIe Max Payload Size steps through 4096 bytes, plus the smaller points. Each size waits 8000 `pclk` cycles so the previous burst's replay is finished. `mb_s` is payload bytes on the 8 ns user bus (`bytes * 125 / cycles`). A full 64-bit beat every user clock is 1000 MB/s, so that bus is the ceiling. A 4096-byte TLP also spends two descriptor beats, which is why 994.416 MB/s is the top of this port.

| Payload | Bytes / TLP | Bytes, 8 TLPs | user cycles | RQ stalls | MB/s | % of 2000 MB/s |
|---:|---:|---:|---:|---:|---:|---:|
| 1 DW | 4 | 32 | 31 | 0 | 129.032 | 6.452 |
| 2 DW | 8 | 64 | 31 | 0 | 258.065 | 12.903 |
| 4 DW | 16 | 128 | 39 | 0 | 410.256 | 20.513 |
| 8 DW | 32 | 256 | 55 | 0 | 581.818 | 29.091 |
| 16 DW | 64 | 512 | 87 | 0 | 735.632 | 36.782 |
| 32 DW | 128 | 1024 | 151 | 0 | 847.682 | 42.384 |
| 64 DW | 256 | 2048 | 279 | 0 | 917.563 | 45.878 |
| 128 DW | 512 | 4096 | 535 | 0 | 957.009 | 47.850 |
| 256 DW | 1024 | 8192 | 1047 | 0 | 978.032 | 48.902 |
| 512 DW | 2048 | 16384 | 2071 | 0 | 988.894 | 49.445 |
| 1024 DW | 4096 | 32768 | 4119 | 0 | 994.416 | 49.721 |

1024 DW is 4096 bytes on each TLP. The wire length field is 0 for that size. The "Bytes, 8 TLPs" column is the `bytes=` field from the PERF line, which sums all 8 packets. Every row had `rq_stall=0`. Reads are not in this table: the completer and requester-completion paths still pack 1 DW.

An earlier 16× 1DW run with a finite-credit peer and a one-cycle bubble between beats printed 83.333 MB/s. That number is not this curve.

VMK180 routed timing, from `fpga/vmk180/impl.log`, is a separate fact: WNS +0.143 ns, TNS 0, WHS +0.019 ns, THS 0. That slack is from the netlist before the 4 KB transmit slot. It is not a data rate and it does not apply to this RTL.

Gen2 x4 after 8b/10b is 2.000 GB/s of symbol data per direction. The MB/s figures above are payload bytes on the 8 ns user bus, not that line rate.
