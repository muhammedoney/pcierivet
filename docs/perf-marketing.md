# Rivet performance note

Rivet is a soft PCIe controller. The MemWr32 block below is the Gen2 x4 measurement from 22 Nov 2026. MemWr64 and MemRd were re-run on 27 Nov 2026. Gen3 and Gen4 x4 sweeps are in [perf-poster.md](perf-poster.md). Nothing else is quoted as a measurement.

## Link under test

Gen2 x4 endpoint, DUT at the PIPE. The posted-write sweep uses `user_clk` at 4.0 ns, so one 64-bit beat every cycle is 2.000 GB/s on that bus. The PIPE clock is 4 ns. Gen2 x4 symbol data after 8b/10b is 2.000 GB/s per direction. Payload is a fraction of that once headers, LCRC, and DLLPs are counted. The tests do not claim that fraction beyond the `pct_gen2x4` field they print. Read latency, inbound, and credit stall below were printed when `user_clk` was 8.0 ns and were not re-run.

## Posted writes versus payload size

`perf_rq_sweep_gen2_x4` sends 8 MemWr32 TLPs at each size from 1 DW (4 bytes) through the Max Payload Size steps to 1024 DW (4096 bytes). The PIPE peer is in performance mode. InitFC advertises infinite posted, non-posted, and completion credits, and the peer ACKs each TLP so the 16-deep replay buffer is not the limit. Eight thousand `pclk` cycles separate the sizes. The monitor counts payload bytes from RQ `tlast` to the next size's disarm.

```
PERF tag=rq_dw1    bytes=32    cycles=32   rq_stall=0  rq_tlast=8 mb_s=250.000 pct_gen2x4=12.500 user_clk_ns=4.0
PERF tag=rq_dw2    bytes=64    cycles=32   rq_stall=0  rq_tlast=8 mb_s=500.000 pct_gen2x4=25.000 user_clk_ns=4.0
PERF tag=rq_dw4    bytes=128   cycles=40   rq_stall=0  rq_tlast=8 mb_s=800.000 pct_gen2x4=40.000 user_clk_ns=4.0
PERF tag=rq_dw8    bytes=256   cycles=57   rq_stall=1  rq_tlast=8 mb_s=1122.807 pct_gen2x4=56.140 user_clk_ns=4.0
PERF tag=rq_dw16   bytes=512   cycles=96   rq_stall=8  rq_tlast=8 mb_s=1333.333 pct_gen2x4=66.667 user_clk_ns=4.0
PERF tag=rq_dw32   bytes=1024  cycles=163  rq_stall=11 rq_tlast=8 mb_s=1570.552 pct_gen2x4=78.528 user_clk_ns=4.0
PERF tag=rq_dw64   bytes=2048  cycles=297  rq_stall=17 rq_tlast=8 mb_s=1723.906 pct_gen2x4=86.195 user_clk_ns=4.0
PERF tag=rq_dw128  bytes=4096  cycles=553  rq_stall=17 rq_tlast=8 mb_s=1851.718 pct_gen2x4=92.586 user_clk_ns=4.0
PERF tag=rq_dw256  bytes=8192  cycles=1065 rq_stall=17 rq_tlast=8 mb_s=1923.005 pct_gen2x4=96.150 user_clk_ns=4.0
PERF tag=rq_dw512  bytes=16384 cycles=2090 rq_stall=18 rq_tlast=8 mb_s=1959.809 pct_gen2x4=97.990 user_clk_ns=4.0
PERF tag=rq_dw1024 bytes=32768 cycles=4138 rq_stall=18 rq_tlast=8 mb_s=1979.700 pct_gen2x4=98.985 user_clk_ns=4.0
```

UVM reported 0 errors and 0 fatals. 1024 DW is 4096 bytes per TLP; `bytes=32768` is 8 of those packets. That point is 1979.700 MB/s, the printed 98.985% of the 2000 MB/s Gen2 x4 symbol rate. Every size printed `credit_stall=0` and `tfc_nph_min=15`. From 64 DW through 256 DW the window printed `rq_stall=17`. 512 DW and 1024 DW printed `rq_stall=18`.

`perf_rq_memwr64_gen2_x4` was re-run on 27 Nov 2026 as MemWr64 (`addr[63:32]=1`). Every size printed `rq_stall=0`, `credit_stall=0`, `rq_tlast=8`, and `tfc_nph_min=15`. The 4-byte, 8-byte, 16-byte, and 32-byte points printed the same `mb_s` as the 22 Nov MemWr32 block. From 64 bytes up the rerun is higher, and the 4096-byte point is 1988.350 MB/s.

