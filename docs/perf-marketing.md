# Rivet performance note

Rivet is a soft PCIe endpoint. The controller is `rivet_pcie_ctrl`. The posted-write sweep was printed by QuestaSim 2024.1 on 22 Nov 2026. The requester-read sweep was printed by the same simulator on 23 Nov 2026. Read latency, inbound, and credit stall were printed on 21 Nov 2026. The FPGA slack below is the 22 Nov streaming-TX image, before the completion-path RAM, and is not a current route. Nothing else is quoted as a measurement.

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

`perf_rq_memwr64_gen2_x4` repeats the sweep as MemWr64 (`addr[63:32]=1`). UVM reported 0 errors. The 4-byte through 32-byte points, and every point from 128 bytes up, printed the same `cycles`, `rq_stall`, and `mb_s` as MemWr32. The 64-byte point differed:

```
PERF tag=rq64_dw16 bytes=512 cycles=95 rq_stall=7 rq_tlast=8 mb_s=1347.368 pct_gen2x4=67.368 user_clk_ns=4.0
```

The 4096-byte MemWr64 point printed 1979.700 MB/s again.

`perf_rq_sweep_gen3_x4` repeats the MemWr32 sweep after L0 at 8 GT/s. UVM reported 0 errors. Printed `mb_s` from 4 bytes through 4096 bytes: 250.000, 500.000, 800.000, 1084.746, 1280.000, 1488.372, 1651.613, 1815.603, 1896.296, 1943.074, 1967.339. The 4096-byte point printed `cycles=4164`, `rq_stall=44`, `pct_gen2x4=98.367`.

Re-run cpld to confirm the scrambler reseed didn't break the completion, then commit. The work lib is gen3 so incremental is fine.

## Requester reads versus payload size

`perf_rq_memrd_gen2_x4` sends 8 MemRd32 TLPs at each size from 1 DW through 1024 DW, then the same sizes as MemRd64. The monitor counts CplD payload bytes on RC and stays armed until `rc_tlast=8`. The peer returns one completion per request and advertises infinite credits. UVM reported 0 errors and 0 fatals. MemRd64 printed the same cycles and `mb_s` as MemRd32 at every size. Every size printed `rq_stall=0`, `credit_stall=0`, and `tfc_nph_min=15`.

```
PERF tag=rd_dw1    bytes=32    cycles=103  rc_tlast=8 mb_s=77.670  pct_gen2x4=3.883  user_clk_ns=4.0
PERF tag=rd_dw2    bytes=64    cycles=109  rc_tlast=8 mb_s=146.789 pct_gen2x4=7.339  user_clk_ns=4.0
PERF tag=rd_dw4    bytes=128   cycles=116  rc_tlast=8 mb_s=275.862 pct_gen2x4=13.793 user_clk_ns=4.0
PERF tag=rd_dw8    bytes=256   cycles=144  rc_tlast=8 mb_s=444.444 pct_gen2x4=22.222 user_clk_ns=4.0
PERF tag=rd_dw16   bytes=512   cycles=184  rc_tlast=8 mb_s=695.652 pct_gen2x4=34.783 user_clk_ns=4.0
PERF tag=rd_dw32   bytes=1024  cycles=263  rc_tlast=8 mb_s=973.384 pct_gen2x4=48.669 user_clk_ns=4.0
PERF tag=rd_dw64   bytes=2048  cycles=424  rc_tlast=8 mb_s=1207.547 pct_gen2x4=60.377 user_clk_ns=4.0
PERF tag=rd_dw128  bytes=4096  cycles=743  rc_tlast=8 mb_s=1378.197 pct_gen2x4=68.910 user_clk_ns=4.0
PERF tag=rd_dw256  bytes=8192  cycles=1383 rc_tlast=8 mb_s=1480.839 pct_gen2x4=74.042 user_clk_ns=4.0
PERF tag=rd_dw512  bytes=16384 cycles=2663 rc_tlast=8 mb_s=1538.115 pct_gen2x4=76.906 user_clk_ns=4.0
PERF tag=rd_dw1024 bytes=32768 cycles=5223 rc_tlast=8 mb_s=1568.447 pct_gen2x4=78.422 user_clk_ns=4.0
```

The 4096-byte point is 1568.447 MB/s. `rd64_dw1` through `rd64_dw1024` printed those same eleven rates. Latency on the 4-byte point was `lat_min=51`, `lat_avg=61`, `lat_max=71`. On the 4096-byte point it was `lat_min=1586`, `lat_avg=3388`, `lat_max=5191`. The seven gaps after the first 4096-byte completion are 515 cycles each. The printed rate includes the first round trip.

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
