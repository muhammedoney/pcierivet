# Gen2 Upstream / Downstream and Root Port — design

**Date:** 2026-11-23
**Status:** Accepted direction. Implementation follows
[the plan](superpowers/plans/2026-11-23-gen2-up-dp-rc.md), one slice at a time.
**Active generation stays Gen2.** The Gen3 EP procedure in
[2026-11-23-gen3-ep.md](superpowers/plans/2026-11-23-gen3-ep.md) waits until this
design's four slices are closed.

## Decision

Finish the port-role axis on the Gen2 link that already passes, then open
Gen3. Four `MODE` values are two ports:

| Port | `MODE` | Trains as | Config header |
|------|--------|-----------|---------------|
| Upstream | `RIVET_MODE_EP` (0), `RIVET_MODE_USP` (2) | Adopts Link# / Lane# | Type 0 |
| Downstream | `RIVET_MODE_RC` (1), `RIVET_MODE_DSP` (3) | Offers Link# `8'h00`, assigns Lane# 0..n-1 | Type 1 |

`RC` adds a requester that emits Type 1 CfgRd/CfgWr. `USP` is the Upstream
config path with no extra transaction engine. `DSP` is the Downstream config
path with no extra transaction engine. Switch forwarding (USP and DSP in one
design, TLP routing between them) is not this design.

## Why this order

Gen2 EP simulation is closed (roadmap Phase 1 and Phase 2). The next cut that
changes the encoding is 128b/130b plus Recovery.Equalization. Equalization is
not symmetric: the Downstream port is the master and the Upstream port is the
slave. `rivet_ltssm` can already offer a link number when `MODE` is RC or DSP,
but it still *enters* Hot Reset and Disabled because it *received* those
training-control bits. That is the Upstream reaction. Building Gen3
equalization on that machine would implement only the slave side.

The Gen2 MAC, DLL, and the four AXI-ST channels stay. Port type changes
LTSSM polarity, the config file, and who creates a Config TLP.

## What the tree already locks

Reviewed: `docs/roadmap.md`, `docs/architecture.md`, `docs/mac.md`,
`docs/dll.md`, `docs/pg213-interface.md`, `docs/gen-evolution.md`,
`docs/verification.md`, `rtl/pcie_ctrl/mac/rivet_ltssm.sv`,
`rtl/pcie_ctrl/tl/rivet_tl_cfg.sv`, `rtl/pcie_ctrl/tl/rivet_tl_cfg_space.sv`,
`rtl/pcie_ctrl/tl/rivet_tl_rx_route.sv`, `rtl/pcie_ctrl/tl/rivet_tl_rq.sv`,
`tb/uvm/rivet_tb_top.sv`.

- Default DUT is `rivet_pcie_ctrl` with `.MODE(0)` in `rivet_tb_top.sv`.
  Lane width is already a compile define (`RIVET_TB_LANES`). Mode is not.
- `IS_DOWNSTREAM` in `rivet_ltssm` is RC or DSP. Linkwidth.Start offers
  `DP_LINK_NUM = 8'h00`. Linkwidth.Accept assigns sequential lane numbers.
  Upstream adopts the partner's numbers and may set `lane_reversed`.
- Hot Reset (`6'h27`) and Disabled (`6'h20`) are entered from
  Recovery.RcvrLock / RcvrCfg when `rx_train_ctrl` has bit 0 or bit 1
  (`RIVET_TS_TC_HOT_RESET`, `RIVET_TS_TC_DISABLE`). The UVM peer sets those
  bits. There is no local request to *send* them.
- `rivet_tl_cfg` completes only `RIVET_TLP_B0_CFGRD0` (`8'h04`) and
  `RIVET_TLP_B0_CFGWR0` (`8'h44`). Type 1 byte0 values are absent.
- `rivet_tl_cfg_space` reset image is Type 0: class `24'h120000`, six BAR
  slots, no bus numbers, no windows. Header type dword is left 0, which is
  Type 0.
- `rivet_tl_rq` packs Mem32/Mem64 from descriptor DW2[14:11]
  (`RIVET_CQ_REQ_MEMWR` and the read default). It does not emit a Config TLP.
- `rivet_tl_rx_route` sends CfgRd0/CfgWr0 to the local completer, memory and
  IO and Msg to CQ, completions to RC.
- User ports stay CQ/CC/RQ/RC plus `cfg_mgmt`. PG213 already uses that set
  for a root port: RQ carries the request the CPU side sends down the link,
  RC carries the completion that comes back, CQ/CC serve requests that
  arrive from the link. No new user bus.
- Public PG213 requester request-type codes (descriptor bits [78:75], which
  this core already reads as DW2[14:11]):

  | Code | Request |
  |------|---------|
  | `4'b0000` | Memory Read |
  | `4'b0001` | Memory Write |
  | `4'b0010` | I/O Read |
  | `4'b0011` | I/O Write |
  | `4'b1000` | Type 0 Configuration Read (requester side) |
  | `4'b1001` | Type 1 Configuration Read (requester side) |
  | `4'b1010` | Type 0 Configuration Write (requester side) |
  | `4'b1011` | Type 1 Configuration Write (requester side) |

  A configuration descriptor uses bits [7:2] as the register number, [11:8]
  as the extended register number, and [119:104] as the completer ID
  (bus, device, function). A configuration read is the 16-byte descriptor
  only. A configuration write appends one dword of payload.

