# PG213-style user interface audit

This document tracks the user-facing contract of Rivet against AMD PG213 v1.3.
It is a derived compatibility checklist, not a replacement for PG213 or the PCIe
Base Specification.

## Scope and terminology

- PG213 describes a complete vendor PCIe hard IP (`TL + DLL + MAC + PHY`).
- Rivet's equivalent deliverable is the complete `rivet_pcie` (`rivet_pcie_ctrl`
  plus `rivet_pcie_phy_*`).
- `rivet_pcie_ctrl` ends at PIPE. PG239 supplies the FPGA PHY (`PCS + PMA`).
- "PG213-style" means compatible channel names and semantics. Rivet is **not yet
  pin-compatible** with PG213.
- Active scope is one Physical Function, Endpoint, Gen2, lanes x1/x2/x4.
  Multi-PF, SR-IOV/VF, Gen3/4, 512-bit straddling, and Root Port-only signals are
  tracked but are not Phase 1 implementation targets.

## Important findings

1. PG213 `tkeep` is **Dword-granular**: width is `AXI_DATA_WIDTH/32`. Rivet
   previously used byte-granular `DATA_WIDTH/8`; this audit corrected it.
2. The four AXI-ST channels alone are not a complete PG213-style user boundary.
   CQ NP credits, RQ tag/sequence feedback, configuration, interrupts, messages,
   flow-control visibility, reset/clock status, and FLR must also be accounted for.
3. Rivet uses PG213-style **`cfg_mgmt_*`** (Table 26) for configuration R/W —
   **no AXI-Lite** on the user boundary. Other dedicated `cfg_*` event/handshake
   ports remain required where pulse semantics cannot be polled.
4. PG213 `user_clk` and active-High `user_reset` are outputs of the complete hard
   IP. The current soft controller takes `user_clk` and active-Low `user_resetn`
   as inputs. The final `rivet_pcie` clock/reset ownership must be resolved when
   the real PG239 wrapper is integrated.

## AXI-ST packet channels

For 64/128/256-bit interfaces (PG213 Tables 9-16):

| Channel | Core direction | Required signals | PG213 `tuser` | Rivet |
|---------|----------------|------------------|----------------|-------|
| CQ | core -> application | `m_axis_cq_tdata`, `tuser`, `tlast`, `tkeep`, `tvalid`, `tready` | 88 | Present |
| CC | application -> core | `s_axis_cc_tdata`, `tuser`, `tlast`, `tkeep`, `tvalid`, `tready[3:0]` | 33 | Present |
| RQ | application -> core | `s_axis_rq_tdata`, `tuser`, `tlast`, `tkeep`, `tvalid`, `tready[3:0]` | 85-bit port; bits `[61:0]` defined, `[84:62]` reserved | Present |
| RC | core -> application | `m_axis_rc_tdata`, `tuser`, `tlast`, `tkeep`, `tvalid`, `tready` | 75 | Present |

Rivet supports 64-bit AXI-ST first. The 512-bit PG213 interface has different
`tuser` widths and straddling semantics and is deferred.

### AXI-ST sideband fields that UVM must model

- CQ: `first_be`, `last_be`, `byte_en`, `sop`, `discontinue`, TPH fields, parity.
- CC: `discontinue`, parity.
- RQ: `first_be`, `last_be`, `addr_offset`, `discontinue`, `tph_present`,
  `tph_type`, `tph_indirect_tag_en`, `tph_st_tag`, `seq_num`, parity.
- RC: `byte_en`, SOF/EOF indicators, `discontinue`, parity.

The packed fields stay in `tuser`; they are not separate top-level ports.

### Companion packet-flow ports

