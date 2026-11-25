# Gen3 16-byte datapath

**Closed.** Gen3 runs at 16 bytes per cycle. Gen4 runs at 32.

## Goal

Gen3 x4 user throughput must rise above the Gen2 x4 curve. Gen2 x4 stays on the 64-bit, 8-byte-per-cycle path. A Gen3 read sweep must finish with zero UVM errors.

## Why the curves match today

The published number is payload bytes on the 4 ns user clock. A 64-bit beat is 8 bytes, so the counter cannot exceed 2000 MB/s. Gen2 x4 wire rate is also 2000 MB/s, and large writes already sit on that ceiling.

Gen3 x4 wire rate is 8 GT/s × 4 × 128/130 = 3938 MB/s, which is 16 bytes per 4 ns cycle before encoding. The DLL/MAC beat is 64 bits, so the MAC never receives those 16 bytes. The read sweep also dies at 16-byte payloads because the peer treats a payload byte equal to STP, SDP, or END as a token.

## Approach

Keep one controller. The beat and the user port grow only when `GEN >= 3`.

- DLL to MAC beat payload is 128 bits with a 16-bit keep. A Gen2 beat sets only `keep[7:0]` and leaves the high half zero.
- At Gen3 the MAC emits a TLP as STP, a 2-byte little-endian DLL length, then that many DLL bytes. All four symbol times of a 32-bit pipe carry frame bytes. There is no END token on that path.
- The peer sends and observes that same layout. Payload bytes equal to STP, SDP, or END are not tokens.
- Gen3 user ports CQ, CC, RQ, and RC are 128 bits. The TL packs and unpacks 16 bytes per user clock. Gen2 ports stay 64 bits.
- The performance monitor keeps the 4 ns clock. A full 128-bit beat is 16 bytes, so the ceiling becomes 4000 MB/s.

## Out of scope

Gen4, preset search, message bus, and any change to `LTSSM_TIMER_SCALE`. Gen2 smokes stay on the 16-bit pipe and the 64-bit user port.

## Success

`perf_rq_memwr64_gen3_x4` and `perf_rq_memrd_gen3_x4` print `UVM_ERROR 0`. At 4096 bytes the Gen3 MemWr64 `mb_s` is above the Gen2 MemWr64 point (1979.700). The chart is updated only from those printed lines. Gen2 MemWr64 and Gen2 read smokes stay green.
