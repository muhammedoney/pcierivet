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
4. **DLL↔MAC datapath width is parameterized** and should grow with `LANES`
   (see [§5](#5-parametric-datapath-width)).

---

## 2. DL feature states (DLL view)

Physical Layer reaching L0 (`link_up`, `accept_dll_tlp`) is necessary but not
sufficient for TLP traffic. Data Link then roughly:

```text
  DL_Inactive → DL_Feature (omit / stub for Gen2 EP VC0) → DL_Init
       → FC_INIT1 (exchange InitFC1) → FC_INIT2 (exchange InitFC2)
       → DL_Active  (UpdateFC + later TLP/ACK)
```

Rivet Phase-1 focus: **VC0 only**, autonomous hardware init (no software VC enable).
Exit / re-init when MAC drops `accept_dll_tlp` / `link_up` (replay freeze already
on sideband).

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
- EP receivers typically advertise **infinite Completion** credits; PH/NPH/PD/NPD
  are finite from real RX buffer sizes.

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

### 5.1 Is lane-scaled width possible with LCRC / DLLP CRC?

**Yes.** Protocol CRCs and FC math are **not** tied to AXI or PIPE beat width:

| Concern | Width coupling |
|---------|----------------|
| DLLP CRC-16 | Byte-stream over the 6 DLLP body bytes; fixed packet |
| TLP LCRC-32 | Byte-stream over Seq# + TLP (+ digest if present) |
| FC credits | Header / DW units, independent of internal bus |
| MAC striping | **Does** scale with `LANES` (and PIPE bytes/lane/clk) |

So: implement CRC and FC as **streaming / sequential** engines (byte or DW
step). Do **not** invent a CRC that “runs once per lane”. Parameterize only the
**parallel beat** that carries bytes between TL↔DLL↔MAC.

### 5.2 Rivet recommendation

```text
  parameter int unsigned LANES = ...;
  // Gen2 Original PIPE: 16 bits/lane → 2 symbols/lane/pclk
  localparam int unsigned SYM_PER_LANE = PIPE_DATA_WIDTH / 8; // 2 for width=16
  parameter int unsigned DLL_DATA_W =
      (LANES * SYM_PER_LANE * 8);  // x1→16B, x2→32B, x4→64B  — or next power-of-two
```

Practical policy for Phase 1:

1. Put `DLL_DATA_W` (and matching `keep` width) on `rivet_dll_mac_*_beat_t`
   **or** keep packed beats in `rivet_pkg` with a `parameter`ized wrapper IF.
2. Default mapping for Gen2 16-bit PIPE: **64 / 128 / 256** bit beats for
   ×1 / ×2 / ×4 if we prefer AXI-like widths; or exact `LANES*16` bytes.
   Prefer **power-of-two ≥ wire bytes/pclk** so striping packs cleanly.
3. CRC blocks take a byte (or DW) stream with `valid`/`last` — width-agnostic.
4. First bring-up may temporarily force `DLL_DATA_W=64` for all lane configs
   **if** MAC framing is still ×1-oriented; grow width when striping lands.

Open micro-choice (decide at D0 RTL): exact formula `LANES*16` bytes vs
`64<<$clog2(LANES)`. Document the pick in the IF header comment.

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
| CPLH / CPLD | **Infinite** (typical Endpoint) |

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
├── rivet_dll_crc16          # DLLP CRC (streaming)
├── rivet_dll_lcrc32         # TLP LCRC (streaming) — after FC milestones
├── rivet_dllp_tx            # Serialize DLLP + CRC; arb vs TLP later
├── rivet_dllp_rx            # Parse DLLP; CRC check; demux by type
├── rivet_dll_fc             # CA/CL/CC, InitFC1/2 SM, UpdateFC scheduler
├── rivet_dll_tlp_tx         # Seq#, LCRC append, replay push (later)
├── rivet_dll_tlp_rx         # LCRC/seq check, ACK/NAK request (later)
└── rivet_dll_replay         # Retry buffer (later)
```

Folder README stays thin; this file is the checklist.

---

## 9. Implementation milestones

### D0 — Types, CRC16, DLLP codec (no wire yet)

- [ ] Parameter `DLL_DATA_W` (lane-linked) + widen / parameterize beats if needed  
- [ ] `rivet_dll_crc16` + directed tests (known vectors from Base examples / self-check)  
- [ ] `rivet_dllp_tx` / `rivet_dllp_rx` for FC + Ack encodings (Ack path dormant)  
- [ ] TL↔DLL FC sideband structs; TL stub module with parameterized CA  
- [ ] Gate: Verilator unit TB for CRC + round-trip DLLP encode/decode  

### D1 — VC0 InitFC exchange

- [ ] `rivet_dll_fc` FC_INIT1 / FC_INIT2 state machine  
- [ ] Drive InitFC1/2 only when MAC `accept_dll_tlp`  
- [ ] Capture peer credits into CL; publish `fc_init_done`  
- [ ] Depends on MAC framing SDP path **or** MAC behavioral stub in TB  
- [ ] Gate: UVM/smoke peer completes InitFC both directions → DL_Active  

### D2 — UpdateFC + credit return

- [ ] Periodic UpdateFC-P/NP/Cpl from CA  
- [ ] TL `credits_freed` increments CA and schedules UpdateFC  
- [ ] Still **no** application TLP  
- [ ] Gate: peer CL tracks freed credits; infinite CPL fields handled  

### D3 — TX gate + PG213 FC stubs

- [ ] Expose available TX credits to TL stub / `pcie_tfc_*` / `cfg_fc_*`  
- [ ] Block TL TLP submission when gate fails (API ready before TLP RTL)  
- [ ] Gate: directed credit-starvation test  

### D4 — TLP reliability (after framing + FC proven)

- [ ] Seq# / LCRC TX+RX, ACK/NAK DLLPs, replay buffer  
- [ ] Only then enable real TL TLP transfer  

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

## 12. Open questions (decide before / during D0)

1. Exact `DLL_DATA_W` formula: `LANES*16` bytes vs `64<<clog2(LANES)`?  
2. First on-wire FC test: real MAC SDP vs behavioral MAC harness?  
3. Initial RX buffer sizes (parameters) for smoke vs silicon-intent?  
4. Infinite CPL only, or also allow finite CPL for switch-like modes later?

---

## 13. References (not redistributed)

Keep under local `specs/`:

- `Gen2/PCI Express Base Specification Revision 2.1.pdf` — Ch.2 FC, Ch.3 DLL  
- `MindShare_PCIe30_eBook_v1.03.pdf` — FC / DLL teaching chapters  
- `pg213-pcie4-ultrascale-plus-en-us-1.3.pdf` — `cfg_fc_*`, `pcie_tfc_*`  

Related Rivet docs: [mac.md](mac.md), [architecture.md](architecture.md),
[verification.md](verification.md), [pg213-interface.md](pg213-interface.md).