| Signals | Direction from core | Purpose | Current status |
|---------|---------------------|---------|----------------|
| `pcie_cq_np_req[1:0]` | input | Grant CQ Non-Posted delivery credits | Present (stub) |
| `pcie_cq_np_req_count[5:0]` | output | Current CQ NP credit count | Present (stub) |
| `pcie_rq_seq_num0[5:0]`, `pcie_rq_seq_num_vld0` | output | RQ ordering/progress feedback | Present (stub) |
| second sequence output | output | Multiple requests per cycle / wide interfaces | Deferred with wide/straddled AXI |
| `pcie_rq_tag0`, `pcie_rq_tag_vld0` | output | First core-managed NP request tag | Present (stub) |
| `pcie_rq_tag1`, `pcie_rq_tag_vld1` | output | Second core-managed NP request tag | Present (stub) |
| `pcie_rq_tag_av[3:0]` | output | Free requester tags | Present (stub) |
| `pcie_tfc_nph_av[3:0]`, `pcie_tfc_npd_av[3:0]` | output | NP header/data TX credit availability | Present (stub) |

These are dedicated handshakes/status ports, not substitutes for `cfg_mgmt`.

## Configuration and status inventory

### Power-management controls (PG213 Table 25)

- `cfg_pm_aspm_l1_entry_reject`
- `cfg_pm_aspm_tx_l0s_entry_disable`

Status: missing; defer until ASPM is implemented.

### Configuration management (Table 26)

- Inputs: `cfg_mgmt_addr[9:0]`, `cfg_mgmt_function_number[7:0]`,
  `cfg_mgmt_write`, `cfg_mgmt_write_data[31:0]`,
  `cfg_mgmt_byte_enable[3:0]`, `cfg_mgmt_read`, `cfg_mgmt_debug_access`
- Outputs: `cfg_mgmt_read_data[31:0]`, `cfg_mgmt_read_write_done`

Rivet decision: expose **`cfg_mgmt_*`** directly (present as stub). Config-space
atomicity and DW addressing follow PG213; `cfg_mgmt_debug_access` is a no-op in EP.

### Configuration/link status (Table 27)

Phase 1/2 status that must be directly visible as dedicated `cfg_*` ports:

- `cfg_phy_link_down`, `cfg_phy_link_status[1:0]`
- `cfg_negotiated_width[2:0]`, `cfg_current_speed[1:0]`
- `cfg_max_payload[1:0]`, `cfg_max_read_req[2:0]`
- `cfg_function_status[15:0]` (PF0 is bits `[3:0]`)
- `cfg_function_power_state[11:0]` (PF0 is bits `[2:0]`)
- `cfg_link_power_state[1:0]`
- `cfg_local_error_out[4:0]`, `cfg_local_error_valid`
- `cfg_rx_pm_state[1:0]`, `cfg_tx_pm_state[1:0]`
- `cfg_ltssm_state[5:0]`
- `cfg_rcb_status` (PF0 subset first)
- `cfg_dpa_substate_change`, `cfg_obff_enable`, `cfg_pl_status_change`
- `cfg_tph_requester_enable`, `cfg_tph_st_mode`

Rivet currently exposes only `link_up`; all detailed status is missing.
The final API should expose frequently sampled link state as dedicated PG213-style
`cfg_*` status ports (not via AXI-Lite).

Deferred status:

- `cfg_vf_status`, `cfg_vf_power_state`, `cfg_vf_tph_requester_enable`,
  `cfg_vf_tph_st_mode`: SR-IOV/VF phase.
- Root Port-only `cfg_pl_status_change`: inactive in the current EP phase.

## Message and flow-control interfaces

### Received messages (PG213 Tables 28-30)

- `cfg_msg_received`
- `cfg_msg_received_data[7:0]`
- `cfg_msg_received_type[4:0]`

### Transmit messages (Table 31)

- Inputs: `cfg_msg_transmit`, `cfg_msg_transmit_type[2:0]`,
  `cfg_msg_transmit_data[31:0]`
- Output: `cfg_msg_transmit_done`

Status: missing. Message events need a dedicated valid/data handshake
(`cfg_msg_*`); software retention can be layered outside the core.

### Flow-control visibility (Table 32)

- Outputs: `cfg_fc_ph[7:0]`, `cfg_fc_pd[11:0]`, `cfg_fc_nph[7:0]`,
  `cfg_fc_npd[11:0]`, `cfg_fc_cplh[7:0]`, `cfg_fc_cpld[11:0]`
- Input: `cfg_fc_sel[2:0]`

Status: missing. Required for verification and diagnostics; the internal DLL
credit model remains authoritative.

