# Gen3 posted-write cut-through Implementation Plan

**Closed.** The Gen3 sweep after this plan is in [perf-poster.md](../../perf-poster.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Gen3 x4 MemWr64 sweep follow the protocol curve `payload / (payload + overhead)` instead of flattening at 64 bytes.

**Architecture:** The user port already offers 16 bytes per clock. The DLL parks each TLP in a 2-bank RAM and only starts framing after `tlast`, so the link work happens after the packet has arrived. A third packet then waits. Cut through: frame the header while later payload beats are still arriving, and do not hold the next packet for replay capture.

**Tech Stack:** SystemVerilog, Verilator lint, Questa UVM (`scripts/sim_questa.ps1 perf_rq_memwr64_gen3_x4 4 0`).

## Global Constraints

- English only in code, comments, commits, and docs.
- Default elaboration stays `GEN=2`, `PIPE_DATA_WIDTH=16`, AXI 64-bit.
- Gen3 elaboration is `GEN=3`, `PIPE_DATA_WIDTH=32`, AXI 128-bit.
- No vendor cells in `rtl/pcie_ctrl/`.
- Do not change `LTSSM_TIMER_SCALE` or the replay timer.
- Do not start Gen4. Do not change the 64-bit TX FSM (`rivet_dll_tlp_tx.sv`, `rivet_tl_rq.sv`).
- Quote MB/s only from a run that printed the number. Do not edit `docs/perf-rq-sweep.svg` or `README.md` until that run prints `UVM_ERROR : 0`.
- Commit each coherent slice on `dev`. Do not push.

## Why the curve is flat

Altera AN 456 plots `payload / (payload + overhead)` and ignores DLLPs. A 3DW header plus sequence, LCRC, and a token is about 20 bytes, so 64 bytes is about 76% and 128 bytes is about 86%. Xilinx WP350's 128-byte point near 84% is that same curve. It is smooth because the overhead is bytes on the wire, not idle cycles between packets.

Rivet's printed Gen3 x4 MemWr64 window (`rivet_g3_wr64c.log`, `user_clk_ns=4.0`, `credit_stall=0`) obeys one identity at every size:

```text
cycles = rq_accept + rq_stall + 8
```

The 8 is one idle user cycle per TLP, from starting a fresh sequence eight times. `rq_stall` is `tvalid && !tready` on RQ. It is 0 at 4/8/16 bytes, 3 at 32 bytes, then 18, 27, 31, 32, 36, 40, 40. Those stalls are why 32 bytes prints 1828.571 MB/s and 64 bytes only 1939.394 MB/s. Against the Gen3 x4 line rate of 3938 MB/s that 64-byte point is 49%, and the 128-byte point (2392.523) is 61%.

`rivet_dll_tl_pack` sets `s_tready_o = !full_q[wr_bank_q]` and raises `full` only on `tlast`. `rivet_dll_tlp_tx16` will not start until that whole TLP is valid (`start_tl` requires `tl_valid_i`), spends a seen cycle plus `ST_PREP`, then emits. It pops the bank only from:

```systemverilog
assign tl_ready_o = cap_pend_q && cap_last_q && cap_ready_i && !replay_q;
```

For a 64-byte MemWr64 the frame is 86 bytes, about 6 MAC beats, and that work starts at `tlast`. The other bank fills in 5 user beats. The extra beats are the 18 stalls (3 per TLP after the first two). A deeper RAM would hide an 8-TLP burst and report a user rate above the wire. The pipe has to start before `tlast`.

Protocol ceiling for MemWr64, overhead = 16 header + 2 sequence + 4 LCRC + 3 (STP and length) = 25 bytes, line = 3938 MB/s:

| Payload | Ceiling MB/s | Printed today |
| --- | ---: | ---: |
| 64 B | 2831 | 1939.394 |
| 128 B | 3297 | 2392.523 |
| 256 B | 3588 | 2925.714 |
| 4096 B | 3914 | 3893.536 |

4096 bytes is already on the ceiling. The 8-cycle sequence gap keeps a zero-stall 64-byte burst near 2667 MB/s (`512 * 250 / 48`), which is the pass floor. MemWr64 cannot print Altera's ~80% at 64 bytes: that figure assumes a 3DW header.

---

### Task 1: Stream the first beat into the framer

**Files:**
- Modify: `rtl/pcie_ctrl/dll/rivet_dll_tlp_tx16.sv` (`start_tl`, `tl_ready_o`, `ST_PREP`)
- Modify: `rtl/pcie_ctrl/dll/rivet_dll_tl_pack.sv` (`s_tready_o`, `m_valid_o`)
- Test: `scripts/lint.ps1 -Gen 3`

**Interfaces:**
- Consumes: TL beats already produced by `rivet_tl_rq_wide` (`tx_tdata_o[127:0]`, `tx_tkeep_o[15:0]`, `tx_tlast_o`).
- Produces: `tl_ready_o` high on every beat the framer can take, including beats before `tlast`. `m_valid_o` must not mean "whole TLP parked".

- [x] **Step 1: Accept a beat before the TLP is complete**

In `rivet_dll_tl_pack.sv`, stop gating the producer on a bank that becomes full only at `tlast`. A 16-byte beat may enter the framer on the cycle it is accepted. Keep the two word banks only as the replay image, written beside the live beat. `s_tready_o` goes low only when the framer's 16-byte hold is full, not when a second whole TLP is parked.

- [x] **Step 2: Start framing on the header beat**

In `rivet_dll_tlp_tx16.sv`, replace the `tl_seen_q` plus `ST_PREP` startup. On the first valid beat, merge the 2 sequence bytes with that beat and present a MAC beat on the next cycle. Later payload beats refill the accumulator while a MAC beat leaves. The existing `crc_merge` path still appends LCRC onto a tail of 1..12 bytes so the last beat is not a 4-byte fragment.

`tl_ready_o` must not include `cap_last_q`. Replay capture may copy the emitted bytes, and a full capture slot may pause the pipe, but capture of an earlier beat must not pause the current one.

- [x] **Step 3: Lint**

Run: `powershell -NoProfile -File scripts/lint.ps1 -Gen 3`

Expected: `PASS: Verilator lint (controller)` and `PASS: Verilator lint (Gen3 x4 width 32)`.

- [x] **Step 4: Commit**

```text
feat(dll): cut through Gen3 posted writes
```

### Task 2: Re-measure and gate the middle of the curve

**Files:**
- Test: `scripts/sim_questa.ps1 perf_rq_memwr64_gen3_x4 4 0`
- Modify after a green run only: `docs/perf-rq-sweep.svg`, `README.md`

**Interfaces:**
- Consumes: the cut-through TX from Task 1.
- Produces: printed `PERF tag=rq64_dw*` lines. Chart Y stays `672 - mb_s * 0.15`.

- [x] **Step 1: Run the sweep**

The Questa library is Gen3 today (`build/questa_regr/work_recheck`). Do not delete it before this run. Do not run a second `vsim` or `wsl.exe` beside it.

Run: `powershell -NoProfile -File scripts/sim_questa.ps1 perf_rq_memwr64_gen3_x4 4 0`

- [x] **Step 2: Check the gates**

Expected in the log:

- `UVM_ERROR : 0` and `UVM_FATAL : 0`
- `rq_stall` at `rq64_dw16`, `rq64_dw32`, and `rq64_dw64` is 0, 1, or 2 (the old values are 18, 27, 31)
- `rq64_dw16` `mb_s` is at least 2600 and at most 2831
- `rq64_dw32` `mb_s` is at least 3100 and at most 3297
- `rq64_dw1024` `mb_s` is at least 3850
- `cycles` still equals `rq_accept + rq_stall + 8`

A 64-byte point still under 2600 means the framer is still waiting for `tlast`. Do not add packer banks to hide it.

- [x] **Step 3: Update the chart from the printed lines**

Replace only the Gen3 x4 MemWr64 series in `docs/perf-rq-sweep.svg` and the same sentence in `README.md`. Leave Gen2 and the Gen3 read series alone.

- [x] **Step 4: Commit**

```text
test(perf): plot the cut-through Gen3 MemWr64 sweep
```

Gen2 MemWr64 is not re-run: Task 1 does not edit `rivet_dll_tlp_tx.sv`.
