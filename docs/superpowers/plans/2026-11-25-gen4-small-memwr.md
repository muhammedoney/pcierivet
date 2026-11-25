# Gen4 small MemWr packing Implementation Plan

**Closed 2026-11-25.** This packing is in the Gen4 requester. Phase 8 did not change it.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise Gen4 x4 MemWr64 throughput at 32, 64, 128, and 256 bytes by removing the half-empty beat at the end of each posted write.

**Architecture:** A MemWr64 header is 16 bytes. Those payload sizes are multiples of 32 bytes, so each TLP ends 16 bytes into a 32-byte user beat. The Gen4 burst places the next descriptor in that free half and marks it with `tuser[RIVET_RQ_TUSER_NEXT_SOP]`. `rivet_tl_rq_g4` finishes the open TLP at byte 16, then pushes the new header into the residue. One-TLP sequences and payloads that are not a multiple of 8 dwords stay on the aligned path.

**Tech Stack:** SystemVerilog, Verilator lint (`scripts/lint.ps1 -Gen 4`), Questa UVM (`scripts/sim_questa.ps1`).

## Global Constraints

- English only in code, comments, commits, and docs.
- Gen2 stays `PIPE_DATA_WIDTH=16`. Gen3 stays 32. Gen4 is 64.
- The RQ user port stays 256 bits. Do not change `LTSSM_TIMER_SCALE`.
- `rq_tlast` stays one per TLP. The perf sequence still requires 8.
- Quote MB/s only from a run that printed the number and `UVM_ERROR : 0`.

---

### Task 1: Split beat

**Files:**
- Modify: `rtl/pcie_ctrl/rivet_pkg.sv` (`RIVET_RQ_TUSER_NEXT_SOP = 80`)
- Modify: `rtl/pcie_ctrl/tl/rivet_tl_rq_g4.sv`
- Modify: `tb/uvm/seq/rivet_axi_st_item.svh`
- Modify: `tb/uvm/agents/rivet_axi_st_driver.svh`
- Modify: `tb/uvm/seq/rivet_axi_rq_memwr_seq.svh`

**Interfaces:**
- Consumes: a 256-bit beat with `tlast` and `tuser[80]`. Bytes 0..15 end the open TLP. Bytes 16..31 are the next PG213 descriptor.
- Produces: the same 32-byte DLL beats. The 16-byte tail leaves with `tlast` before the new header is pushed.

- [x] **Step 1: Accept the split only when the tail can leave this cycle**

`s_axis_rq_tready` in `ST_PAY` requires `slot_free` and `res_n_q <= 16` when the beat is a split. Other beats keep the current ready rule.

- [x] **Step 2: Pack the burst**

When `n_pkt > 1`, the bus is 256 bits, and `payload_dw` is a multiple of 8, `rivet_axi_rq_memwr_seq` emits one byte stream of descriptor-plus-payload and sets `burst_user_q` per beat. The driver drives that queue. `n_pkt == 1` stays on the old loop.

- [x] **Step 3: Lint**

Run: `powershell -NoProfile -File scripts/lint.ps1 -Gen 4`

Expected: `PASS: Verilator lint (Gen4 x4 width 64)`.

### Task 2: Measure

**Files:**
- Test: `scripts/sim_questa.ps1 smoke_gen4_memwr_x4` and `perf_rq_memwr64_gen4_x4`

- [x] **Step 1: Smoke**

`smoke_gen4_memwr_x4` prints `UVM_ERROR : 0`.

- [x] **Step 2: Sweep gates**

Eight TLPs, `rq_tlast=8`, `rq_stall=0`. User cycles at most 13, 21, 37, and 69 for 32, 64, 128, and 256 bytes. 4-byte `mb_s` stays at least 800. 4096-byte cycles stay at most 1029.

- [x] **Step 3: Record printed lines**

Update `docs/perf-poster.md`, `docs/perf-rq-sweep.svg`, `docs/verification.md`, and `README.md` from the log only after the sweep is clean.

2026-11-25: `scripts/lint.ps1 -Gen 4` passed. `smoke_gen4_memwr_x4` printed `UVM_ERROR : 0`. `perf_rq_memwr64_gen4_x4` printed 32-byte `mb_s` 4923.077 (13 cycles), 64-byte 6095.238 (21 cycles), 128-byte 6918.919 (37 cycles), 256-byte 7420.290 (69 cycles), and 4096-byte 7961.127 (1029 cycles, `rq_accept=1028`). Every size printed `rq_tlast=8`, `rq_stall=0`. 4-byte stayed 888.889. `UVM_ERROR : 0`, `UVM_FATAL : 0`.