## Configuration control, reset, and errors

PG213 Table 33 contains both generally useful and mode/feature-specific signals.

### Gen2 EP baseline

- `cfg_hot_reset_out`
- `cfg_config_space_enable`
- `cfg_dsn[63:0]`
- `cfg_power_state_change_ack`
- `cfg_power_state_change_interrupt`
- `cfg_err_cor_in`, `cfg_err_uncor_in`
- `cfg_err_cor_out`, `cfg_err_nonfatal_out`, `cfg_err_fatal_out`
- `cfg_flr_done[3:0]`, `cfg_flr_in_process[3:0]` (PF0 first)
- `cfg_req_pm_transition_l23_ready`
- `cfg_link_training_enable`
- `cfg_bus_number[7:0]`
- identity values: `cfg_vend_id`, `cfg_subsys_vend_id`, `cfg_dev_id_pf0`,
  `cfg_rev_id_pf0`, `cfg_subsys_id_pf0`
- `cfg_ds_port_number[7:0]` (Link Capabilities Port Number; also relevant to EP)

Rivet decision:

- Static identity values should normally be parameters/initial config-space data,
  with optional `cfg_mgmt` override before enumeration where PG213 allows.
- Hot reset, power transition, errors, and FLR require event/handshake semantics;
  they cannot be represented only by passive status registers.
- Current implementation has none of these except the coarse `link_up`.

### Later modes/features

- `cfg_hot_reset_in`, downstream bus/device/function number: RC/DSP.
- PF1-PF3 identity/status/FLR: multi-PF.
- `cfg_vf_flr_done`, `cfg_vf_flr_func_num`, `cfg_vf_flr_in_process`: SR-IOV.

## Interrupt interfaces

### Legacy INTx (PG213 Table 34)

- Inputs: `cfg_interrupt_int[3:0]`, `cfg_interrupt_pending[3:0]`
- Output: `cfg_interrupt_sent`

### MSI (Table 35)

- Core status: `cfg_interrupt_msi_enable[3:0]`,
  `cfg_interrupt_msi_mmenable[11:0]`
- Request: `cfg_interrupt_msi_int[31:0]`,
  `cfg_interrupt_msi_function_number[7:0]`
- Completion: `cfg_interrupt_msi_sent`, `cfg_interrupt_msi_fail`
- Pending/mask: `cfg_interrupt_msi_pending_status`,
  `cfg_interrupt_msi_pending_status_function_num`,
  `cfg_interrupt_msi_pending_status_data_enable`,
  `cfg_interrupt_msi_mask_update`, `cfg_interrupt_msi_select`,
  `cfg_interrupt_msi_data`
- Attributes/TPH: `cfg_interrupt_msi_attr`,
  `cfg_interrupt_msi_tph_present`, `cfg_interrupt_msi_tph_type`,
  `cfg_interrupt_msi_tph_st_tag`

### MSI-X (Tables 36-37)

- Enable/mask status: `cfg_interrupt_msix_enable[3:0]`,
  `cfg_interrupt_msix_mask[3:0]`
- External table request: `cfg_interrupt_msix_address[63:0]`,
  `cfg_interrupt_msix_data[31:0]`, `cfg_interrupt_msix_int`
- Optional internal table/PBA: `cfg_interrupt_msix_vec_pending`,
  `cfg_interrupt_msix_vec_pending_status`
- VF enable/mask buses are deferred with SR-IOV.

Status: all interrupt groups are missing. Phase 2 should implement MSI first;
INTx and MSI-X remain explicit tracked groups, not accidental omissions.

## Extended configuration interface

PG213 Tables 38:

- Outputs: `cfg_ext_read_received`, `cfg_ext_write_received`,
  `cfg_ext_register_number[9:0]`, `cfg_ext_function_number[7:0]`,
  `cfg_ext_write_data[31:0]`, `cfg_ext_write_byte_enable[3:0]`
- Inputs: `cfg_ext_read_data[31:0]`, `cfg_ext_read_data_valid`

Rivet decision: use an internal config-space router; expose PG213
`cfg_ext_*` ports when extended config is implemented (no AXI-Lite bridge).

## Clock, reset, and physical boundary

