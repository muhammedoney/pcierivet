# Rivet MAC — implementation follow-guide

**Audience:** anyone implementing or reviewing the Media Access Control inside `rivet_pcie_ctrl`.  
**Active target:** `MODE=EP`, **Gen2**, `LANES` ∈ {1,2,4}, PIPE to PG239-aligned `rivet_pipe_if`.  
**Do not** implement Gen3/4 protocol behavior while Gen2 is active ([roadmap.md](roadmap.md), [gen-evolution.md](gen-evolution.md)).

This is the checklist doc for MAC work. PIPE signal meaning: [pipe-notes.md](pipe-notes.md). User IF: [pg213-interface.md](pg213-interface.md).

---

## 1. Where MAC sits

```text
  AXI-ST + cfg_mgmt (PG213-style)     ← user boundary
           │
     TL (Transaction) + Config Space
           │
     DLL (Data Link) — DLLP, ACK/NAK, LCRC, FC
           │
     ★ MAC ★  — LTSSM, ordered sets, lane/rate/power, PIPE adapter
           │
         PIPE                             ← PHY boundary
           │
     rivet_pcie_phy_* → PG239 (PCS+PMA: 8b/10b, elastic buffer, SerDes)
```

| Owns | Does **not** own (Gen2 / Original PIPE) |
|------|----------------------------------------|
| LTSSM + timers (sim-abbreviated OK) | 8b/10b encode/decode |
| TS1/TS2 / SKP / EIOS / FTS / … generation & detect | Elastic buffer |
| **Scrambler / descrambler** (see [§6.1](#61-scrambling-mac-owned-not-yet-implemented)) | Serial / PMA |
| **STP/SDP/END framing + byte striping** across Lanes | AXI-ST user ports (TL) |
| PIPE command/status driving | Message Bus / LPC PIPE |
| DLL ↔ MAC framing + control sideband | LCRC / sequence numbers (DLL) |
| `cfg_ltssm_state` / link status toward user | |

Scrambling and framing are **Physical Layer** duties, so in Rivet they are MAC
work even though they carry DLL payload. Base spec §4.2.3 puts scrambling
"prior to the 8b/10b encoding" on TX and descrambling "after 8b/10b decoding" on
RX; since PG239 owns 8b/10b, whatever we place on `txdata` must already be
scrambled and whatever arrives on `rxdata` is still scrambled.

---

## 2. Locked LTSSM encodings (PG213 `cfg_ltssm_state[5:0]`)

Use these **exact** values in `rivet_pkg` / `rivet_ltssm` so status ports and UVM match UltraScale+ IP conventions:

| Code | State | Gen2 Phase 1 |
|------|-------|--------------|
| `6'h00` | Detect.Quiet | **Yes** |
| `6'h01` | Detect.Active | **Yes** |
| `6'h02` | Polling.Active | **Yes** |
| `6'h03` | Polling.Compliance | Stub / later |
| `6'h04` | Polling.Configuration | **Yes** |
| `6'h05` | Configuration.Linkwidth.Start | **Yes** |
| `6'h06` | Configuration.Linkwidth.Accept | **Yes** |
| `6'h07` | Configuration.Lanenum.Accept | **Yes** |
| `6'h08` | Configuration.Lanenum.Wait | **Yes** |
| `6'h09` | Configuration.Complete | **Yes** |
| `6'h0A` | Configuration.Idle | **Yes** |
| `6'h0B` | Recovery.RcvrLock | Minimal stub after L0 |
| `6'h0C` | Recovery.Speed | Later (Gen1↔Gen2 change) |
| `6'h0D` | Recovery.RcvrCfg | Minimal stub |
| `6'h0E` | Recovery.Idle | Minimal stub |
| `6'h10` | **L0** | **Yes — success gate** |
| `6'h11`–`6'h16` | (reserved / other in PG213 tables) | Ignore until needed |
| `6'h17` | L1.Entry | Later |
| `6'h18` | L1.Idle | Later |
| `6'h20` | Disabled | Later |
| `6'h21`–`6'h26` | Loopback.* | Later |
| `6'h27` | Hot_Reset | Later |
| `6'h28`–`6'h2B` | Recovery.Equalization.* | **Gen3+ only** |

Canonical type: `typedef enum logic [5:0] { ... } rivet_ltssm_state_e;`

Primary EP training ladder for smoke:

```text
Detect.Quiet → Detect.Active → Polling.Active → Polling.Configuration
  → Configuration.Linkwidth.* → Lanenum.* → Complete → Idle → L0
```

Reference behavior (do **not** copy code): [ref-pcievhost.md](ref-pcievhost.md) (GPL-3 VIP). Structure names only: [ref-pci-express-gen7.md](ref-pci-express-gen7.md).

---

## 3. Module split (target RTL)

Controller layout:

```text
rtl/pcie_ctrl/
  rivet_pkg.sv / rivet_pcie_ctrl.sv   # shared pkg + top
  mac/   # this layer
  dll/   # Data Link
  tl/    # Transaction + config
```

Under `rtl/pcie_ctrl/mac/` (names locked for follow-on slices):

| Module / package | Responsibility |
|------------------|----------------|
| `rivet_ltssm` | State machine, timers, power/rate requests, link_up / cfg_ltssm_state |
| `rivet_mac_os_tx` | Ordered-set / TS encoder → symbol stream to PIPE adapter |
| `rivet_mac_os_rx` | Symbol stream → OS/TS detect, lane deskew hooks, error flags |
| `rivet_mac_pipe_adapter` | Pack/unpack `LANES` × `PIPE_DATA_WIDTH`; drive `rivet_pipe_if.mac` |
| `rivet_dll_mac_if` (pkg or SV IF) | DLL ↔ MAC streams + **control sideband** (may live under `dll/`) |
| (M2) `rivet_mac_scrambler` / `rivet_mac_descrambler` | Per-Lane LFSR, K/TS bypass ([§6.1](#61-scrambling-mac-owned-not-yet-implemented)) |
| (M2) `rivet_mac_framer` / `rivet_mac_deframer` | STP/SDP/END/EDB + byte striping across Lanes |
| (M2) `rivet_mac_skp` | SKP insertion policy in L0 |

Keep Gen3+ block-framing and EQ **out** of Gen2 bodies; adapter may have dead ports.

---

## 4. DLL ↔ MAC contract (AXI-ST alone is **not** enough)

AXI-ST is for user TLPs at the **user** boundary. Between DLL and MAC use:

### 4.1 Payload streams (AXI-ST-*like* OK)

| Path | Content |
|------|---------|
| DLL_TX → MAC_TX | Framed DLLP/TLP bytes after LCRC (or pre-LCRC — pick one and document); SOP/EOP; type tag |
| MAC_RX → DLL_RX | Recovered DLLP/TLP bytes; SOP/EOP; error/abort flags |

### 4.2 Control sideband (required)

| Direction | Examples |
|-----------|----------|
| LTSSM → DLL | `link_up`, negotiated width/speed, “accept DLLP/TLP only in L0”, replay freeze |
| DLL → LTSSM | Replay timer expiry hint, unexpected NAK storm (policy later) |
| MAC_OS ↔ LTSSM | “Send TS1/TS2 with fields…”, “Saw N matching TS2 on lane0”, EIOS/FTS requests |
| MAC_RX → LTSSM | Deskew done, 8b/10b decode errors via RxStatus, loss of RxValid |
| FC / ACK | Visibility events; MAC may only forward — DLL owns credit math |

Define structs/enums in `rivet_pkg` or `rivet_dll_pkg` before wiring RTL.

---

## 5. PIPE duties checklist (Gen2)

See [pipe-notes.md](pipe-notes.md) for detail. MAC must:

1. **Detect:** P1 (or P2) + `txelecidle` + `txdetectrx`; wait `phystatus` + `rxstatus` present/absent.  
2. **Training:** Drive TS1/TS2 (and related OS) on `txdata`/`txdatak`; parse RX.  
3. **Idle:** Legal PowerDown × Detect × ElecIdle table only.  
4. **L0:** `powerdown=P0`, data path open to DLL; periodic **SKP** on TX.  
5. **Assist (PG239):** `as_mac_in_detect`, `as_cdr_hold_req` as LTSSM requires.  
6. **Leave idle:** Gen3 EQ ports, Message Bus, SerDes EB, `txdata_valid` block framing.

Rate: Gen2. Width: 16 bits/lane. PCLK: 250 MHz class (TB clock).

---

## 6. Ordered sets / symbols (Gen2 EP minimum)

Implement / scoreboard at least:

| Set | Role |
|-----|------|
| TS1 / TS2 | Polling + Configuration (+ Recovery later) |
| SKP | Clock compensation; EB in PHY |
| EIOS | Enter electrical idle / L0s/L1 entry sequences |
| FTS | Exit L0s (when L0s enabled) |
| COM / IDL characters | As required by OS definitions |

Field handling for EP: Link Number, Lane Number, N_FTS, Data Rate ID, Training Control bits — start minimal (enough for ×1 then ×2/×4 width negotiation).

### 6.1 Scrambling (MAC-owned)

Implemented in `rivet_mac_scrambler` / `rivet_mac_descrambler` (wired in `rivet_mac`).
Base spec §4.2.3 rules:

| Rule | Value |
|------|-------|
| Polynomial | `G(X) = X^16 + X^5 + X^4 + X^3 + 1` |
| Seed | `FFFFh`; TX LFSR re-initialises immediately after COM leaves it, RX LFSR every time a COM enters it on **any** Lane |
| Advance | 8 serial shifts per Symbol, **except SKP** (SKP does not advance it) |
| Bypass | All K codes; D Symbols inside TS1/TS2; Compliance and Modified Compliance patterns |
| Multi-lane | One LFSR per Lane |
| Enable | Always on from Detect; Disable Scrambling training-control bit not yet honored |

Logical Idle is scrambled `00h`. Configuration.Idle advances on eight consecutive
descrambled Idle Symbol Times. The LTSSM smoke peer scrambles its Idle stream so
the loop stays honest against a real Root Port.

### 6.2 Physical Layer gaps to close before/with DLL

| Item | State | Why the DLL needs it |
|------|-------|----------------------|
| Scrambler / descrambler | Present (M2 start) | §6.1; Config.Idle + every TLP/DLLP byte |
| STP / SDP / END / EDB framing | Missing | The DLL hands us sequence number + LCRC; delimiting the packet on the wire is ours |
| Byte striping / un-striping | Missing | ×2/×4 need STP on the right Lane and bytes spread round-robin (§4.2.2) |
| SKP scheduling in L0 (`rivet_mac_skp`) | Missing | SKP OS every 1180–1538 Symbol Times, never inside a packet; the PHY elastic buffer depends on it |
| Real lane-to-lane deskew | Hook only | Striped data cannot be reassembled without it |
| Descrambled-`00h` Idle detect | Done | `rivet_mac_os_rx` counts descrambled `00h` |

`rivet_mac_os_tx` / `rivet_mac_os_rx` already carry the DLL ports, but they are
tied off (`dll_tx_ready_o = 1'b0`, `dll_rx_valid_o = 1'b0`) — there is no packet
datapath through the MAC yet, only the training path.

---

## 7. Lane matrix

| `LANES` | Priority |
|---------|----------|
| 1 | First LTSSM + UVM proof |
| 2 | Same RTL; width negotiation + packing |
| 4 | Same; deskew / multi-lane TS checks |

All three are first-class parameters; do not hard-code ×1 in MAC datapath.

### 7.1 Negotiated width vs port width

`LANES` is **our port width**, not the width of the link partner. Two cases that
look alike behave very differently today:

| Case | Status |
|------|--------|
| Partner is **wider** than us (×16 Root Port, `LANES=4` Endpoint) | **Works.** All four of our Lanes detect a Receiver and get numbered; narrowing 16 → 4 is the Downstream Port's job. Covered by the ×4 smoke. |
| No Receiver on some Lanes at all | **Works.** Detect.Active's two-pass rule narrows `lane_en` to the Lanes that detected, and training continues on that subset. |
| Partner **configures fewer Lanes than we have** (×4 Endpoint, Root Port offers ×2) | **Not yet.** The LTSSM climbs to Configuration.Linkwidth.Accept, times out after 24 ms and drops to Detect, forever. |

The third case fails in two specific places, both in `rivet_ltssm`:

1. `Configuration.Linkwidth.Start` clears `link_pad` for **every** Lane in
   `lane_en` instead of narrowing `lane_en` to the Lanes that actually received a
   non-PAD Link number. Lanes the partner left out must keep transmitting PAD.
2. `Configuration.Linkwidth.Accept` waits for `ts1_lane_all_i`, so it requires a
   non-PAD Lane number on *every* enabled Lane. The Lanes the partner left out
   stay PAD, so the condition can never be satisfied.

Reproduce with the smoke peer, which can be told to configure fewer Lanes than
the DUT has:

```text
# passes  — partner configures all four Lanes
verilator ... -DRIVET_SMOKE_LANES=4 -DRIVET_SMOKE_PEER_LANES=4
# retrain loop — partner offers only two of our four Lanes
verilator ... -DRIVET_SMOKE_LANES=4 -DRIVET_SMOKE_PEER_LANES=2
```

Closing it is the M3 slice and needs: per-Lane shape flags out of `os_rx`
(the per-Lane counters already exist internally, only the reductions are
exported), per-Lane `tx_link_pad` / `tx_lane_pad` in `os_tx`, and `lane_en`
narrowing in the two Linkwidth substates. `negotiated_width` already follows
`lane_en`, so status reporting needs no change.

---

## 8. Gen2 now vs Gen3/4 later (MAC-only)

| Area | Gen2 now | Later |
|------|----------|-------|
| Encoding | Logical 8b/10b OS (PHY encodes) | 128b/130b OS / sync header |
| LTSSM | Detect→…→L0 (+ light Recovery) | Recovery.Equalization `0x28..0x2B` |
| PIPE width | 16 | 32 then 64 |
| EQ | Tie off PG239 EQ | Drive `txeq_*` / `rxeq_*` |
| Rate change | Fixed Gen2 | Recovery.Speed + PhyStatus |

Details: [gen-evolution.md](gen-evolution.md).

---

## 9. Status toward user / TB

Expose (dedicated ports or internal → top):

- `cfg_ltssm_state[5:0]` — table in §2  
- `link_up` (already stubbed) — assert in L0 when policy satisfied  
- Later: `cfg_negotiated_width`, `cfg_current_speed`, `cfg_phy_link_down`, etc. ([pg213-interface.md](pg213-interface.md))

UVM must use an **independent** PIPE peer (not a BFM that peeks DUT LTSSM).

---

## 10. Implementation milestones (follow in order)

### M0 — Types & IF (done skeleton)

- [x] `rivet_ltssm_state_e` with PG213 values (`rivet_pkg`)
- [x] `rivet_dll_mac_*` structs + `rivet_dll_mac_if`
- [x] `rivet_mac` / LTSSM / OS TX/RX / PIPE adapter stubs wired in `rivet_pcie_ctrl`
- [x] Lint green (`scripts/lint.ps1`) when Verilator available

### M1 — Gen2 ×1 Detect → … → L0 (RTL done)

Port/state/timer worksheet: [ltssm.xlsx](ltssm.xlsx) (regenerate with
`python scripts/gen_ltssm_xlsx.py`).

- [x] LTSSM inputs from PHY: `phystatus`, `rxelecidle`, `rxvalid`, `rx_detected` (fan out of pipe adapter)
- [x] `rivet_mac_timer` shared timeout counter, `LTSSM_TIMER_SCALE` shrinks 12 / 24 / 48 / 2 ms for sim
- [x] Per-lane TS detect + consecutive counters (8 RX) and TX counters (1024 TS1, 16 TS2)
- [x] `rate` = 2.5 GT/s during training, Gen2 capability advertised in the TS rate ID
- [x] `link_up` asserted in Configuration.Idle, not on L0 entry
- [x] OS TX field control: Link#/Lane#/PAD, N_FTS, rate ID, training control, lane mask
- [x] Gate: Verilator smoke reaches L0 for ×1/×2/×4 (`scripts/sim_ltssm_smoke.ps1`)
- [ ] UVM sequence: peer responds with TS; scoreboard state path (Questa not installed)

Known simplifications, all revisited in M2–M4:

| Area | Simplification |
|------|----------------|
| Scrambling | Not implemented at all — see [§6.1](#61-scrambling-mac-owned-not-yet-implemented); training is scramble-exempt, so this only shows up at Configuration.Idle against a real partner |
| Idle detection | Counts consecutive non-K Symbol Times rather than descrambled `00h`, which is what lets the unscrambled smoke agree with itself |
| Lane-to-lane deskew | `deskew_done` = every enabled Lane saw a TS in the same cycle; no per-lane skew correction |
| Lane numbers | Sequential 0..n-1, no Lane reversal; Downstream Port assigns them when `MODE=RC/DSP` |
| Dual-EP BFM | Fixed: board is EP+RC; Downstream offers Link# at Linkwidth.Start |
| Recovery | Only `Recovery.RcvrLock` exists, and only so timeouts and RX errors cannot dead-end |
| EIOS | 4 symbols (2.5 GT/s form); the 8-symbol 5.0 GT/s form lands with Recovery.Speed |
| Multi-lane exits | Configuration substates use "all enabled Lanes" where the spec allows per-Lane "any", so a partner that configures fewer Lanes than our port width cannot train — see [§7.1](#71-negotiated-width-vs-port-width) |

### M2 — Physical Layer datapath, then DLL stubs at MAC boundary

Prerequisites from [§6.2](#62-physical-layer-gaps-to-close-beforewith-dll):

- [x] `rivet_mac_scrambler` / `rivet_mac_descrambler` (per Lane, COM-seeded, SKP does not advance, K and TS bypass)
- [x] Scramble Logical Idle, and switch Idle detection to descrambled `00h`
- [x] Extend the smoke peer to scramble Idle so the loop stays honest
- [ ] STP/SDP/END/EDB framing insert + strip
- [ ] Byte striping / un-striping and real deskew for ×2/×4
- [ ] `rivet_mac_skp` — SKP OS every 1180–1538 Symbol Times, never mid-packet
- [ ] Untie `dll_tx_ready_o` / `dll_rx_valid_o`; pass-through / idle DLLP hooks in L0
- [ ] Keep ×2/×4 smokes elaborating after framing lands

### M3 — Lane grow

- [ ] Linkwidth / lanenum for ×2 then ×4  
- [ ] Multi-lane packing tests

### M4 — Recovery / errors (still Gen2)

- [ ] RxValid loss / RxStatus overflow → Recovery → L0  
- [ ] Hot reset / Disabled as needed

### Later phases

- Gen2 TLP/DLL complete (Phase 2)  
- VCU118 + real PG239 (Phase 2 HW)  
- Gen3 EQ / 128b/130b (Phase 3)

---

## 11. Verification gates

Per [verification.md](verification.md) and workspace gates:

1. Verilator lint on touched RTL — `scripts/lint_lanes.ps1` covers ×1/×2/×4.  
2. `scripts/sim_ltssm_smoke.ps1 <lanes>` must reach L0 (hand-written PIPE peer, no UVM).  
3. Questa UVM smoke when installed; else note “UVM deferred — Questa not installed”.  
4. Vivado BFM optional — never replaces UVM.  
5. No GPL `pcievhost` sources in `rtl/` or `tb/uvm`.  
6. No MindShare PDF content committed; keep under `specs/`.

---

## 12. Non-goals (explicit)

- SerDes PIPE architecture in FPGA Rivet  
- Soft elastic buffer / 8b/10b codec in MAC for Gen2  
- PIPE Message Bus / LPC  
- Gen3/4 EQ protocol while Gen2 is active  
- Copying reference RTL or GPL VIP into the tree  
- Treating AXI-ST as the only DLL↔MAC interface  

---

## 13. Related reading

| Doc | Why |
|-----|-----|
| [ltssm.xlsx](ltssm.xlsx) | LTSSM states, transitions, port list, timers, open findings |
| [pipe-notes.md](pipe-notes.md) | PIPE TX/RX, EB, PowerDown, RxStatus |
| [architecture.md](architecture.md) | Stack terminology |
| [roadmap.md](roadmap.md) | Phase order |
| [gen-evolution.md](gen-evolution.md) | Gen deltas |
| [pg213-interface.md](pg213-interface.md) | User/status ports |
| [ref-pcievhost.md](ref-pcievhost.md) | Clean-room Gen1–2 behavior ideas |
| Local `specs/` | PIPE / PCIe Base / PG213 / PG239 (not in git) |
