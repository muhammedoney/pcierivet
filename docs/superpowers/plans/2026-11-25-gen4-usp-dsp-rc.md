# Gen4 USP, DSP, and RC

**Closed 2026-11-25.** Phase 8 later added RC config at 16 GT/s, Hot Reset and Link Disable at Gen4, the posted forwarder, and opt-in preset search. Gen5 and the FPGA lab stayed out.

**Goal:** `MODE` USP, DSP, and RC each reach L0 at 16 GT/s on x4 and post one RQ MemWr32. Every current Gen4 EP smoke, the Gen3 DSP L0 smoke, and `smoke_gen2_x4` still pass.

**Architecture:** The Gen3 downstream master is already rate-independent, so Gen4 adds no LTSSM RTL. USP keeps the existing downstream peer (`peer_upstream=0`, `peer_gen4=1`). RC and DSP reuse `peer_upstream` at both 8 GT/s and 16 GT/s. After Gen3 L0 the peer holds speed-change TS2 until the rate pin leaves Gen3, then the electrical-idle gap restarts the slave walk for the second equalization. No second Rivet DUT.

## Link rules

Upstream is `MODE` EP or USP. Downstream is `MODE` RC or DSP.

The master in `rtl/pcie_ctrl/mac/rivet_ltssm.sv` already transmits `tx_eq_ctrl = 8'h0A` and `tx_eq_data = 8'h01` in EQ0 through EQ3, and those assigns do not depend on PIPE rate. The same exits used at Gen3 apply at 16 GT/s: one TS from EQ0 to EQ1, one TS from EQ1 to EQ2, partner phase 2 or success from EQ2 to EQ3, one TS from EQ3 to Recovery.RcvrLock.

The Gen4 L0 sequence still walks Gen1 L0, Gen2 L0, equalization into L0 at rate 2, then a second equalization into L0 at rate 3.

## Peer

`tb/uvm/agents/rivet_pipe_ltssm_peer.svh`.

- USP uses the downstream blast: 24 TS1 at `8'h0A` / preset 1, then TS2, then data. At rate 2 with `g3_speed` the rate byte is `8'h8E`. At rate 3 it is `8'h1E`.
- `peer_upstream=1` runs the Gen3 slave at rate 2 and the same slave at rate 3. EQ byte 0 until the DUT transmits `8'h0A`, one block of `8'h02`, then `8'h0A` until the DUT leaves EQ. Sixteen TS2 blocks are counted only after the DUT TS2 identifier `8'h2D`.
- A Gen4 recovery pulse while the rate pin is still 2 sets phase 5. Phase 5 sends TS2 with rate byte `8'h9E` (`8'h1E` plus the speed-change bit) and does not advance. TxElecIdle takes the inactive branch, which clears the phase and the saw flags, so the rate-3 equalization starts again at phase 0.
- A block is still 16 bytes. At 64-bit PIPE that is eight symbols per cycle, and byte 6 is still on the first beat.

## Gates

Each command printed `UVM_ERROR : 0` and `UVM_FATAL : 0` on 2026-11-25. The L0 rows also printed `Gen4 x4 L0 after equalization OK`. The MemWr rows printed `TLP RQ MemWr vseq complete`.

- `.\scripts\sim_questa.ps1 smoke_gen4_l0_usp_x4 4 2`
- `.\scripts\sim_questa.ps1 smoke_gen4_memwr_usp_x4 4 2`
- `.\scripts\sim_questa.ps1 smoke_gen4_l0_dsp_x4 4 3`
- `.\scripts\sim_questa.ps1 smoke_gen4_memwr_dsp_x4 4 3`
- `.\scripts\sim_questa.ps1 smoke_gen4_l0_rc_x4 4 1`
- `.\scripts\sim_questa.ps1 smoke_gen4_memwr_rc_x4 4 1`

Regression the same day, same zero counts: `smoke_gen4_l0_x4` and `smoke_gen4_memwr_x4` at mode 0, `smoke_gen3_l0_dsp_x4` at mode 3, and `smoke_gen2_x4`. No controller RTL changed, so the Gen3 lint top was not re-run.

## Out of scope

- Type 0/1 config cycles at 16 GT/s.
- Switch forwarding.
- Hot Reset or Disable at Gen4.
- Changing `LTSSM_TIMER_SCALE`.
- Message-bus margining, preset search, and coefficient iteration.
- Gen5.
- FPGA bitstream and lab.
