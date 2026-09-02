# Rivet DLL — implementation follow-guide

**Audience:** anyone implementing or reviewing the Data Link Layer inside `rivet_pcie_ctrl`.  
**Active target:** `MODE=EP`, **Gen2**, `LANES` ∈ {1,2,4}, VC0 only.  
**Companion docs:** [mac.md](mac.md) (PHY framing / LTSSM), [pg213-interface.md](pg213-interface.md) (user FC visibility), [roadmap.md](roadmap.md).

This is an **original Rivet engineering plan**. Normative detail stays in local
`specs/` (gitignored). Do **not** paste Base Spec / MindShare / PG213 text or
figures into the repo.

**Primary references (local only):**

| Doc | Use for |
|-----|---------|
| PCI Express Base Specification Rev 2.1 | DLLP formats, FC init / UpdateFC rules, LCRC / seq / ACK-NAK, DL_* states |
| MindShare PCI Express Technology 3.0 | Pedagogy for FC counters and InitFC1→InitFC2 story (non-normative) |
| PG213 UltraScale+ PCIe v1.3 | `cfg_fc_*`, `pcie_tfc_*` user-visible credit ports |

---

## 1. Where DLL sits

```text
  AXI-ST CQ/CC/RQ/RC + cfg_mgmt + cfg_fc_* / pcie_tfc_*   ← user (TL / cfg)
                         │
                   ★  DLL  ★   — DLLP, FC, LCRC, seq, ACK/NAK, replay
                         │
              rivet_dll_mac_if  (payload beats + sideband)
                         │
                   MAC         — STP/SDP/END/EDB, stripe, scramble, SKP, LTSSM
                         │
                   PIPE → PHY
```

| DLL owns | Does **not** own |
|----------|------------------|
| DLLP build / parse + **16-bit DLLP CRC** | STP / SDP / END / EDB (MAC) |
| InitFC1 / InitFC2 / UpdateFC for **VC0** | Ordered sets / LTSSM (MAC) |
| Credit counters + TX TLP gate (vs peer credits) | Scramble / deskew / SKP (MAC) |
| TLP **seq#** + **32-bit LCRC** + ACK/NAK + replay | User AXI-ST packing (TL) |
| Report credits toward TL / PG213-style ports | Gen3+ FC scaling features (later) |

**Locked decisions (2026-09):**

1. **LCRC lives in DLL** (not MAC). MAC receives wire-ready TLP bytes that already
   include Sequence Number + LCRC, and wraps them with Physical Layer framing.
2. **FC before TLP.** No application TLP TX until VC0 FC initialization completes
   and the TX credit gate allows it. UpdateFC runs continuously after init.
3. **Minimal TL for FC is required now** (buffer sizes + credit-allocated /
   credit-freed events). Full TLP assemble/decode waits until after FC works.