```
PERF tag=rq64_dw1    bytes=32    cycles=32   rq_stall=0 rq_tlast=8 mb_s=250.000 pct_gen2x4=12.500 user_clk_ns=4.0
PERF tag=rq64_dw2    bytes=64    cycles=32   rq_stall=0 rq_tlast=8 mb_s=500.000 pct_gen2x4=25.000 user_clk_ns=4.0
PERF tag=rq64_dw4    bytes=128   cycles=40   rq_stall=0 rq_tlast=8 mb_s=800.000 pct_gen2x4=40.000 user_clk_ns=4.0
PERF tag=rq64_dw8    bytes=256   cycles=56   rq_stall=0 rq_tlast=8 mb_s=1142.857 pct_gen2x4=57.143 user_clk_ns=4.0
PERF tag=rq64_dw16   bytes=512   cycles=88   rq_stall=0 rq_tlast=8 mb_s=1454.545 pct_gen2x4=72.727 user_clk_ns=4.0
PERF tag=rq64_dw32   bytes=1024  cycles=152  rq_stall=0 rq_tlast=8 mb_s=1684.211 pct_gen2x4=84.211 user_clk_ns=4.0
PERF tag=rq64_dw64   bytes=2048  cycles=280  rq_stall=0 rq_tlast=8 mb_s=1828.571 pct_gen2x4=91.429 user_clk_ns=4.0
PERF tag=rq64_dw128  bytes=4096  cycles=536  rq_stall=0 rq_tlast=8 mb_s=1910.448 pct_gen2x4=95.522 user_clk_ns=4.0
PERF tag=rq64_dw256  bytes=8192  cycles=1048 rq_stall=0 rq_tlast=8 mb_s=1954.198 pct_gen2x4=97.710 user_clk_ns=4.0
PERF tag=rq64_dw512  bytes=16384 cycles=2072 rq_stall=0 rq_tlast=8 mb_s=1976.834 pct_gen2x4=98.842 user_clk_ns=4.0
PERF tag=rq64_dw1024 bytes=32768 cycles=4120 rq_stall=0 rq_tlast=8 mb_s=1988.350 pct_gen2x4=99.417 user_clk_ns=4.0
```

`perf_rq_sweep_gen3_x4` repeats the MemWr32 sweep after L0 at 8 GT/s. That 24 Nov run reported 0 errors. Printed `mb_s` from 4 bytes through 4096 bytes: 250.000, 500.000, 800.000, 1084.746, 1280.000, 1488.372, 1651.613, 1815.603, 1896.296, 1943.074, 1967.339. The 4096-byte point printed `cycles=4164`, `rq_stall=44`, `pct_gen2x4=98.367`. It was not re-run on 27 Nov. The Gen3 MemWr64 column in the poster is a different sweep.

## Requester reads versus payload size

`perf_rq_memrd_gen2_x4` was re-run on 27 Nov 2026. It sends 8 MemRd32 TLPs at each size from 1 DW through 1024 DW, then the same sizes as MemRd64. The monitor counts CplD payload bytes on RC and stays armed until `rc_tlast=8`. The peer returns one completion per request and advertises infinite credits. Every size printed `rq_stall=0`, `credit_stall=0`, `rc_tlast=8`, and `tfc_nph_min=15`. The scoreboard printed `UVM_ERROR : 4` and `UVM_FATAL : 0`. All four errors were `RC completion unmatched tag=0x00 req=0x004a`, two during 8-byte MemRd32 and two during 8-byte MemRd64.

MemRd64:

