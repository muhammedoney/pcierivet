# Gen3 USP, DSP, and RC

**Goal:** `MODE` USP, DSP, and RC each reach L0 at 8 GT/s on x4 and post one RQ MemWr32. Every current Gen2 smoke and every current Gen3 EP smoke still passes.

**Architecture:** USP is the same upstream equalization slave as EP. RC and DSP share one downstream master. The master transmits the compressed handshake the UVM peer already uses against EP: EQ byte `8'h0A` (phase 2 plus success) and preset `8'h01`. The peer grows an upstream-slave mode for RC and DSP. No second Rivet DUT. Gen4 multi-mode is a follow-on plan.

## Link rules

Upstream is `MODE` EP or USP. Downstream is `MODE` RC or DSP (`IS_DOWNSTREAM` in `rivet_ltssm`).

Upstream slave exits are unchanged: EQ0 on rate-id bit 3, EQ1 on phase 2, EQ2 on the success bit, EQ3 after one ordered set.

Downstream master, in `rtl/pcie_ctrl/mac/rivet_ltssm.sv`:

- EQ0, EQ1, EQ2, and EQ3 transmit `tx_eq_ctrl = 8'h0A` and `tx_eq_data = 8'h01`.
- EQ0 goes to EQ1 after one TS. EQ1 goes to EQ2 after one TS.
- EQ2 goes to EQ3 when the partner echoes phase 2 or the success bit.
- EQ3 goes to Recovery.RcvrLock after one TS.

## Peer

`peer_upstream` (default 0) on `tb/uvm/agents/rivet_pipe_ltssm_peer.svh`.

- `peer_upstream=0` keeps the downstream blast. EP and USP tests use this.
- `peer_upstream=1` keeps Link# `8'h00` and Lane# 0..n-1 through 8b/10b Configuration. Those are the numbers a downstream DUT assigns, so the wire image is the echo. At 8 GT/s it sends EQ byte 0 until the DUT transmits `8'h0A`, one block of `8'h02`, then `8'h0A` until the DUT leaves EQ. It keeps TS2 until the DUT itself sends TS2 (Recovery.RcvrCfg), for 16 blocks, then logical idle. Recovery.RcvrLock consumes an early TS2 burst, so the 16 TS2 blocks are counted only after the DUT TS2 identifier.

## Gates

Each command printed `UVM_ERROR : 0` and `UVM_FATAL : 0` on 2026-11-25.

- `.\scripts\sim_questa.ps1 smoke_gen3_l0_usp_x4 4 2`
- `.\scripts\sim_questa.ps1 smoke_gen3_memwr_usp_x4 4 2`
- `.\scripts\sim_questa.ps1 smoke_gen3_l0_dsp_x4 4 3`
- `.\scripts\sim_questa.ps1 smoke_gen3_memwr_dsp_x4 4 3`
- `.\scripts\sim_questa.ps1 smoke_gen3_l0_rc_x4 4 1`
- `.\scripts\sim_questa.ps1 smoke_gen3_memwr_rc_x4 4 1`

Regression the same day: `smoke_gen3_l0_x4` and `smoke_gen3_memwr_x4` at mode 0, and `smoke_gen2_x4`. Verilator lint of the controller and the Gen3 x4 lint top passed.

## Out of scope

- Gen4 for USP, DSP, or RC.
- Type 0/1 config cycles at 8 GT/s.
- Switch forwarding.
- Hot Reset or Disable at Gen3.
- Changing `LTSSM_TIMER_SCALE`.
- FPGA bitstream and lab.
