# PIPE notes for Rivet (engineering digest)

**Purpose:** Rivet-oriented notes for the MAC ↔ PHY boundary.  
**Primary local training source:** `specs/MindShare_PIPE_vC.2.pdf` (MindShare PIPE course, based on PIPE spec rev 6.0, version C.2).  
**Implementation authority for Rivet ports:** AMD **PG239** via `rtl/interfaces/rivet_pipe_if.sv` + [gen-evolution.md](gen-evolution.md).

## Copyright / redistribution

The MindShare PDF is **copyrighted course material** (“Do Not Distribute”). This document is an **original Rivet engineering digest** — concepts restated for our Gen2-first MAC work. It is **not** a slide-by-slide conversion and must **not** paste MindShare figures, long verbatim bullet lists, or proprietary wording.

Keep the PDF under local `specs/` (gitignored). Prefer the Intel PIPE specification itself as the normative reference when implementing.

---

## 1. What PIPE is

PIPE (Physical Interface for PCI Express — also used for SATA/USB/DisplayPort/USB4 families) standardizes the per-lane interface between:

| Side | Role in Rivet |
|------|----------------|
| **MAC** | Soft logic inside `rivet_pcie_ctrl` (LTSSM, ordered sets, framing to DLL) |
| **PHY** | PCS + PMA — for Rivet FPGA, **PG239** wrapped by `rivet_pcie_phy_*` |

Higher layers (Transaction / Data Link) sit **above** the MAC; serial lanes sit **below** the PHY.

---

## 2. Two PIPE architectures (Rivet choice)

| Architecture | Encode / elastic buffer | Data width flavor | Rivet |
|--------------|-------------------------|-------------------|--------|
| **Original PIPE** | 8b/10b or 128b/130b **inside PHY**; elastic buffer **in PHY** | Byte-oriented: 8 / 16 / 32 (classic); PG239 extends pin width | **Active** — matches PG239 |
| **SerDes PIPE** | Encode/decode + elastic buffer **moved to MAC**; thinner PHY | Multiples of 10 bits (10/20/40/80) | **Not** our FPGA path |

**Implication for Rivet Gen2:** MAC does **not** implement the RX elastic buffer or 8b/10b codec. Those live in PG239 PCS. MAC must still:

- Generate / consume **SKP** (and other OS) at the **logical** link layer so the PHY EB can absorb ppm drift.
- Honor **RxStatus** SKP add/remove and EB overflow/underflow codes.
- Drive Gen1/2 **TxDataK / RxDataK** and observe **RxValid**.

SerDes notes stay in this doc only so Gen3+ / ASIC discussions do not confuse boundaries.

---

## 3. Clocking: PCLK, width, throttling

Interface transfers are timed by **PCLK**.

| Option | Notes | Rivet / PG239 |
|--------|-------|----------------|
| PCLK as PHY **output** | Legacy; trend is deprecation; not used for PCIe 5+ | Possible on some PHYs |
| PCLK as PHY **input** | MAC/system provides PCLK; favored in later PIPE | Prefer when designing clocking |

Link rate can be absorbed by changing **width**, **PCLK**, or **data throttling** (`TxDataValid` / `RxDataValid` sparingly).

**Rivet Gen1/2 lock (PG239 UltraScale+):** fixed **16-bit/lane** datapath; Gen1 vs Gen2 is mainly **PCLK** (125 vs 250 MHz), not byte-width change. See [gen-evolution.md](gen-evolution.md).

MindShare examples of “fixed 250 MHz → Gen1 1B / Gen2 2B / Gen3 4B” are **generic PIPE options**, not the Rivet/PG239 Gen1↔Gen2 policy.

---

## 4. Multi-lane composition