4. **DLL↔MAC width follows the PIPE wire:** `DLL_DATA_W = LANES * PIPE_DATA_WIDTH`
   (Gen2 → `LANES*16` **bits**). User AXI-ST width is **independent**
   (`AXI_DATA_WIDTH` ∈ {64,128,256,512} per PG213). TL owns the gear box.
   See [§5](#5-parametric-datapath-width).
5. **MAC framing (incl. SDP) proceeds in parallel** with DLL D0/D1 — not a serial
   gate on offline DLLP/CRC work.
6. **Smoke FC ads:** PH/NPH/PD/NPD = large finite (cap below protocol maxima);
   **CPLH/CPLD = infinite** (`00h` / `000h`) for EP. See [§4.1](#41-infinite-vs-finite-credits).

---

## 2. DL feature states (DLL view)

Physical Layer reaching L0 (`link_up`, `accept_dll_tlp`) is necessary but not
sufficient for TLP traffic. Rivet owns an explicit **Data Link SM** (do not
collapse into FC-only logic):

```text
  DL_Inactive  — !accept_dll_tlp / !link_up; clear seq / freeze replay
       ↓ accept
  DL_Init      — FC_INIT1 → FC_INIT2 (rivet_dll_fc); no application TLP
       ↓ fc_init_done
  DL_Active    — UpdateFC + TLP TX/RX + ACK/NAK; REPLAY_TIMER armed
       ↓ NAK or REPLAY_TIMER expiry (while Active)
  DL_Replay    — retransmit from replay buffer; then return to Active
       ↓ accept drops / REPLAY_NUM overflow → LTSSM retrain hint
  DL_Inactive
```

`DL_Feature` (Gen2 EP VC0) is **omitted / stubbed**. Exit / re-init when MAC
drops `accept_dll_tlp` / `link_up` (`replay_freeze` already on sideband).

FC SM (`rivet_dll_fc`) remains nested under `DL_Init` / `DL_Active`. Reliability
(seq, LCRC, ACK/NAK, replay) runs only in `DL_Active` / `DL_Replay`.

---

## 3. DLLP inventory (Gen2 EP, VC0 first)

All DLLPs are a fixed **8-byte** packet: type / body fields + **16-bit CRC**.
Bad CRC → discard DLLP (no ACK/NAK implied by the CRC miss alone).

| Class | Types (VC0) | When |
|-------|-------------|------|
| Flow-control init | InitFC1-P / -NP / -Cpl | FC_INIT1; order **P → NP → Cpl**; repeat ≥ every 34 µs |
| Flow-control init | InitFC2-P / -NP / -Cpl | FC_INIT2; same order and body credits as InitFC1 |
| Flow-control update | UpdateFC-P / -NP / -Cpl | DL_Active; periodic + when buffers free |
| Ack / Nak | Ack, Nak | With TLP reliability (later milestone) |
| PM | Enter_L1 / L23 / ASPM / Request_Ack | Defer until power mgmt |

FC DLLP body fields (engineering summary):

- Virtual Channel in type low bits (VC0 = 0 for now).
- **HdrFC** — header credit value (8-bit field width in the protocol counters).
- **DataFC** — data credit value (12-bit field width in the protocol counters).

Credit **units** (Base 2.1 Ch.2 FC):

- Data credit unit = **4 DW** (16 bytes).
- Header credit unit = one max-size header (digest-capable); Rivet Gen2 EP starts
  with the common non-prefix header size model.

### 4.1 Infinite vs finite credits

**Infinite** is advertised at FC init as **all zeros** in the credit field:

| Field | Width | Infinite encoding |
|-------|-------|-------------------|
| HdrFC (PH / NPH / CPLH) | 8 bits | `00h` |
| DataFC (PD / NPD / CPLD) | 12 bits | `000h` |

Transmitter treats that type as never throttled. UpdateFC for an infinite field
must carry zeros (receiver ignores). Finite types still need UpdateFC on the
Base schedule.

**Who must advertise infinite Completion (EP focus):**

- Endpoint: **CPLH + CPLD = infinite** (Base minimum for EP).
- Root Complex without peer-to-peer between all RPs: same.
- Switch / RC with P2P: may use finite CPL (deadlock care) — **out of Rivet EP scope**.

P / NP header and data are normally **finite** (real RX buffers). Protocol also
caps outstanding unused ads (~127 header / ~2047 data cumulative) — do not
spam “max” beyond that.

**Smoke / sim defaults (Rivet):**

| Type | Init advertisement |
|------|--------------------|
| PH, NPH | Finite max useful for sim (e.g. `7Fh` header = 127) |
| PD, NPD | Finite large but ≤ 2047 (`7FFh` ok) |
| CPLH, CPLD | **Infinite** (`00h` / `000h`) |

“Max credit” for smoke means **max legal finite** for P/NP, not infinite on
those types unless we deliberately test infinite-P paths later.

### 4.2 What is CPL?

**CPL = Completion** traffic class in flow control (not a DLLP name by itself).

PCIe splits TLP traffic into three FC types:

| FC type | Abbrev | Examples |
|---------|--------|----------|
| Posted | P | Memory Write, Message (no response required) |
| Non-Posted | NP | Memory Read, Cfg/IO Read/Write (needs a Completion) |
| Completion | **Cpl** | Completion / Completion with Data — the **response** to an NP |

So **CPLH / CPLD** are header/data credit pools for Completions the peer will
send us (when we issued NP requests) or that we must accept. An Endpoint almost
always gives the link partner **infinite CPL credits** so completions for our
reads are never blocked by FC.

DLLP names: `InitFC*-Cpl`, `UpdateFC-Cpl` carry those CPLH/CPLD values.

Type encodings and CRC polynomial / bit order: implement from Base 2.1 §3.4
(tables for DLLP Type and CRC). Do not copy tables into git.

---

## 4. Flow-control model (what we implement)

Per traffic type {P, NP, Cpl} × {Hdr, Data} keep the classic counter set:

| Counter | Side | Meaning |
|---------|------|---------|
| **CREDIT_LIMIT (CL)** | TX | Peer’s advertised cumulative credits (from InitFC / UpdateFC) |
| **CREDITS_CONSUMED (CC)** | TX | Credits used by TLPs we sent |
| **CREDITS_ALLOCATED (CA)** | RX | Credits we have granted to the peer (InitFC / UpdateFC payload) |
| (optional) CREDITS_RECEIVED | RX | Debug / overflow check |

TX may send a TLP only if for every required credit type:

```text
  (CC + credits_needed) mod 2^W  is still “inside” CL
```

(with the usual infinite-credit exception when init advertised infinite).

**Init sequence (both ends):**

1. While FC_INIT1: continuously send InitFC1-P, InitFC1-NP, InitFC1-Cpl advertising
   **our** CA (from TL RX buffer sizes). Capture peer InitFC1 into CL.
2. After a full peer InitFC1 set: enter FC_INIT2; send InitFC2-* with the **same**
   advertised values; capture peer InitFC2 (or UpdateFC / TLP as FI2 shortcuts
   per Base rules).
3. When local FI1/FI2 complete → **DL_Active**.

**After init:** schedule UpdateFC-* so peer CL tracks buffer frees; still send
UpdateFC for types advertised infinite (fields zero / ignored per rules).

MindShare’s CC / CL / CA story is the teaching model; Base 2.1 remains normative
for timers, minima, and infinite-credit edge cases.

---

## 5. Parametric datapath width

### 5.1 User AXI vs DLL/MAC width (PG213)

PG213 UltraScale+ supports **configurable 64 / 128 / 256 / 512-bit** AXI-ST
datapaths. **64-bit is valid** (own tables for 64/128/256; 512 has different
`tuser` / straddle rules). Rivet already targets 64-bit first; wider later.

These user widths are **not** the same knob as link width (`LANES`):

| Knob | Values | Owner |
|------|--------|-------|
| `AXI_DATA_WIDTH` | 64 / 128 / 256 / (512 later) | TL ↔ user |
| `DLL_DATA_W` | `LANES * PIPE_DATA_WIDTH` bits | DLL ↔ MAC |
| `PIPE_DATA_WIDTH` | 16 (Gen2 now) | MAC ↔ PHY |

Example Gen2 (`PIPE_DATA_WIDTH=16`):

| LANES | Wire / pclk | `DLL_DATA_W` |
|-------|-------------|--------------|
| 1 | 16 bits (2 symbols) | 16 |
| 2 | 32 bits | 32 |
| 4 | 64 bits | 64 |

Changing user IF from 64→256 only touches TL packing; DLL/MAC stay
lane-scaled. Forcing DLL to equal AXI width would **fight** striping and still
need a gear box when `LANES` and `AXI_DATA_WIDTH` disagree — so we **do not**
tie DLL to AXI.

### 5.2 CRC / FC vs beat width

| Concern | Width coupling |
|---------|----------------|
| DLLP CRC-16 | Byte-stream; fixed 8-byte DLLP |
| TLP LCRC-32 | Byte-stream over Seq# + TLP |
| FC credits | Header / DW units |
| MAC striping | Scales with `LANES` + PIPE |

CRC/FC engines stay streaming (byte or DW). Parallel beats only move payload.

### 5.3 Locked formula

```text
  parameter int unsigned LANES = ...;
  parameter int unsigned PIPE_DATA_WIDTH = 16;           // Gen2
  parameter int unsigned DLL_DATA_W = LANES * PIPE_DATA_WIDTH;  // bits
  // AXI_DATA_WIDTH independent: 64 / 128 / 256 / 512 (PG213)
```

`keep` width tracks `DLL_DATA_W/8` (or DW-granular later if we mirror PG213
`tkeep` style on the internal IF — decide at D0; either is fine if documented).

---

## 6. DLL ↔ MAC contract (already stubbed)

Defined today in `rivet_pkg` + `rtl/pcie_ctrl/dll/rivet_dll_mac_if.sv`:

| Path | Content |
|------|---------|
| DLL TX → MAC | `data/keep/sop/eop/pkt_type` — DLLP or TLP bytes **after** DLLP-CRC or LCRC |
| MAC RX → DLL | Same + `err` (framing / symbol abort) |
| MAC → DLL SB | `link_up`, `ltssm_state`, width/speed, `accept_dll_tlp`, `replay_freeze` |
| DLL → MAC SB | `replay_timer_expired`, `nak_storm`, `tx_idle_req` (grow later) |

**Prerequisite:** MAC M2 framing (SDP for DLLP, STP/END for TLP) + L0 datapath
untie. Until then DLL can be unit-tested against a behavioral MAC harness.

---

## 7. DLL ↔ TL contract (minimal for FC — do now)

Full TL TLP path is **later**. For FC we still need a thin TL credit face:

```text
  TL (buffer model)              DLL (FC / Init / Update)
  ─────────────────              ────────────────────────
  rx_buf_size_{ph,pd,...}   →   CA values in InitFC/UpdateFC
  rx_credits_freed_*        →   bump CA + schedule UpdateFC
  tx_credits_available_*    ←   from CL − CC (gate)
  tx_tlp_consume_*          →   bump CC when a TLP is accepted (later)
  fc_init_done / dl_active  ←   status
```

Suggested types (names illustrative — finalize in `rivet_pkg` or `rivet_dll_pkg`):

- `rivet_fc_credit_set_t` — PH/PD/NPH/NPD/CPLH/CPLD + per-field `infinite` flags  
- `rivet_tl_dll_fc_sb_t` — advertised CA, freed pulses, MPS, infinite policy  
- `rivet_dll_tl_fc_sb_t` — CL snapshot, available credits, `fc_init_done`

**EP defaults (starting point, tune with buffer RTL):**

| Type | Initial advertise |
|------|-------------------|
| PH / NPH | ≥ 1 (finite from RX header FIFO depth) |
| PD / NPD | From payload FIFO / Max_Payload_Size |
| CPLH / CPLD | **Infinite** (`00h` / `000h`) — required EP policy |
| PH / NPH / PD / NPD | Finite from parameterized RX depths (smoke: large legal max) |

TL stub can hardcode these sizes with parameters — no AXI-ST traffic required yet.

### 7.1 PG213 user visibility (map later, stub early)

| Port | Role |
|------|------|
| `cfg_fc_ph/pd/nph/npd/cplh/cpld` + `cfg_fc_sel` | Muxed view of RX/TX credit sets |
| `pcie_tfc_nph_av`, `pcie_tfc_npd_av` | TX NP credit availability for RQ scheduling |

Internal DLL counters remain authoritative; these ports are a **projection**.

---

## 8. Planned RTL modules (`rtl/pcie_ctrl/dll/`)

```text
rivet_dll
├── rivet_dll_sm             # DL_Inactive / Init / Active / Replay
├── rivet_dll_crc16          # DLLP CRC
├── rivet_dll_lcrc32         # TLP LCRC (seq + TLP bytes)
├── rivet_dllp_tx            # Serialize DLLP + CRC; arb vs TLP
├── rivet_dllp_rx            # Parse DLLP; CRC check; demux by type
├── rivet_dll_fc             # CA/CL/CC, InitFC1/2, UpdateFC
├── rivet_dll_tlp_tx         # Seq#, LCRC append, replay push
├── rivet_dll_tlp_rx         # LCRC/seq check, ACK/NAK request
└── rivet_dll_replay         # Retry buffer (parametric)
```

Folder README stays thin; this file is the checklist.

### 8.1 Replay buffer sizing (locked for Phase 1)

Spec does **not** mandate a fixed byte count. Size so the buffer can hold all
in-flight TLPs for one ACK round-trip without stalling under max payload:

```text
depth_bytes ≈ f(LANES, wire_rate, MPS, AckLatency, InternalDelay, SafetyFactor)
```

| Knob | Phase-1 default |
|------|-----------------|
| Wire rate | Gen1 training / L0 (2.5 GT/s) until Recovery.Speed exists |
| `LANES` | 1 / 2 / 4 |
| `MPS_BYTES` | **128** (cfg may raise later) |
| `REPLAY_TLP_SLOTS` | **16** (sim-friendly; each slot holds one max TLP) |
| `REPLAY_SLOT_BYTES` | `MPS_BYTES + 32` (seq + hdr + LCRC + margin) |
| Safety | ~1.5–2× vs theoretical AckLatency occupancy |
| REPLAY_TIMER | ~3× AckLatency band (exact Base table later) |

Override via module parameters. Too small → early TX stall; too large → BRAM
only. Directed tests may shrink slots (e.g. 4) for fast fill/starve cases.

---

## 9. Implementation milestones

### D0 — Types, CRC16, DLLP codec (no wire yet)

- [x] `rivet_dll_crc16` + Verilator TB (`scripts/sim_dll_crc16.ps1`)
- [x] DLLP beats stay **64-bit** (one 8-byte DLLP); wire `LANES*PIPE` is MAC-only
- [x] `rivet_dllp_tx` / `rivet_dllp_rx` (FC + Ack/Nak) + round-trip TB
- [x] TL↔DLL FC sideband structs + `rivet_tl_fc_stub` (CA params; CPL infinite)
- [x] `rivet_dll` top wired in `rivet_pcie_ctrl` (TX idle until D1)
- [x] Gate: Verilator lint + `scripts/sim_dllp_roundtrip.ps1` + LTSSM smoke

### D1 — VC0 InitFC exchange

- [x] `rivet_dll_fc` FC_INIT1 / FC_INIT2 state machine  
- [x] Drive InitFC1/2 only when MAC `accept_dll_tlp`  
- [x] Capture peer credits into CL; publish `fc_init_done`  
- [x] Dual-DLL Verilator TB (`scripts/sim_dll_fc_init.ps1`) — beat cross-connect (no MAC)  
- [x] Gate: Verilator `sim_dll_fc_init` + Questa `ltssm_l0_gen2_x{1,2,4}` (FC UVM peer later)  

### D2 — UpdateFC + credit return

- [x] Periodic UpdateFC-P/NP/Cpl from CA  
- [x] TL `credits_freed` increments CA and schedules UpdateFC  
- [x] Still **no** application TLP  
- [x] Gate: Verilator `sim_dll_fc_update` (peer CL tracks free; infinite CPL sticky)  
- [x] Gate: Questa `ltssm_l0_gen2_x{1,2,4}`  

### D3 — TX gate + PG213 FC stubs

- [x] Expose available TX credits to TL / `pcie_tfc_*` / `cfg_fc_*`  
- [x] Consume API gates CC bumps; `*_ok` / `tx_gate_ready` for future TLP  
- [x] Still **no** application TLP  
- [x] Gate: Verilator `sim_dll_fc_gate` (starve → peer UpdateFC restore)  
- [x] Gate: Questa `smoke_gen2_x1` + `ltssm_l0_gen2_x{1,2,4}`  

### D4 — TLP reliability (DL SM + ACK/NAK + replay)

Split: **D4a** infrastructure → **D4b** on-wire TLP path.

#### D4a — SM, LCRC, replay core (no full TL yet)

- [x] `rivet_dll_sm`: Inactive / Init / Active / Replay  
- [x] `rivet_dll_lcrc32` + Verilator TB  
- [x] `rivet_dll_replay` parametric slots; ACK purge / NAK replay API  
- [x] Gate: Verilator LCRC + SM + replay + FC regress; Questa smoke + L0  

#### D4b — Seq/LCRC on TLP beats + ACK/NAK scheduling

- [ ] `rivet_dll_tlp_tx` / `rivet_dll_tlp_rx`  
- [ ] ACK/NAK DLLP schedule from RX; REPLAY_TIMER / REPLAY_NUM  
- [ ] Gate: dual-DLL TLP + ACK purge / NAK replay; then real TL hook (D5)  

### D5 — Hook full TL

- [ ] Discuss when D1–D3 green; see `rtl/pcie_ctrl/tl/README.md`  

**MAC dependency:** D1 on-wire needs MAC M2 SDP (and later STP). Prefer parallel
tracks: D0 CRC/DLLP offline while MAC framing is built.

---

## 10. Verification notes

| Gate | Intent |
|------|--------|
| Verilator lint | All new `dll/` + pkg |
| Unit TB | CRC16, DLLP codec, FC SM without PHY |
| LTSSM L0 smoke | Unchanged; still Gen1-rate L0 |
| New FC smoke / UVM | Peer that speaks InitFC/UpdateFC over PIPE after L0 |
| Questa | Required when available; else “UVM deferred” |

Scoreboard hooks: DLLP type timeline, CA/CL/CC snapshots, `fc_init_done`.

---

## 11. Explicit non-goals (for now)

- VC1+ and TC mapping beyond TC0/VC0  
- ACK/NAK / replay before FC works  
- ECRC (TL digest optional later)  
- ASPM / PM DLLPs  
- Gen3+ FC scaling / extended credits  
- Treating AXI-ST as the DLL↔MAC interface  

---

## 12. Resolved / remaining decisions

| Topic | Decision |
|-------|----------|
| `DLL_DATA_W` | `LANES * PIPE_DATA_WIDTH` bits (Gen2: `LANES*16`) |
| User AXI width | Independent; **64 supported** by PG213; Rivet starts at 64 |
| MAC SDP | Parallel with DLL D0; required for on-wire D1 |
| Smoke credits | P/NP large finite; **CPL infinite** |
| Finite CPL mode | Deferred (switch / P2P RC only) |
| Replay depth | Parametric; default **16×(MPS+32)** @ MPS=128 |
| DL SM | Explicit Inactive/Init/Active/Replay (not FC-only) |

Still pick at D0 RTL: internal `keep` byte vs DW granularity on DLL↔MAC beats.

---

## 13. References (not redistributed)

Keep under local `specs/`:

- `Gen2/PCI Express Base Specification Revision 2.1.pdf` — Ch.2 FC, Ch.3 DLL  
- `MindShare_PCIe30_eBook_v1.03.pdf` — FC / DLL teaching chapters  
- `pg213-pcie4-ultrascale-plus-en-us-1.3.pdf` — `cfg_fc_*`, `pcie_tfc_*`  

Related Rivet docs: [mac.md](mac.md), [architecture.md](architecture.md),
[verification.md](verification.md), [pg213-interface.md](pg213-interface.md).
