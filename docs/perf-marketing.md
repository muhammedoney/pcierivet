# Rivet performance note

Rivet is a soft PCIe endpoint. The controller is `rivet_pcie_ctrl`. The figures below were printed by QuestaSim 2024.1 on 21 Nov 2026, or by the VMK180 route. Nothing else is quoted as a measurement.

## Link under test

Gen2 x4 endpoint, DUT at the PIPE. The UVM bench clock `user_clk` is 8.0 ns, so one 64-bit beat every cycle is 1.000 GB/s on that bus. The PIPE clock in the same bench is 4 ns. Gen2 x4 symbol data after 8b/10b is 2.000 GB/s per direction. Payload is a fraction of that once headers, LCRC, and DLLPs are counted. The tests do not claim that fraction beyond the `pct_gen2x4` field they print.

## Posted writes

`perf_rq_memwr_gen2_x4` sent 16 memory writes of 1 dword. The monitor counted 4 payload bytes on each RQ `tlast`.

```
PERF tag=rq_memwr bytes=64 cycles=96 rq_accept=48 rq_stall=0 rq_tlast=16 mb_s=83.333 pct_gen2x4=4.167 credit_stall_pct=0.000 user_clk_ns=8.0
```

64 bytes in 96 user clocks is 83.333 MB/s. No beat waited on `tready`. 83.333 / 2000 is the printed 4.167% of the Gen2 x4 symbol rate. The peer advertises 32 posted header credits, so the burst stops at 16 writes, inside that budget.

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

That is setup and hold slack. It is not a throughput result.

## Not in these numbers

The PG213 and PG239 benches can count accepted beats on the endpoint application. They were not run for this note, so they contribute no beat counts.