- Most PIPE signals are **per lane**.
- A few may be **shared** across lanes (examples: PCLK, Rate, Width, Reset# — implementation-dependent).
- PCIe links are **symmetric** (same lane count each direction). Rivet params: `LANES` ∈ {1,2,4}.
- Packing convention in Rivet: `{LaneN-1, …, Lane0}` on wide buses (`rivet_pipe_if`).

---

## 5. Original PIPE TX path (Gen1/2 mental model)

PHY-side chain (conceptual — **inside PG239**, not Rivet RTL):

```text
MAC TxData / TxDataK / (TxDataValid)
        → optional width mux / throttle
        → serialize register
        → 8b/10b encode
        → differential TX
```

MAC responsibilities:

| Signal / action | Gen2 use |
|-----------------|----------|
| `txdata` / `txdatak` | Symbols + K/D; 2 K bits per lane at 16-bit width |
| `txelecidle` | Enter/exit electrical idle with OS (EIOS) |
| `txdetectrx` | Receiver detect (with PowerDown + ElecIdle combo) |
| `txcompliance` | Compliance pattern |
| `rate` | Gen1=`0`, Gen2=`1` (PIPE encodings; PG239 `rate[2:0]`) |
| `powerdown` | P0 / P0s / P1 / P2 mapping to LTSSM / ASPM |
| `txmargin` / `txswing` / `txdeemph` | Gen1/2 driver; Gen2 de-emphasis select |

Gen3+ adds block controls (`txdata_valid`, `txstart_block`, `txsync_header`) — present on Rivet IF, idle until Phase 3+.

---

## 6. Original PIPE RX path (Gen1/2 mental model)

PHY-side chain (conceptual — **inside PG239**):

```text
differential RX → CDR → symbol lock (e.g. K28.5)
  → elastic buffer (recovered → PCLK domain)
  → 8b/10b decode → RxData / RxDataK
  → RxValid, RxElecIdle, RxStatus
```

MAC responsibilities:

| Signal | Meaning for Gen2 MAC |
|--------|----------------------|
| `rxdata` / `rxdatak` | Decoded symbols after PHY PCS |
| `rxvalid` | Symbol lock / valid data; EB overflow/underflow can clear it |
| `rxelecidle` | Electrical idle detect (async on many PHYs) |
| `rxstatus[2:0]` | Per-lane status/error (see below) |
| `rxpolarity` | Lane polarity invert request |
| `phystatus` | Handshake: reset done, power/rate/detect complete |

---

## 7. RxStatus encodings (PCIe — Gen2-critical)

| Code | Meaning (PCIe) |
|------|----------------|
| `000` | Data OK |
| `001` | One SKP **added** |
| `010` | One SKP **removed** |
| `011` | Receiver **detected** (with detect sequence) |
| `100` | Decode error (optional disparity) |
| `101` | Elastic buffer **overflow** |
| `110` | Elastic buffer **underflow** (not used in nominal-empty EB mode) |
| `111` | Disparity error (if not folded into `100`) |

UVM PIPE monitor / scoreboard should treat SKP add/remove as **expected** during L0, and overflow/underflow / decode errors as **Recovery** triggers.

---

## 8. Elastic buffer (why MAC still cares)

| Item | Original PIPE (Rivet) | SerDes PIPE |
|------|------------------------|-------------|
| EB location | **PHY** | **MAC** |
| Clock problem | ±300 ppm per device → up to ~600 ppm skew | Same physics |
| Compensation | TX inserts **SKP OS**; RX EB adds/removes SKP symbols | MAC owns EB |

Modes (PHY/MAC register or capability — PG239 handles internals):

- **Nominal half-full** — target ~50% fill; add/remove SKP to stay there.
- **Nominal empty** — minimize latency; may pause with DataValid rather than inventing SKPs when local clock is faster.

**Rivet Gen2:** do not build EB RTL in `rivet_pcie_ctrl`. Do implement **SKP scheduling** on TX and **tolerate** RXStatus SKP codes. SRIS (separate RefClk) needs deeper EB — PHY/config concern, not Phase 1 soft MAC.

---

## 9. PowerDown × TxDetectRx × TxElecIdle (PCIe)

Canonical combinations (MAC must not request illegal ones):

| PowerDown | TxDetectRx | TxElecIdle | Meaning |
|-----------|------------|------------|---------|
| P0 | 0 | 0 | Transmit MAC data |
| P0 | 0 | 1 | Electrical idle |
| P0 | 1 | 0 | Loopback |
| P0 | 1 | 1 | **Illegal** |
| P0s | * | 0 | **Illegal** (must idle) |
| P0s | * | 1 | Electrical idle |
| P1 | * | 0 | **Illegal** |
| P1 | 0 | 1 | Electrical idle |
| P1 | 1 | 1 | **Receiver detect** |
| P2 | * | 0 | Beacon |
| P2 | 0 | 1 | Electrical idle |
| P2 | 1 | 1 | Receiver detect |

`PhyStatus` pulses complete power/rate/detect operations. Detect example: while in P1/P2 with detect+idle, `RxStatus` reports present/not-present with `PhyStatus`.

PCIe PowerDown encodings used by Rivet (`powerdown[1:0]` on PG239 path):

| Code | State | Typical LTSSM use |
|------|-------|-------------------|
| `00` | P0 | L0 and most training states |
| `01` | P0s | L0s |
| `10` | P1 | L1 / Detect / Disabled (as needed) |
| `11` | P2 | Deep L1/L2 (when supported) |

---

## 10. Rate / width (PIPE command plane)

PIPE Rate (PCIe): `0`=2.5, `1`=5.0, `2`=8.0, `3`=16, `4`=32 GT/s.  
Width (classic Original): 8 / 16 / 32 bits when encode in PHY.

Rivet Phase 1: hold `rate=Gen2`, `PIPE_DATA_WIDTH=16`. Do not implement dynamic Gen3+ rate change until Phase 3.

---

## 11. Message bus / LPC (awareness only)

Later PIPE revisions add an 8-bit **Message Bus** (M2P / P2M) and **Low Pin Count** modes that move slow controls into registers (margining, some EQ, RxPolarity in LPC, etc.).

**Rivet Gen2 + PG239:** stick to **legacy pin-style** signals already on `rivet_pipe_if`. Do not plan Message Bus RTL for Phase 1–2. Gen4 margining / Gen3 EQ on AMD PHYs use **PG239 custom** EQ/assist ports, not standard PIPE Local FS/LF message-bus sequences.

---

## 12. Gen3+ equalization (defer)

From 8 GT/s up, EQ is an active MAC↔PHY dialogue (presets, FS/LF, coefficient iteration, Recovery.Equalization). MindShare covers message-bus EQ flows extensively.

**Rivet:** Phase 3+; use PG239 `txeq_*` / `rxeq_*` (AMD custom). Keep ports present, behavior idle in Gen2.

---

## 13. Mapping MindShare → Rivet files

| Concept | Rivet home |
|---------|------------|
| PIPE pins / packing | `rtl/interfaces/rivet_pipe_if.sv` |
| MAC LTSSM + OS + PIPE drive | `rtl/pcie_ctrl/mac/` — see [mac.md](mac.md) |
| PHY PCS/PMA (EB, 8b/10b) | `rivet_pcie_phy_*` → PG239 |
| Gen/width policy | [gen-evolution.md](gen-evolution.md) |
| User AXI-ST / cfg | PG213-style — **not** PIPE |

---

## 14. Verification hooks from these notes

1. PIPE agent must model **PhyStatus** handshakes for power/rate/detect.  
2. Scoreboard: illegal PowerDown/Detect/Idle combos → TB error.  
3. Monitor **RxStatus** SKP add/remove in L0; inject overflow → expect Recovery.  
4. Gen2 smoke: Detect (P1 + detect) → Polling/Config OS on `txdata`/`rxdata` → L0 with SKP cadence.  
5. Do **not** require Rivet MAC to implement SerDes EB or Message Bus for Gen2 green.

---

## Related docs

- [mac.md](mac.md) — MAC implementation follow-guide  
- [architecture.md](architecture.md) — stack boundaries  
- [gen-evolution.md](gen-evolution.md) — Gen2 vs Gen3/4 PIPE  
- [verification.md](verification.md) — UVM priority  
- Local: `specs/MindShare_PIPE_vC.2.pdf`, Intel PIPE 4.4.1 / 5.x / 6.0, PG239