- Pipe encoding, rate, and width stay Gen2: 8b/10b, 16 bits/lane, 5.0 GT/s
  after Recovery.Speed. `GEN != 1` and `GEN != 2` remains an elaboration error.

## Gaps this design closes

1. A Downstream DUT cannot be elaborated in the UVM top. The peer always
   behaves as the Downstream partner of an Endpoint.
2. A Downstream port cannot start Hot Reset or Link Disable. It can only
   echo a bit it received, then fall back to Detect on the 2 ms timer.
   For the port that owns the link, Disabled holds until software clears it.
3. Config space has no Type 1 image: header type `8'h01`, class `24'h060400`,
   two BARs, primary/secondary/subordinate bus, I/O and memory windows,
   Bridge Control.
4. The requester cannot send Type 1 CfgRd1 (`8'h05`) or CfgWr1 (`8'h45`),
   and the route block would treat those byte0 values as a drop.
5. USP and DSP are legal `MODE` values in the LTSSM check and share the
   port polarity, but nothing proves they train or that their config header
   matches the port.

## Slices

Each slice keeps every current Gen2 EP smoke green. New tests are ×4.
×1 and ×2 stay legal elaborations; they are not new gates in this design.

### Slice 1 — Downstream LTSSM polarity

Goal: `MODE=RC`, Gen2 ×4, reaches L0 against the PG213 Endpoint model
(`xilinx_pcie4_uscale_ep`), then can originate Hot Reset and Link Disable.
The UVM PIPE peer stays the Downstream partner of Rivet Endpoint tests.

Behavior locked here:

- Upstream (EP, USP) keeps today's entries: received Hot Reset bit →
  `RIVET_LTSSM_HOT_RESET` → timer → Detect; received Disable bit →
  `RIVET_LTSSM_DISABLED` → EIOS → Electrical Idle → timer → Detect.
- Downstream (RC, DSP) does not take those entries from `rx_train_ctrl`.
  A level `hot_reset_req_i` sampled in L0 moves through Recovery into
  `RIVET_LTSSM_HOT_RESET` and transmits training-control bit 0. When the
  request drops and the timer has been entered, go to Detect and retrain.
- A level `link_disable_req_i` sampled in L0 moves through Recovery,
  transmits training-control bit 1, then `RIVET_LTSSM_DISABLED`. Stay there
  while the request is high. When it falls, go to Detect and retrain.
- Requests are TB-forced the same way `aspm_l0s_req` is forced today
  (`rivet_link_status_if` + `force` in `rivet_tb_top`). Slice 2 connects
  Link Disable to the Type 1 Link Control bit. Slice 1 does not invent a
  new user port beyond the status-interface bit.
- `cfg_hot_reset_in` is the PG213 name for the root-port request. Slice 1
  may add it as a controller input tied to the same LTSSM request, default
  0, so the force target is a real port. EP builds leave it at 0.

Gate:

- `ltssm_l0_gen2_rc_x4` reaches L0, `negotiated_width=4`, link number 0.
- `smoke_dp_hot_reset_gen2_x4` sees `cfg_ltssm_state == 6'h27` with the
  Hot Reset bit set on the transmitted TS, then L0 again.
- `smoke_dp_disable_gen2_x4` sees `6'h20` and stays there until the request
  drops, then L0.
- Existing `ltssm_l0_gen2_x4`, `smoke_hot_reset_gen2_x4`, and
  `smoke_disabled_gen2_x4` still pass with `MODE=0`.

### Slice 2 — Type 1 config space

Goal: RC and DSP present a PCI-PCI bridge header. EP and USP keep the
current Type 0 image byte for byte.

Type 1 dwords (byte offsets / 4). Unlisted dwords stay 0 except the
capability chain, which is copied from the Type 0 image (PM at `8'h40`,
MSI at `8'h50`, PCIe at `8'h70`).

| DW | Offset | Reset value | Software write mask |
|----|--------|-------------|---------------------|
| 0 | `0x00` | `{device, vendor}` same IDs as Type 0 | none |
| 1 | `0x04` | `32'h0010_0000` (Status bit 20, Cap List) | Command `32'h0000_0547` |
| 2 | `0x08` | `{24'h060400, rev}` | none |
| 3 | `0x0C` | header type `8'h01` in byte 2 (bits [23:16]) | none in this slice |
| 4 | `0x10` | BAR0, mask `RIVET_CFG_BAR0_MASK` | BAR sizing |
| 5 | `0x14` | BAR1, mask 0 | BAR sizing |
| 6 | `0x18` | primary `8'h00`, secondary `8'h01`, subordinate `8'h01`, sec. latency 0 | all four bytes |
| 7 | `0x1C` | I/O base/limit 0 | base and limit bytes |
| 8 | `0x20` | memory base/limit 0 | both 16-bit fields, bits [3:0] hard-wired 0 |
| 9 | `0x24` | prefetch base/limit 0 | same as memory |
| 10–12 | `0x28`–`0x30` | prefetch/I/O upper 32/16 | full dword |
| 13 | `0x34` | cap pointer `8'h40` | none |
| 14 | `0x38` | expansion ROM 0 | ROM mask (0 in this slice) |
| 15 | `0x3C` | interrupt line/pin 0, Bridge Control 0 | interrupt line; Bridge Control secondary-bus reset bit 6 only |