PG213 Tables 39-40 include `user_clk`, active-High `user_reset`, `sys_clk`,
`sys_clk_gt`, active-low `sys_reset`, `phy_rdy_out`, and serial PCIe lanes.

Rivet mapping:

| PG213 | Rivet now | Required resolution |
|-------|-----------|---------------------|
| `user_lnk_up` | `link_up` | Equivalent coarse link indication; compatibility adapter can rename |
| `user_clk` core output | `user_clk` controller/top input | Full IP should derive/export the user clock from the PHY/clocking block |
| `user_reset` active-High output | `user_resetn` active-Low input | Define one canonical polarity and generate user reset inside full IP |
| `sys_clk`, `sys_clk_gt` | one `sys_clk` input | Real VCU118 wrapper must separate fabric and GT reference clock paths |
| `sys_reset` active-low | `sys_reset_n` | Semantically aligned |
| `phy_rdy_out` | absent | Add when real PG239 reset/clock FSM exists |
| serial lanes | present on `rivet_pcie` | Present |

These hard-IP clock directions are not copied blindly into `rivet_pcie_ctrl`;
the controller remains independently testable at user clock + PIPE.

## Implementation gates

### Before Phase 1 functional Gen2 RTL

- [x] Correct AXI-ST `tkeep` to Dword granularity.
- [x] Add CQ NP credit and RQ tag/sequence/credit companion ports (stub behavior).
- [ ] Define packed `tuser` types/bit positions in `rivet_pkg`.
- [ ] Bind all four AXI-ST channels and companion ports into UVM agents.
- [x] Replace AXI-Lite with PG213 `cfg_mgmt_*` ports (stub).
- [ ] Add canonical link/config status types and remaining `cfg_*` ports.

### Before Phase 2 functional endpoint

- [ ] Config-space management/status/control and identity.
- [ ] FLR and power-state handshakes.
- [ ] Message receive/transmit.
- [ ] MSI, then INTx/MSI-X according to enabled feature set.
- [ ] Flow-control observability.
- [ ] PG213 compatibility adapter if pin-level drop-in compatibility is desired.

### Explicitly deferred, not forgotten

- 512-bit AXI and straddling.
- Multi-PF and SR-IOV/VF buses.
- Root Port-only controls/status.
- Gen3/4-specific widths/features (tracked in `gen-evolution.md`).

## PG213 extract caveats and locked decisions

The local `specs/*.md` is auto-extracted from the PDF; some rows are ambiguous or
corrupted. Where PG213 text conflicts, Rivet locks the choice below (Chapter 3
Port Descriptions wins over migration/appendix tables).

| Topic | Conflict in extract | Rivet decision |
|-------|---------------------|----------------|
| `pcie_rq_tag0/1` width | Table 13 says 10, Table 21/App.A say 8 | Use **10** (non-512 Table 13); low bits used until wider tags needed |
| `pcie_rq_seq_num0` | Prose says `[3:0]`, port/tuser carry `[5:0]` | Port width **6**; `seq_num` sideband is 6 bits (`[27:24]`+`[61:60]`) |
| `cfg_local_error_out/valid` | Ch.3 = Output, App.A Table 102 = Input | Treat as **Output** (Ch.3) |
| `s_axis_cc_tready`, `s_axis_rq_tready` | 4-bit bus, all bits identical | Expose **[3:0]**; any bit is usable |
| `s_axis_rq_tuser` | 85-bit port, only `[61:0]` defined | Port **85**, `[84:62]` reserved / tie-0 |
| `user_lnk_up` | Missing from clock/reset Table 39; only prose/Tandem | Rivet uses `link_up`; alias `user_lnk_up` in a future PG213 adapter |
| `cfg_dpa_substate_change`, `cfg_ds_function_number` | In Ch.3 but "not available" in Table 104 | Treat as deprecated; do not rely on for new work |
| Name typos (`cfg_msg_data`, `cfg_mg_transmit`, `cfg_ext_wrte_data`, `cfg_vf_flr_runc_num`, `cfg_imterrupt_msi_int`) | PDF OCR/extraction noise | Use the corrected canonical names in this doc |

