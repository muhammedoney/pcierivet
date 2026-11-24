# Gen3 16-byte datapath Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise Gen3 x4 user throughput above Gen2 x4 by moving 16 bytes per clock, and make the Gen3 read sweep finish clean.

**Architecture:** Gen2 keeps 64-bit AXI-ST and 8-byte DLL beats. Gen3 uses 128-bit AXI-ST, a 128-bit DLL/MAC beat, and a length-prefixed TLP in all four symbol times. The peer uses that same frame so payload bytes are not mistaken for tokens.

**Tech Stack:** SystemVerilog, Verilator lint, Questa UVM (`scripts/sim_questa.ps1`).

## Global Constraints

- English only in code, comments, commits, and docs.
- Default elaboration stays `GEN=2`, `PIPE_DATA_WIDTH=16`, AXI 64-bit.
- Gen3 elaboration is `GEN=3`, `PIPE_DATA_WIDTH=32`, AXI 128-bit.
- No vendor cells in `rtl/pcie_ctrl/`.
- Do not change `LTSSM_TIMER_SCALE`.
- Do not start Gen4.
- Quote MB/s only from a run that printed the number.
- Commit each coherent slice. Do not push.

---

### Task 1: Widen the DLL/MAC beat

**Files:**
- Modify: `rtl/pcie_ctrl/rivet_pkg.sv` (`rivet_dll_mac_tx_beat_t`, `rivet_dll_mac_rx_beat_t`)
- Modify: `rtl/pcie_ctrl/mac/rivet_mac_os_tx.sv` (`keep_nbytes`, `dllp_ok`)
- Test: `scripts/lint.ps1` Gen2

**Interfaces:**
- Consumes: existing 8-byte beats (`keep[7:0] == 8'hFF`, high data zero).
- Produces: `data[127:0]`, `keep[15:0]`. Gen2 assignments zero-extend.

- [ ] **Step 1:** Change both beat structs to 128-bit `data` and 16-bit `keep`.
- [ ] **Step 2:** Count keep nibbles across 16 bits. A DLLP is still legal only when `keep[7:0] == 8'hFF` and `keep[15:8] == 8'h00`.
- [ ] **Step 3:** Run `scripts/lint.ps1`. Expected: `PASS: Verilator lint (controller)`.
- [ ] **Step 4:** Commit `refactor(dll): widen the MAC beat to 16 bytes`.

### Task 2: Gen3 TX uses four symbol times and a length

**Files:**
- Modify: `rtl/pcie_ctrl/mac/rivet_mac_os_tx.sv` (TLP emit, `take_b`, `tlp_em_done`)
- Test: `scripts/lint.ps1 -Gen 3`

**Interfaces:**
- Consumes: Task 1 beat. Gen3 x4 `sym_step` is 16.
- Produces: on a Gen3 data block, symbol order is STP, length low, length high, then DLL bytes. No END byte. Gen2 STP/END K path is unchanged.

- [ ] **Step 1:** On the first Gen3 beat, consume `sym_step - 3` payload bytes (13 at x4). Later beats consume `sym_step` bytes. Add shift cases for 5, 6, 8, 12, 13, 15, and 16.
- [ ] **Step 2:** Done when `tlp_pos + sym_step` reaches `tlp_len + 3`.
- [ ] **Step 3:** Lint Gen2 and Gen3. Both PASS lines required.
- [ ] **Step 4:** Commit `feat(mac): send a Gen3 TLP in all four symbol times`.

### Task 3: Gen3 RX parses four symbol times

**Files:**
- Modify: `rtl/pcie_ctrl/mac/rivet_mac_os_rx.sv` (the `s >= 2` gate and `gf_st_q`)
- Test: existing `smoke_gen3_memwr_x4` and `smoke_gen3_cpld_x4`

**Interfaces:**
- Consumes: the Task 2 frame.
- Produces: the same 8-byte DLL beat stream the gearbox already accepts. Length bytes are stripped. The byte after the body is a synthetic END for that gearbox only.

- [ ] **Step 1:** Walk symbol times 0..3 while `rate == GEN3`.
- [ ] **Step 2:** Delete `work`, run `smoke_gen3_memwr_x4` and `smoke_gen3_cpld_x4`. Expected: `UVM_ERROR : 0` and `UVM_FATAL : 0` in both logs.
- [ ] **Step 3:** Commit `feat(mac): parse a Gen3 TLP across four symbol times`.

### Task 4: Peer matches the length frame

**Files:**
- Modify: `tb/uvm/agents/rivet_pipe_ltssm_peer.svh`
- Test: `perf_rq_memrd_gen3_x4` after Task 5, plus `smoke_gen3_cpld_x4` here

**Interfaces:**
- Consumes: DUT TX in the Task 2 layout.
- Produces: peer TX in the same layout, including CplD. Observe state advances on the length, not on FD/FE/FB.

- [ ] **Step 1:** Send STP, length, DLL bytes in symbol times 0..3. Remove the `ns = 2` cap for Gen3 TLPs.
- [ ] **Step 2:** On observe, arm the 23-bit LFSR on the first data header and count `length` bytes before calling a frame done. Do not set `is_k` from a payload byte.
- [ ] **Step 3:** Re-run `smoke_gen3_cpld_x4`. Expected: `UVM_ERROR : 0`.
- [ ] **Step 4:** Commit `fix(tb): match Gen3 length framing in the peer`.

### Task 5: 128-bit user port for Gen3

**Files:**
- Modify: `rtl/pcie_ctrl/tl/rivet_tl_rq.sv`, `rtl/pcie_ctrl/tl/rivet_tl_rc.sv`, `rtl/pcie_ctrl/dll/rivet_dll_tlp_tx.sv`, `rtl/pcie_ctrl/dll/rivet_dll_tlp_rx.sv`
- Modify: `tb/uvm/rivet_tb_top.sv` and the RQ/RC drivers used by the perf sequences
- Test: `perf_rq_memwr64_gen3_x4`, `perf_rq_memrd_gen3_x4`, `perf_rq_memwr64_gen2_x4`

**Interfaces:**
- Consumes: Gen3 AXI 128-bit beats, two dwords of keep.
- Produces: 16-byte DLL beats (`keep == 16'hFFFF`) at Gen3. Gen2 still produces 8-byte beats.

- [ ] **Step 1:** Add a data-width parameter. Gen2 elaborations pass 64. Gen3 testbench passes 128.
- [ ] **Step 2:** A Gen3 posted write streams 16 payload bytes per accepted user beat after the header beat.
- [ ] **Step 3:** Delete `work`. Run the three perf tests above. Gen3 logs must show `UVM_ERROR : 0` and `UVM_FATAL : 0`. The 4096-byte Gen3 MemWr64 `mb_s` must be greater than 1979.700.
- [ ] **Step 4:** Commit `feat(tl): stream 16 bytes per cycle at Gen3`.

### Task 6: Plot the new points

**Files:**
- Modify: `docs/perf-rq-sweep.svg`, `README.md`

- [ ] **Step 1:** Copy `mb_s` only from the new PERF lines. Add Gen3 x4 MemWr64 and Gen3 x4 read. Keep the 500 MB/s grid and the 4000 MB/s axis.
- [ ] **Step 2:** Commit `test(perf): plot the 16-byte Gen3 sweeps`.
