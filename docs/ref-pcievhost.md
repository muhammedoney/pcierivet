# Reference report: pcievhost (wyvernSemi)

**Upstream:** https://github.com/wyvernSemi/pcievhost  
**Local clone (gitignored):** `third_party/ref/pcievhost`  
**Investigated:** 2026-07-28  
**Author:** Simon Southwell / wyvernSemi  

## Verdict

Professional Gen1–2 **C protocol VIP/BFM** (HDL shim + VProc/DPI), **not** synthesizable soft MAC. Strong **simulation** evidence (including Altera Cyclone V HIP over PIPE). **Not** FPGA silicon of its own. **GPL-3 — do not copy into Apache-2.0 Rivet.** Far more professional than the Gen7 educational RTL toy (~8/10 vs ~3/10 as verification/protocol assets).

## What it is

| Item | Finding |
|------|---------|
| Purpose | Virtual host/endpoint model for logic sim; user C/C++ drives rich API |
| License | **GNU GPL v3** (`LICENSE`) — copyleft; incompatible with absorbing into Apache-2.0 |
| Version | API ~1.9.4 (`src/pcie.h`) |
| Docs | `README.md` + `doc/pcieVHost.pdf` |
| Scope | PCIe **1.0a–2.0**, lanes to **16**, 8b/10b; **partial LTSSM** (power to L0) |
| Classification | VIP/BFM + C reference model — hybrid C + Verilog/SV/VHDL glue |

## Layout

```
src/           C protocol brain: pcie.c, ltssm.c, codec.c, mem.c, …
verilog/       VIP HDL: pcieVHost, Pipe×1, Serialiser, DispLink, TBs
vhdl/          VHDL mirrors + testaltpcie (HIP co-sim)
doc/           PDF user guide
```

## MAC / LTSSM / DLL quality

| Area | Paths | Completeness |
|------|-------|--------------|
| Public API | `src/pcie.h` | Mature: Mem/Cfg, Cpl, DLLP Send*, Idle/OS/TS, InitFc, ConfigurePcie |
| DLL / TL | `pcie.c`, `pcie_utils.c` | Strong Gen1–2: LCRC/ECRC, ACK/NAK+retry, FC Init/Update, SKP |
| Codec | `codec.c` | Real 8b/10b + disparity |
| LTSSM | `ltssm.c` (~688 lines) | **Partial by design:** Detect→Polling→Config→L0; Recovery without speed change; **no L0s** |
| PIPE | `pcieVHostPipex1.v` | Single-lane PIPE gearbox 8/16/32/64; multi-lane is parallel symbol ports |

Header honesty: *“IT IS NOT COMPLETE, and is meant only to be able to power up a link to L0.”*

## Verification evidence

| Evidence | Detail |
|----------|--------|
| Multi-sim | Questa, Vivado xsim, Verilator, Icarus, NVC, GHDL claimed/used |
| VIP↔VIP | `verilog/test/`, PIPE×1, serial paths |
| Vendor HIP | `vhdl/testaltpcie/` — RC VIP ↔ **Altera Cyclone V PCIe HIP** over PIPE ×1 Gen1; Detect→…→L0 PASS log |
| UVM | **Not used** — directed C/`VUserMain*` |
| FPGA silicon of VIP | **None** — sim-only; HIP PIPE “not for synthesis” |

## What Rivet can inspire (clean-room)

### Phase 1 UVM / LTSSM

1. **Observable training ladder** for scoreboard: Detect Quiet/Active → Polling Active/Config → Config width/lanenum/complete/idle → L0 (as in HIP PASS log).
2. **PIPE agent config knobs** (disable auto ACK / FC / SKP / completions on any peer BFM) so DUT DLL can be proven later.
3. **Event counters / TS observability** (“≥N TS2 on lane 0”) as scoreboard hooks.
4. **Independent peer**, not DUT-mirroring (contrast Gen7 BFM).
5. **Sim-abbreviated timeouts** vs real Detect/Polling timers.
6. **PIPE gearbox mindset:** DUT speaks PG239 PIPE; peer may be symbol-oriented — adapter at IF boundary.
7. **Separate link decode monitor** (PL/DL/TL verbosity) — pattern for UVM monitors.

### Phase 2 functional

- TLP matrix from their API: MRd/MWr 32/64, Cfg0, Cpl/CplD, Msg; bad LCRC; FC stall.
- Programmable credit/ACK rates for negative tests.
- Optional **out-of-tree** GPL VIP against Rivet PIPE (legal review); never vendor into `rtl/` or `tb/uvm`.

## What Rivet must not copy

| Do not | Why |
|--------|-----|
| Any `src/*.c` / codec / ltssm into Rivet | **GPL-3** vs Apache-2.0 |
| Treat as synthesizable MAC source | It isn’t |
| Gen3+ / 128b/130b / EQ | Out of repo scope |
| PIPE×1-only as sole model | Rivet needs Gen2 ×1/×2/×4 + full PG239 |

## Confidence

**~8/10** as Gen1–2 verification/protocol reference (mature API, real coding, HIP co-sim). Deduct for incomplete LTSSM, no UVM, no own FPGA silicon. Correct mental model: **sim-proven VIP**, not soft-IP silicon.
