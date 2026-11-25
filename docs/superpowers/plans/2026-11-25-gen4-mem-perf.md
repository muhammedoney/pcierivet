# Gen4 MemWr / MemRd throughput Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Raise Gen4 x4 MemWr64 and MemRd64 throughput by removing the idle user cycle between posted writes and the store-and-forward wait on completions.

**Architecture:** `rivet_tl_rq_g4` keeps a 64-byte residue so a TLP's last DLL beat leaves on the cycle the last user beat is accepted, and a descriptor beat may carry 16 payload bytes. The Gen4 perf sequences send eight TLPs as one burst. `rivet_mac_os_rx` on a 64-bit PIPE starts playback after one committed beat instead of waiting for end of packet.

**Tech Stack:** SystemVerilog, Verilator lint (`scripts/lint.ps1`), Questa UVM (`scripts/sim_questa.ps1`).

## Global Constraints

- English only in code, comments, commits, and docs.
- Gen2 elaboration stays `PIPE_DATA_WIDTH=16`. Gen3 stays 32. Gen4 is 64.
- RX cut-through is `PIPE_DATA_WIDTH >= 64` only.
- No vendor cells in `rtl/pcie_ctrl/`.
- Do not change `LTSSM_TIMER_SCALE`.
- Quote MB/s only from a run that printed the number and `UVM_ERROR : 0`.

---

### Task 1: RQ residue and in-beat payload

**Files:**
- Modify: `rtl/pcie_ctrl/tl/rivet_tl_rq_g4.sv`
- Modify: `tb/uvm/seq/rivet_axi_rq_memwr_seq.svh`
- Modify: `tb/uvm/seq/rivet_axi_rq_memrd32_seq.svh`
- Modify: `tb/uvm/seq/rivet_perf_vseq.svh` (Gen4 branch of MemWr64 and MemRd only)

**Interfaces:**
- Consumes: 256-bit RQ beats. Descriptor in `[127:0]`. Payload may occupy `[255:128]` when `tkeep[7:4]` is set.
- Produces: 32-byte DLL beats with `tlast` on the last byte of the TLP, same cycle the finishing user beat is accepted when the DLL slot is free.

- [x] **Step 1: Residue packer**

`rivet_tl_rq_g4` holds up to 64 residue bytes. Peel 32 into the DLL beat when the slot is free. A finished packet with 1..32 bytes left peels that short beat with `tlast`. The next descriptor is accepted only after that tail fits in the same cycle.

- [x] **Step 2: Gen4 stimulus**

The 256-bit MemWr sequence places the first 1..4 payload dwords in the descriptor beat. When `gen >= 4`, MemWr64 and MemRd each post eight TLPs as one `use_burst` item. `n_pkt` defaults to 1, so Gen2/Gen3 callers and the single-beat MemRd smokes stay on the old item path.

- [x] **Step 3: Lint**

Run: `powershell -NoProfile -File scripts/lint.ps1`

Expected: `PASS: Verilator lint (controller)`.

### Task 2: MAC RX cut-through

**Files:**
- Modify: `rtl/pcie_ctrl/mac/rivet_mac_os_rx.sv`

**Interfaces:**
- Consumes: captured DLL bytes in `tlp_ram`, write index `tlp_wr_slot_q`.
- Produces: the same `dll_rx_beat` stream, with `sop` after 32 committed bytes and `eop` on the final byte. A frame that ends before that threshold still uses `frame_push`.

- [x] **Step 1: Live playback**

When `RX_CUT` is set, `rd_ph` is idle, the queue is empty, and capture is in `RX_TLP` with at least `RX_PLAY_W` words already written, start playback at `tlp_base_q`. Do not read a word capture has not committed. On end of packet, if this frame is live, set `live_len` and do not `frame_push`. `eop` is set only after that length is reached.

- [x] **Step 2: Lint Gen4**

Run: `powershell -NoProfile -File scripts/lint.ps1 -Gen 4`

Expected: pass for the Gen4 width.

### Task 3: Measure

**Files:**
- Test: `scripts/sim_questa.ps1 smoke_gen4_memwr_x4`, `smoke_gen4_cpld_x4`, `perf_rq_memwr64_gen4_x4`, `perf_rq_memrd_gen4_x4`

- [x] **Step 1: Smokes**

Both print `UVM_ERROR : 0`.

- [x] **Step 2: Sweeps**

MemWr64: 4-byte `mb_s` >= 800, 64-byte >= 5000, 4096-byte cycles <= 1032.
MemRd64: 4096-byte `mb_s` >= 7400 and `rc_tlast=8`.

- [x] **Step 3: Record printed lines**

Update `docs/perf-poster.md` and `docs/verification.md` from the log only after both sweeps are clean.

2026-11-25: `scripts/lint.ps1 -Gen 4` passed. `smoke_gen4_memwr_x4` and `smoke_gen4_cpld_x4` printed `UVM_ERROR : 0`. `perf_rq_memwr64_gen4_x4` printed 4-byte `mb_s` 888.889 (9 cycles), 64-byte 5120.000 (25 cycles), 4096-byte 7930.300 (1033 cycles, `rq_accept=1032`, `rq_stall=0`). `perf_rq_memrd_gen4_x4` printed 4096-byte `mb_s` 7447.273 (1100 cycles, `rc_tlast=8`). Both sweeps printed `UVM_ERROR : 0` and `UVM_FATAL : 0`.
