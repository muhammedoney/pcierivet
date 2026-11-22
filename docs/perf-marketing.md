# Rivet performance note

Rivet is a soft PCIe endpoint. The controller is `rivet_pcie_ctrl`. The posted-write sweep was printed by QuestaSim 2024.1 on 22 Nov 2026. Read latency, inbound, and credit stall were printed on 21 Nov 2026. The VMK180 numbers are from the route log. Nothing else is quoted as a measurement.

## Link under test

Gen2 x4 endpoint, DUT at the PIPE. The posted-write sweep uses `user_clk` at 4.0 ns, so one 64-bit beat every cycle is 2.000 GB/s on that bus. The PIPE clock is 4 ns. Gen2 x4 symbol data after 8b/10b is 2.000 GB/s per direction. Payload is a fraction of that once headers, LCRC, and DLLPs are counted. The tests do not claim that fraction beyond the `pct_gen2x4` field they print. Read latency, inbound, and credit stall below were printed when `user_clk` was 8.0 ns and were not re-run.

## Posted writes versus payload size

`perf_rq_sweep_gen2_x4` sends 8 MemWr32 TLPs at each size from 1 DW (4 bytes) through the Max Payload Size steps to 1024 DW (4096 bytes). The PIPE peer is in performance mode. InitFC advertises infinite posted, non-posted, and completion credits, and the peer ACKs each TLP so the 16-deep replay buffer is not the limit. Eight thousand `pclk` cycles separate the sizes. The monitor counts payload bytes from RQ `tlast` to the next size's disarm.

```
PERF tag=rq_dw1    bytes=32    cycles=32   rq_stall=0  rq_tlast=8 mb_s=250.000 pct_gen2x4=12.500 user_clk_ns=4.0
PERF tag=rq_dw2    bytes=64    cycles=32   rq_stall=0  rq_tlast=8 mb_s=500.000 pct_gen2x4=25.000 user_clk_ns=4.0
PERF tag=rq_dw4    bytes=128   cycles=40   rq_stall=0  rq_tlast=8 mb_s=800.000 pct_gen2x4=40.000 user_clk_ns=4.0
PERF tag=rq_dw8    bytes=256   cycles=57   rq_stall=1  rq_tlast=8 mb_s=1122.807 pct_gen2x4=56.140 user_clk_ns=4.0
PERF tag=rq_dw16   bytes=512   cycles=95   rq_stall=7  rq_tlast=8 mb_s=1347.368 pct_gen2x4=67.368 user_clk_ns=4.0
PERF tag=rq_dw32   bytes=1024  cycles=161  rq_stall=9  rq_tlast=8 mb_s=1590.062 pct_gen2x4=79.503 user_clk_ns=4.0
PERF tag=rq_dw64   bytes=2048  cycles=293  rq_stall=13 rq_tlast=8 mb_s=1747.440 pct_gen2x4=87.372 user_clk_ns=4.0
PERF tag=rq_dw128  bytes=4096  cycles=549  rq_stall=13 rq_tlast=8 mb_s=1865.209 pct_gen2x4=93.260 user_clk_ns=4.0
PERF tag=rq_dw256  bytes=8192  cycles=1061 rq_stall=13 rq_tlast=8 mb_s=1930.254 pct_gen2x4=96.513 user_clk_ns=4.0
PERF tag=rq_dw512  bytes=16384 cycles=2085 rq_stall=13 rq_tlast=8 mb_s=1964.508 pct_gen2x4=98.225 user_clk_ns=4.0
PERF tag=rq_dw1024 bytes=32768 cycles=4133 rq_stall=13 rq_tlast=8 mb_s=1982.095 pct_gen2x4=99.105 user_clk_ns=4.0
```

UVM reported 0 errors and 0 fatals. 1024 DW is 4096 bytes per TLP; `bytes=32768` is 8 of those packets. That point is 1982.095 MB/s, the printed 99.105% of the 2000 MB/s Gen2 x4 symbol rate. Every size printed `credit_stall=0` and `tfc_nph_min=15`. From 64 DW up the same window printed `rq_stall=13`.

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

VMK180 (XCVM1802, PG345 GTY) Gen2 x4, post-route in `fpga/vmk180/impl.log`:

- WNS +0.143 ns (property 0.142599 ns)
- TNS 0
- WHS +0.019 ns (property 0.018743 ns)
- THS 0

That is setup and hold slack from the netlist before the 4 KB transmit slot. It is not a throughput result, and it does not apply to this RTL.

## Not in these numbers

The PG213 and PG239 benches can count accepted beats on the endpoint application. They were not run for this note, so they contribute no beat counts.