```
PERF tag=rd64_dw1    bytes=32    cycles=90   rc_tlast=8 mb_s=88.889  pct_gen2x4=4.444  user_clk_ns=4.0
PERF tag=rd64_dw2    bytes=64    cycles=101  rc_tlast=8 mb_s=158.416 pct_gen2x4=7.921  user_clk_ns=4.0
PERF tag=rd64_dw4    bytes=128   cycles=112  rc_tlast=8 mb_s=285.714 pct_gen2x4=14.286 user_clk_ns=4.0
PERF tag=rd64_dw8    bytes=256   cycles=144  rc_tlast=8 mb_s=444.444 pct_gen2x4=22.222 user_clk_ns=4.0
PERF tag=rd64_dw16   bytes=512   cycles=180  rc_tlast=8 mb_s=711.111 pct_gen2x4=35.556 user_clk_ns=4.0
PERF tag=rd64_dw32   bytes=1024  cycles=254  rc_tlast=8 mb_s=1007.874 pct_gen2x4=50.394 user_clk_ns=4.0
PERF tag=rd64_dw64   bytes=2048  cycles=398  rc_tlast=8 mb_s=1286.432 pct_gen2x4=64.322 user_clk_ns=4.0
PERF tag=rd64_dw128  bytes=4096  cycles=686  rc_tlast=8 mb_s=1492.711 pct_gen2x4=74.636 user_clk_ns=4.0
PERF tag=rd64_dw256  bytes=8192  cycles=1262 rc_tlast=8 mb_s=1622.821 pct_gen2x4=81.141 user_clk_ns=4.0
PERF tag=rd64_dw512  bytes=16384 cycles=2414 rc_tlast=8 mb_s=1696.769 pct_gen2x4=84.838 user_clk_ns=4.0
PERF tag=rd64_dw1024 bytes=32768 cycles=4718 rc_tlast=8 mb_s=1736.329 pct_gen2x4=86.816 user_clk_ns=4.0
```

The 4096-byte point is 1736.329 MB/s. MemRd32 printed the same `mb_s` from 32 bytes up. It differed at 4 bytes (87.912, 91 cycles) and 16 bytes (290.909, 110 cycles). Latency on the 4-byte MemRd64 point was `lat_min=50`, `lat_avg=53`, `lat_max=58`. On the 4096-byte point it was `lat_min=1074`, `lat_avg=2880`, `lat_max=4686`. The printed rate includes the first round trip.

An earlier `perf_rq_memwr_gen2_x4` run (16× 1DW, finite credits, one idle user clock between beats) printed 83.333 MB/s. That run is not the payload curve.

## Read latency

`perf_rq_rc_lat_gen2_x4` issued eight RQ MemRd32 and waited for the PIPE peer to return CplD on RC. Eight latencies were recorded, in `user_clk` cycles from the RQ `tlast` accept to the RC `tlast` accept:

```
PERF tag=rq_rc_lat lat_n=8 lat_min=363 lat_avg=458 lat_max=714 user_clk_ns=8.0
```

At 8.0 ns that is 2.904 us, 3.664 us, and 5.712 us. The peer's inject delay is part of the number.

## Inbound reads

`perf_cq_cc_gen2_x4` took eight MemRd32 from the PIPE peer and answered each with a 1DW CplD on CC. The log shows 8 CQ packets and 8 CC completions, 0 errors.

```
PERF tag=cq_cc bytes=32 cycles=2876 cq_tlast=8 cc_tlast=8 mb_s=1.391 pct_gen2x4=0.070 user_clk_ns=8.0
```

32 payload bytes over 2876 user clocks is 1.391 MB/s. Most of those cycles are the gap while the peer prepares the next MemRd, not the CC beat itself.

## Credit stall

`perf_credit_stall_gen2_x4` sent 12 RQ MemRd32 while sampling `pcie_tfc_nph_av`. The peer advertises 16 non-posted header credits. The run stayed inside that.

```
PERF tag=credit_stall rq_accept=24 rq_stall=0 rq_tlast=12 credit_stall=0 tfc_zero=0 tfc_nph_min=4 credit_stall_pct=0.000
```

No RQ beat was held. The credit scale never read 0. The lowest value seen was 4, which on this port means 4 header credits (the value 15 would mean 15 or more).

## FPGA timing

Post-route slack on the streaming-TX image, 22 Nov 2026, before the completion-path RAM. These logs are not a route of the current netlist. The figures are the implementation run properties. They are not throughput.

VCU118 (XCVU9P, PG239), `fpga/vcu118/impl.console.log`:

- WNS +0.029814 ns
- TNS 0
- WHS +0.011372 ns
- `write_bitstream` completed, progress 100%

VMK180 (XCVM1802, PG345), `fpga/vmk180/impl.console.log`:

- WNS +0.052571 ns
- TNS 0
- WHS +0.025194 ns
- `write_device_image` completed, DRC 0 errors, progress 100%

## Not in these numbers

The PG213 and PG239 benches can count accepted beats on the endpoint application. They were not run for this note, so they contribute no beat counts.