`rivet_tl_cfg` on a Downstream port completes Type 0 config only when the
TLP's bus number equals the primary bus (the port's own header). Every
other CfgRd0/CfgWr0/CfgRd1/CfgWr1 is not a local completion. Slice 2 does
not forward them; the completer UR-completes a config TLP that is not for
this port's primary bus, with status `3'b001` (Unsupported Request). Slice 3
replaces that UR with forwarding for Type 1 TLPs generated by the
requester. Fabric-received Type 1 TLPs are not forwarded in this design
(no switch).

`cfg_mgmt` reads and writes the same file. The existing
`smoke_cfg_mgmt_gen2_x4` stays on EP and must still see class `24'h120000`
and header type 0.

Gate: `smoke_cfg_type1_gen2_rc_x4` reads header type 1, class `060400`,
writes secondary bus `8'h05`, reads it back. EP `smoke_cfg_mgmt_gen2_x4`
unchanged.

### Slice 3 — Root-port requester

Goal: an RC user sends one Type 1 config write and one Type 1 config read
across the link. The Upstream peer completes them. The completion returns
on RC.

Locked for the first gate (one dword, no extended register, tag supplied
by the client the same way MemRd tags work today):

- RQ descriptor `req_type == 4'b1011` → wire byte0 `8'h45` (CfgWr1).
- RQ descriptor `req_type == 4'b1001` → wire byte0 `8'h05` (CfgRd1).
- Completer ID descriptor bits [119:104] become the config TLP's bus /
  device / function. Register number bits [7:2] and extended register
  bits [11:8] become the last header dword.
- CfgWr1 carries the one payload dword that follows the 16-byte descriptor.
  CfgRd1 has no payload beat.
- `rivet_tl_rx_route` sends CfgRd1/CfgWr1 to RC only when `MODE` is RC
  (they are completions? no). Outbound Type 1 is generated by RQ, not
  received. Inbound completions stay on RC. An inbound CfgRd0/CfgWr0
  whose bus matches primary bus still goes to the local completer.
- The peer in this test is an Upstream config completer: it accepts one
  CfgWr1, stores the dword, and returns Cpl / CplD for CfgRd1. It is not
  a second Rivet Endpoint. A loopback of two Rivet controllers is out of
  scope.
- Type 0 requester codes `4'b1000` and `4'b1010` are decoded and rejected
  with `rq_tready` low and no TLP until a later slice. The RC gate uses
  Type 1 only. Emitting Type 0 at an EP is how a link partner is
  enumerated after the first bridge; that is the slice after this gate,
  still inside Slice 3 if the Type 1 test is green: one extra test
  `smoke_cfg_type0_req_gen2_rc_x4` that emits CfgRd0 (`8'h04`) when
  `req_type == 4'b1000`.

Gate: `smoke_rc_cfg_gen2_x4` writes `32'hA5A5_0001` through CfgWr1 and
reads it back through CfgRd1 on the RC channel. Zero `uvm_error`.
EP `smoke_tlp_rq_memwr_gen2_x4` and `smoke_tlp_rq_rc_gen2_x4` still pass.

### Slice 4 — USP and DSP aliases

Goal: prove the two aliases are the two ports, not two new stacks.

- `MODE=USP` trains to L0 against the existing Downstream peer
  (`ltssm_l0_gen2_usp_x4`) and `cfg_mgmt` reads header type 0.
- `MODE=DSP` trains to L0 against the Upstream peer from Slice 1
  (`ltssm_l0_gen2_dsp_x4`) and `cfg_mgmt` reads header type 1.
- DSP does not grow an RQ config master. A CfgWr1 descriptor on a DSP
  build produces no TLP (ready stays low). RC is the only mode that
  emits config requests in this design.
- No crosslink, no loopback states (`6'h21`–`6'h26`), no peer-to-peer
  bridge forward.

## Out of scope

- Gen3/Gen4 protocol, 128b/130b, equalization, `PIPE_DATA_WIDTH != 16`.
- Switch forwarding, multi-function, SR-IOV, FLR, INTx.
- A second Rivet controller as the link partner.
- FPGA bitstream and PG239 generation.
- Changing AXI-ST data width (stays 64).
- Pasting PCIe Base or PG213 text into the tree. Codes above are the
  values already used, or the public PG213 request-type table the RQ
  descriptor already indexes.

## Docs already moved

`docs/roadmap.md` Phase 3 is these four slices. EP Gen3 is Phase 4 and
keeps `docs/gen-evolution.md` as its procedure. The Gen3 plan file stays,
with a deferral line at the top, so an agent does not start it while this
design is active. This file lives at `docs/gen2-port-roles.md` because
`specs/` is gitignored.
