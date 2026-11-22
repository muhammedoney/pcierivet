# Posted-write cut-through implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Raise Gen2 x4 posted-write throughput from the 1000 MB/s user-port ceiling toward the 2000 MB/s symbol rate.

**Architecture:** Fold the LCRC while the payload beats leave `rivet_dll_tlp_tx`, and start STP in `rivet_mac_os_tx` once 16 bytes are buffered so the wire runs during that same beat stream. The user port in simulation runs at 4 ns (250 MHz), matching the FPGA PHY user clock, so 64 bits is 4 Gbit/s per lane on x4.

**Tech Stack:** SystemVerilog, Questa UVM, Verilator lint.

## Global Constraints

- English only. No vendor cells in `rtl/pcie_ctrl/`.
- Do not widen AXI-ST past 64 bits.
- Do not change the RX slot (160 bytes) or the replay timer formula.
- Quote only `mb_s` values a Questa run prints. Update the README graph only after that run.
- Gen2, lanes 1/2/4. SKP stays between packets.

---

### Task 1: Stream the LCRC

**Files:**
- Modify: `rtl/pcie_ctrl/dll/rivet_dll_tlp_tx.sv`

New packets emit `crc_sh_q` beats during `ST_CRC`. The last payload beat is not EOP. `ST_LCRC` sends the 4 LCRC bytes with EOP and pushes `insert_lcrc(frame_q)` into the replay buffer in that same cycle. Replay still enters `ST_EMIT` with a finished image. `frame_q` is not shifted, so the inserted LCRC lands at the saved index.

### Task 2: Cut-through MAC

**Files:**
- Modify: `rtl/pcie_ctrl/mac/rivet_mac_os_tx.sv`

After the second beat of a multi-beat TLP, `tlp_flow` emits STP on the next cycle while `ST_TLP_COL` keeps accepting beats. END is allowed only after the EOP beat has been accepted (`tlp_closed`). A one-beat or two-beat TLP keeps the old collect-then-emit path.

### Task 3: Measure at 250 MHz

**Files:**
- Modify: `tb/uvm/rivet_tb_top.sv` (`forever #2 user_clk`)
- Modify: `tb/uvm/env/rivet_perf_mon.svh` (`USER_CLK_NS = 4.0`, `mb_s = bytes * 250 / cycles`)

### Task 4: Verify

Run `scripts/lint.ps1`, then `scripts/sim_questa.ps1 smoke_gen2_x1`, then `scripts/sim_questa.ps1 perf_rq_sweep_gen2_x4 4`. A 4096-byte point near 1990 MB/s with `rq_stall` near 0 is the pass. Update README and the poster only from the printed lines.
