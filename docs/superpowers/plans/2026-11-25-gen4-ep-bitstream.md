# Gen4 EP Bitstream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two Gen4 x4 Endpoint bitstreams, VCU118 then VMK180, from parameterized board projects.

**Architecture:** `rivet_tl_cq256` and `rivet_tl_cc256` pack the existing 64-bit CQ/CC fields into one 256-bit beat. The Gen4 shell uses `rivet_fpga_pio256` for one-DW BAR0 Mem32. Gen2 elaboration, the 64-bit PIO, and the no-argument Vivado project stay as they are. PG239 asks for 16.0 GT/s and PG345 asks for `link_speed 4`. A rejected setting stops the run.

**Tech Stack:** SystemVerilog, Verilator, Vivado Tcl, Windows `cmd` / PowerShell, and a bash queue for a Linux Vivado host.

## Global Constraints

- Images, in order: `fpga/vcu118/build/gen4_ep/rivet_vcu118_gen4_ep.bit`, then `fpga/vmk180/build/gen4_ep/rivet_vmk180_gen4_ep.bit`.
- Controller parameters for those images: `MODE=0`, `GEN=4`, `LANES=4`, `PIPE_DATA_WIDTH=64`, `AXI_DATA_WIDTH=256`, `SPEED_CHANGE_EN=1`, `LTSSM_TIMER_SCALE=1`, `N_TS1_POLLING=1024`.
- No-argument `create_project` still writes the Gen2 EP project in `fpga/<board>/build/`.
- The only new argument list is `4 ep`. Any other list, including one extra argument, exits non-zero before `create_project`.
- `AXI_DATA_WIDTH==64` keeps `rivet_tl_cq`, `rivet_tl_cc`, and `rivet_tl_pio_app`.
- 256-bit CQ MemRd is DESC0 at `[63:0]`, DESC1 at `[127:64]`, `tkeep=8'h0F`, `tlast=1`. MemWr 1DW adds `{32'h0, data}` at `[191:128]`, `tkeep=8'h3F`.
- 256-bit Cpl is D0 at `[63:0]`, D1 at `[127:64]`, `tkeep=8'h0F`. CplD adds `{32'h0, data}` at `[191:128]`, `tkeep=8'h3F`. The data dword is `[159:128]`.
- The 128-bit user port is unchanged. No 128-bit packer.
- PIO storage is 256 dwords. A CQ beat whose dword count is not 1, or whose type is not MemRd or MemWr, is consumed and produces no CC beat. MemWr is posted and also produces no CC beat.
- VCU118 LEDs stay `link_up`, PHY ready, heartbeat, `cfg_ltssm_state[4:0]`. VMK180 LEDs stay `link_up`, PHY ready, heartbeat, L0.
- `phy_userclk` stays 250 MHz. PHY data pins stay 64 bits per lane. At PIPE width 64 the pad is a copy.
- PG239 `phy_max_speed` `16.0_GT/s` and PG345 `link_speed 4` do not fall back to Gen2.
- Gen4 `phy_rate` must be three bits. A two-bit port stops the script before synthesis.
- Vendor IP, `.xpr`, and `.bit` stay gitignored.
- Gen3 bitstreams, RC, DSP, USP, requester MemWr, a config master, and Gen5 are out of scope.

## File map

| File | Responsibility |
|------|----------------|
| `rtl/pcie_ctrl/tl/rivet_tl_cq256.sv` | One 256-bit CQ beat from the 64-bit DLL byte stream |
| `rtl/pcie_ctrl/tl/rivet_tl_cc256.sv` | One 256-bit CC beat back to two 64-bit DLL beats |
| `fpga/common/rivet_fpga_pio256.sv` | Gen4 lab BAR0, one DW |
| `tb/fpga/rivet_tl_cq256_tb.sv` | CQ beat contract |
| `tb/fpga/rivet_tl_cc256_tb.sv` | CC beat contract |
| `tb/fpga/rivet_fpga_pio256_tb.sv` | Write then read one DW |
| `rtl/pcie_ctrl/rivet_pcie_ctrl.sv` | Select the 256-bit packers when `AXI_DATA_WIDTH>=256` |
| `rtl/filelist_core.f` | Compile the new packers |
| `rtl/phy/rivet_pcie_phy_wrap.sv` | `PHY_RATE_W` slice into `phy_rate` |
| `fpga/vcu118/rtl/rivet_vcu118_ep.sv` | `GEN` 2 or 4 shell |
| `fpga/vmk180/rtl/rivet_vmk180_ep.sv` | Same shell for VMK180 |
| `fpga/vcu118/*.tcl`, `fpga/vcu118/*.cmd` | Gen4 project, synth, bitstream |
| `fpga/vmk180/*.tcl`, `fpga/vmk180/*.cmd` | Same for VMK180 |
| `fpga/build_gen4_ep.ps1`, `fpga/build_gen4_ep.sh` | VCU118 then VMK180 |
| Board READMEs, `docs/hardware.md`, `docs/roadmap.md` | Say the lab image is Gen4 EP |

---

### Task 1: 256-bit CQ packer

**Files:**
- Create: `tb/fpga/rivet_tl_cq256_tb.sv`
- Create: `rtl/pcie_ctrl/tl/rivet_tl_cq256.sv`
- Test: `tb/fpga/rivet_tl_cq256_tb.sv`

**Interfaces:**
- Consumes: `rivet_pkg` (`RIVET_TLP_B0_MEMWR32`, `RIVET_TLP_B0_MEMRD32`, `rivet_tlp_len_dw`, `rivet_cq_tuser_pack`, `RIVET_CQ_REQ_MEMWR`, `RIVET_CQ_REQ_MEMRD`)
- Produces: `rivet_tl_cq256` with the same RX and sideband ports as `rivet_tl_cq`, and `m_axis_cq_tdata[255:0]`, `m_axis_cq_tkeep[7:0]`

- [ ] **Step 1: Write the failing test**

```systemverilog
// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
module rivet_tl_cq256_tb;
  import rivet_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_ni;
  logic [63:0] rx_tdata;
  logic        rx_tlast, rx_tvalid, rx_tready;
  logic [255:0] cq_tdata;
  logic [7:0]   cq_tkeep;
  logic         cq_tlast, cq_tvalid;
  logic         cq_tready;
  logic [87:0]  cq_tuser;

  rivet_tl_cq256 u (
    .clk_i(clk), .rst_ni(rst_ni),
    .rx_tdata_i(rx_tdata), .rx_tkeep_i(8'hFF),
    .rx_tlast_i(rx_tlast), .rx_tvalid_i(rx_tvalid), .rx_tready_o(rx_tready),
    .bar0_base_i(32'h0), .bar0_mask_i(32'hFFFF_F000), .bar0_mem_en_i(1'b1),
    .cq_np_req_i(2'b00), .cq_np_req_count_o(),
    .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
    .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
    .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser(cq_tuser),
    .rx_accept_o(), .rx_hdr0_o(), .rx_len_dw_o()
  );

  task automatic beat(input logic [63:0] data, input logic last);
    rx_tdata = data; rx_tlast = last; rx_tvalid = 1'b1;
    @(posedge clk);
    while (!rx_tready) @(posedge clk);
    rx_tvalid = 1'b0;
  endtask

  initial begin
    rst_ni = 0; rx_tvalid = 0; rx_tlast = 0; cq_tready = 1; rx_tdata = '0;
    repeat (4) @(posedge clk);
    rst_ni = 1;
    @(posedge clk);
    // MemWr32, len 1, req id 16'h0100, tag 8'hAB, fbe 4'hF
    beat(64'h0FAB_0100_0100_0040, 1'b0);
    // addr 32'h10 little-endian on the wire, data 32'hA1B2C3D4
    beat({32'hA1B2C3D4, 32'h1000_0000}, 1'b1);
    while (!cq_tvalid) @(posedge clk);
    if (cq_tdata[63:0] !== {32'h0, 32'h0000_0010}) $error("DESC0");
    if (cq_tdata[78:75] !== RIVET_CQ_REQ_MEMWR) $error("type");
    if (cq_tdata[73:64] !== 10'd1) $error("len");
    if (cq_tdata[111:96] !== 16'h0100) $error("req");
    if (cq_tdata[119:112] !== 8'hAB) $error("tag");
    if (cq_tdata[191:128] !== {32'h0, 32'hA1B2C3D4}) $error("data");
    if (cq_tkeep !== 8'h3F || cq_tlast !== 1'b1) $error("keep/last");
    @(posedge clk);
    if (cq_tvalid) $error("extra beat");
    $display("PASS: cq256 memwr");
    $finish;
  end
endmodule
```

DESC0 in `rivet_tl_cq` is `{addr_hi, addr_lo[31:2], 2'b00}`. For address `32'h10` and `addr_hi=0` that is `64'h0000_0010`. The test compares that value.

- [ ] **Step 2: Run the test and confirm it fails**

From the repo root, when `verilator` is on `PATH`:

```text
verilator --binary --timing +incdir+rtl/pcie_ctrl rtl/pcie_ctrl/rivet_pkg.sv rtl/pcie_ctrl/tl/rivet_tl_cq256.sv tb/fpga/rivet_tl_cq256_tb.sv --top-module rivet_tl_cq256_tb
```

When Verilator is only in WSL, map the drive the way `scripts/lint.ps1` does and run that command inside `wsl.exe -e bash -lc`.

Expected: FAIL because `rivet_tl_cq256` is not defined.

- [ ] **Step 3: Write the packer**

Create `rtl/pcie_ctrl/tl/rivet_tl_cq256.sv`. Copy the header parse from `rivet_tl_cq.sv` (`ST_IDLE`, `ST_HDR1`, `ST_HDR2`, `ST_DROP`, `le32`, `bar0_hit32`, the NP counter). Replace `ST_DESC0`, `ST_DESC1`, and `ST_DATA` with one state `ST_BEAT`. Every transition that used to enter `ST_DESC0` enters `ST_BEAT`.

AXI outputs while `st_q==ST_BEAT && np_ok`:

```systemverilog
assign m_axis_cq_tvalid = (st_q == ST_BEAT) && np_ok;
assign m_axis_cq_tlast  = 1'b1;
assign m_axis_cq_tkeep  = is_wr_q ? 8'h3F : 8'h0F;
assign m_axis_cq_tuser  = rivet_cq_tuser_pack(
    fbe_q, lbe_q, is_wr_q ? 32'h0000_000F : 32'h0, 1'b1, 1'b0);
assign m_axis_cq_tdata  = {64'h0,
                           is_wr_q ? {32'h0, data_q} : 64'h0,
                           {8'h00, tag_q, req_id_q, 17'h0, req_type_q, 1'b0, len_q},
                           {addr_hi_q, addr_lo_q[31:2], 2'b00}};
assign rx_tready_o = (st_q == ST_IDLE) || (st_q == ST_HDR1) ||
                     (st_q == ST_HDR2) || (st_q == ST_DROP);
assign rx_accept_o = (st_q == ST_BEAT) && m_axis_cq_tvalid && m_axis_cq_tready;
```

On a `ST_BEAT` handshake, set `have_data_q<=0` and `st_q<=ST_IDLE`. Decrement `np_cnt_q` on a read handshake the same way `rivet_tl_cq` decrements it on `ST_DESC0`. Ports other than the AXI data and keep buses match `rivet_tl_cq`. `m_axis_cq_tdata` is `[255:0]`. `m_axis_cq_tkeep` is `[7:0]`.

- [ ] **Step 4: Run the test and confirm it passes**

Same command as Step 2.

Expected: `PASS: cq256 memwr` and exit code 0.

- [ ] **Step 5: Commit**

```text
git add rtl/pcie_ctrl/tl/rivet_tl_cq256.sv tb/fpga/rivet_tl_cq256_tb.sv
git commit -m "feat(tl): pack Gen4 CQ into one 256-bit beat"
```

### Task 2: 256-bit CC unpacker

**Files:**
- Create: `tb/fpga/rivet_tl_cc256_tb.sv`
- Create: `rtl/pcie_ctrl/tl/rivet_tl_cc256.sv`

**Interfaces:**
- Consumes: the D0/D1 field offsets in `rivet_tl_cc` (`[6:0]`, `[27:16]`, `[41:32]`, `[45:43]`, D1 `[7:0]` tag, D1 `[31:16]` requester id)
- Produces: `rivet_tl_cc256`. User side is 256-bit data and 8-bit keep. DLL side stays 64-bit `tx_*`, two beats, matching the `tx_q` bytes built in `rivet_tl_cc` `ST_DAT`

- [ ] **Step 1: Write the failing test**

```systemverilog
// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
module rivet_tl_cc256_tb;
  import rivet_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_ni, cc_tvalid, cc_tready, cc_tlast, tx_tvalid, tx_tready, tx_tlast;
  logic [255:0] cc_tdata;
  logic [7:0] cc_tkeep;
  logic [63:0] tx_tdata;
  logic [7:0] tx_tkeep;

  rivet_tl_cc256 u (
    .clk_i(clk), .rst_ni(rst_ni),
    .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
    .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
    .s_axis_cc_tready(cc_tready), .s_axis_cc_tuser('0),
    .tx_tdata_o(tx_tdata), .tx_tkeep_o(tx_tkeep),
    .tx_tlast_o(tx_tlast), .tx_tvalid_o(tx_tvalid), .tx_tready_i(tx_tready),
    .tx_accept_o(), .tx_hdr0_o(), .tx_len_dw_o()
  );

  initial begin
    rst_ni = 0; cc_tvalid = 0; cc_tlast = 0; cc_tkeep = 0; cc_tdata = '0;
    tx_tready = 1;
    repeat (4) @(posedge clk);
    rst_ni = 1;
    @(posedge clk);
    // D0: lower_addr 7'h10, byte count 4, dword count 1, status SC
    cc_tdata[6:0] = 7'h10;
    cc_tdata[27:16] = 12'd4;
    cc_tdata[41:32] = 10'd1;
    cc_tdata[45:43] = 3'b000;
    cc_tdata[64 +: 8] = 8'hAB;
    cc_tdata[80 +: 16] = 16'h0100;
    cc_tdata[159:128] = 32'hA1B2C3D4;
    cc_tkeep = 8'h3F;
    cc_tlast = 1'b1;
    cc_tvalid = 1'b1;
    @(posedge clk);
    while (!cc_tready) @(posedge clk);
    cc_tvalid = 1'b0;
    while (!tx_tvalid) @(posedge clk);
    if (tx_tdata[7:0] !== RIVET_TLP_B0_CPLD) $error("cpld type");
    if (tx_tlast !== 1'b0) $error("first beat is not last");
    @(posedge clk);
    if (tx_tdata[7:0] !== 8'h00) $error("req id lo");
    if (tx_tdata[15:8] !== 8'h01) $error("req id hi");
    if (tx_tdata[23:16] !== 8'hAB) $error("tag");
    if (tx_tdata[39:32] !== 8'hD4) $error("data0");
    if (tx_tdata[63:56] !== 8'hA1) $error("data3");
    if (tx_tlast !== 1'b1) $error("eop");
    $display("PASS: cc256 cpld");
    $finish;
  end
endmodule
```

The expected second beat is the high half of `tx_q` in `rivet_tl_cc` `ST_DAT`: requester id little-endian, tag, `{1'b0, lower_addr}`, then the data dword little-endian. Requester id `16'h0100` is bytes `8'h00`, `8'h01`. Data `32'hA1B2C3D4` is bytes `D4 C3 B2 A1`.

- [ ] **Step 2: Run the test and confirm it fails**

```text
verilator --binary --timing +incdir+rtl/pcie_ctrl rtl/pcie_ctrl/rivet_pkg.sv rtl/pcie_ctrl/tl/rivet_tl_cc256.sv tb/fpga/rivet_tl_cc256_tb.sv --top-module rivet_tl_cc256_tb
```

Expected: FAIL because the module is missing.

- [ ] **Step 3: Write the unpacker**

`rivet_tl_cc256` accepts one user beat (`tready` high only in the idle state). It reads D0 from `[63:0]` and D1 from `[127:64]` with the offsets above. `has_data` is `s_axis_cc_tkeep[4]`. The data dword is `s_axis_cc_tdata[159:128]`. It then builds the same `tx_q[127:0]` assignment as `ST_DAT` in `rivet_tl_cc` when `has_data` is set, and the no-data `tx_q` assignment from `ST_D1` when `has_data` is clear. It shifts that 128-bit word out as two 64-bit beats: low half first with `tlast=0`, high half with `tlast=1`. `tx_tkeep` on the second beat is `8'hFF` when `has_data` and `8'h0F` otherwise, matching `rivet_tl_cc`.

- [ ] **Step 4: Run the test and confirm it passes**

Same command as Step 2. Expected: `PASS: cc256 cpld` and exit code 0.

- [ ] **Step 5: Commit**

```text
git add rtl/pcie_ctrl/tl/rivet_tl_cc256.sv tb/fpga/rivet_tl_cc256_tb.sv
git commit -m "feat(tl): unpack one 256-bit CC beat onto the DLL"
```

### Task 3: Select the wide packers in the controller

**Files:**
- Modify: `rtl/pcie_ctrl/rivet_pcie_ctrl.sv` (the `rivet_tl_cq` instance near line 441 and the `rivet_tl_cc` instance near line 532)
- Modify: `rtl/filelist_core.f` (insert the two new files after `rivet_tl_cq.sv` and `rivet_tl_cc.sv`)

**Interfaces:**
- Consumes: `rivet_tl_cq256`, `rivet_tl_cc256`
- Produces: `AXI_DATA_WIDTH>=256` elaborates those modules. `AXI_DATA_WIDTH==64` still elaborates `rivet_tl_cq` and `rivet_tl_cc`

- [ ] **Step 1: Add the files to the filelist**

After `rtl/pcie_ctrl/tl/rivet_tl_cq.sv`:

```text
rtl/pcie_ctrl/tl/rivet_tl_cq256.sv
```

After `rtl/pcie_ctrl/tl/rivet_tl_cc.sv`:

```text
rtl/pcie_ctrl/tl/rivet_tl_cc256.sv
```

- [ ] **Step 2: Generate the instances**

Wrap the existing `rivet_tl_cq u_tl_cq` instance:

```systemverilog
generate
  if (AXI_DATA_WIDTH >= 256) begin : g_cq256
    rivet_tl_cq256 u_tl_cq (
      // same named ports as today's rivet_tl_cq instance
    );
  end else begin : g_cq64
    rivet_tl_cq u_tl_cq (
      // the instance that is there today, unchanged
    );
  end
endgenerate
```

Do the same for `rivet_tl_cc`. In `g_cc256`, connect `s_axis_cc_tkeep` to `cc_p_tkeep` (8 bits). In `g_cc64`, keep today's `cc_p_tkeep[1:0]`.

- [ ] **Step 3: Lint Gen2 and Gen4**

```text
powershell -File scripts/lint.ps1
powershell -File scripts/lint.ps1 -Gen 4
```

Expected: both exit 0. If Verilator is missing even under WSL, say so in the commit message and do not treat that as a pass.

- [ ] **Step 4: Commit**

```text
git add rtl/pcie_ctrl/rivet_pcie_ctrl.sv rtl/filelist_core.f
git commit -m "feat(pcie): elaborate 256-bit CQ and CC at Gen4"
```

### Task 4: Gen4 lab PIO

**Files:**
- Create: `fpga/common/rivet_fpga_pio256.sv`
- Create: `tb/fpga/rivet_fpga_pio256_tb.sv`

**Interfaces:**
- Consumes: the CQ/CC beat layout from Tasks 1 and 2, `rivet_cc_tuser_pack`
- Produces: `rivet_fpga_pio256` with `PIO_N=256`, 256-bit CQ in, 256-bit CC out, `s_axis_cc_tready[3:0]`

- [ ] **Step 1: Write the failing test**

```systemverilog
// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
module rivet_fpga_pio256_tb;
  import rivet_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_ni, cq_tvalid, cq_tready, cq_tlast, cc_tvalid, cc_tlast;
  logic [255:0] cq_tdata, cc_tdata;
  logic [7:0] cq_tkeep, cc_tkeep;
  logic [3:0] cc_tready;

  rivet_fpga_pio256 u (
    .clk_i(clk), .rst_ni(rst_ni),
    .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
    .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
    .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser('0),
    .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
    .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
    .s_axis_cc_tready(cc_tready), .s_axis_cc_tuser()
  );

  task automatic cq(input logic wr, input logic [31:0] addr,
                    input logic [31:0] data, input logic [9:0] len);
    cq_tdata = '0;
    cq_tdata[31:2] = addr[31:2];
    cq_tdata[73:64] = len;
    cq_tdata[78:75] = wr ? RIVET_CQ_REQ_MEMWR : RIVET_CQ_REQ_MEMRD;
    cq_tdata[111:96] = 16'h0100;
    cq_tdata[119:112] = 8'h11;
    cq_tdata[159:128] = data;
    cq_tkeep = wr ? 8'h3F : 8'h0F;
    cq_tlast = 1'b1;
    cq_tvalid = 1'b1;
    @(posedge clk);
    while (!cq_tready) @(posedge clk);
    cq_tvalid = 1'b0;
  endtask

  initial begin
    rst_ni = 0; cq_tvalid = 0; cc_tready = 4'hF; cq_tdata = '0;
    repeat (4) @(posedge clk);
    rst_ni = 1;
    repeat (300) @(posedge clk);
    cq(1'b1, 32'h0000_0010, 32'hA1B2C3D4, 10'd1);
    repeat (4) @(posedge clk);
    if (cc_tvalid) $error("posted write completed");
    cq(1'b0, 32'h0000_0010, 32'h0, 10'd1);
    while (!cc_tvalid) @(posedge clk);
    if (cc_tdata[159:128] !== 32'hA1B2C3D4) $error("read data");
    if (cc_tkeep !== 8'h3F || cc_tlast !== 1'b1) $error("cpld shape");
    if (cc_tdata[45:43] !== 3'b000) $error("status");
    @(posedge clk);
    cq(1'b0, 32'h0000_0020, 32'h0, 10'd2);
    repeat (8) @(posedge clk);
    if (cc_tvalid) $error("multi-DW produced a completion");
    $display("PASS: pio256");
    $finish;
  end
endmodule
```

- [ ] **Step 2: Run the test and confirm it fails**

```text
verilator --binary --timing +incdir+rtl/pcie_ctrl rtl/pcie_ctrl/rivet_pkg.sv fpga/common/rivet_fpga_pio256.sv tb/fpga/rivet_fpga_pio256_tb.sv --top-module rivet_fpga_pio256_tb
```

Expected: FAIL because the module is missing.

- [ ] **Step 3: Write the PIO**

`rivet_fpga_pio256` uses the same block-RAM init as `rivet_tl_pio_app`: `PIO_N=256`, `ram_style="block"`, no reset on the RAM write, `pio_ready` rises after `PIO_N` writes of zero. Until `pio_ready`, `m_axis_cq_tready` is 0.

On one CQ beat with `len==1` and type MemWr, write `tdata[159:128]` to `pio_q[addr[2 +: PIO_AW]]` and return to idle with `s_axis_cc_tvalid=0`.

On one CQ beat with `len==1` and type MemRd, wait one clock so the registered RAM read is valid, then drive one CC beat:

```systemverilog
s_axis_cc_tdata = '0;
s_axis_cc_tdata[6:0]   = addr_q[6:0];
s_axis_cc_tdata[27:16] = 12'd4;
s_axis_cc_tdata[41:32] = 10'd1;
s_axis_cc_tdata[45:43] = 3'b000;
s_axis_cc_tdata[71:64] = tag_q;
s_axis_cc_tdata[95:80] = req_id_q;
s_axis_cc_tdata[127:112] = 16'h0100;
s_axis_cc_tdata[191:128] = {32'h0, pio_rd_q};
s_axis_cc_tkeep = 8'h3F;
s_axis_cc_tlast = 1'b1;
s_axis_cc_tuser = rivet_cc_tuser_pack(1'b0);
```

Any other beat is accepted and produces no CC beat. `s_axis_cc_tready[0]` is the handshake bit, matching `rivet_tl_pio_app`.

- [ ] **Step 4: Run the test and confirm it passes**

Same command as Step 2. Expected: `PASS: pio256` and exit code 0.

- [ ] **Step 5: Commit**

```text
git add fpga/common/rivet_fpga_pio256.sv tb/fpga/rivet_fpga_pio256_tb.sv
git commit -m "feat(fpga): add the Gen4 one-DW BAR0 PIO"
```

### Task 5: Parameterize both board shells

**Files:**
- Modify: `fpga/vcu118/rtl/rivet_vcu118_ep.sv`
- Modify: `fpga/vmk180/rtl/rivet_vmk180_ep.sv`

**Interfaces:**
- Consumes: `rivet_fpga_pio256`, `rivet_tl_pio_app`, `rivet_pcie_phy_wrap`
- Produces: module parameters `GEN` (default 2) and `PHY_RATE_W` (default 2). `GEN==4` sets PIPE width 64 and AXI width 256

- [ ] **Step 1: Change the VCU118 header**

Replace `module rivet_vcu118_ep (` with:

```systemverilog
module rivet_vcu118_ep #(
  parameter int unsigned GEN         = 2,
  parameter int unsigned PHY_RATE_W  = 2
) (
```

Replace `localparam int unsigned PIPE_DATA_WIDTH = 16;` with:

```systemverilog
localparam int unsigned PIPE_DATA_WIDTH = (GEN == 4) ? 64 : 16;
localparam int unsigned AXI_DATA_WIDTH  = (GEN == 4) ? 256 : 64;
localparam int unsigned AXI_KEEP_WIDTH  = AXI_DATA_WIDTH / 32;
```

Replace `logic [63:0] cq_tdata, cc_tdata;` and `logic [1:0] cq_tkeep, cc_tkeep;` with vectors of `AXI_DATA_WIDTH` and `AXI_KEEP_WIDTH`.

Pass `.PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)` and `.PHY_RATE_W(PHY_RATE_W)` into `rivet_pcie_phy_wrap`. Pass `.GEN(GEN)`, `.PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)`, and `.AXI_DATA_WIDTH(AXI_DATA_WIDTH)` into `rivet_pcie_ctrl`. Leave `MODE`, `SPEED_CHANGE_EN`, `LTSSM_TIMER_SCALE`, and `N_TS1_POLLING` as they are.

Replace the single `rivet_tl_pio_app u_pio` with:

```systemverilog
generate
  if (GEN == 4) begin : g_pio256
    rivet_fpga_pio256 u_pio (
      .clk_i(user_clk), .rst_ni(sys_rst_n & phy_ready),
      .m_axis_cq_tdata(cq_tdata), .m_axis_cq_tkeep(cq_tkeep),
      .m_axis_cq_tlast(cq_tlast), .m_axis_cq_tvalid(cq_tvalid),
      .m_axis_cq_tready(cq_tready), .m_axis_cq_tuser(cq_tuser),
      .s_axis_cc_tdata(cc_tdata), .s_axis_cc_tkeep(cc_tkeep),
      .s_axis_cc_tlast(cc_tlast), .s_axis_cc_tvalid(cc_tvalid),
      .s_axis_cc_tready(cc_tready), .s_axis_cc_tuser(cc_tuser)
    );
  end else begin : g_pio64
    rivet_tl_pio_app u_pio (
      // today's port list
    );
  end
endgenerate
```

- [ ] **Step 2: Apply the same parameters on VMK180**

In `rivet_vmk180_ep`, add the same two parameters and the same localparams, wire widths, controller parameters, wrap `PHY_RATE_W`, and PIO generate. The wrap `BOARD` stays `RIVET_BOARD_VMK180`.

- [ ] **Step 3: Lint Gen2**

```text
powershell -File scripts/lint.ps1
```

Expected: exit 0. The board tops are not in that filelist. This step checks the controller default did not move.

- [ ] **Step 4: Commit**

```text
git add fpga/vcu118/rtl/rivet_vcu118_ep.sv fpga/vmk180/rtl/rivet_vmk180_ep.sv
git commit -m "feat(fpga): parameterize the EP shells for Gen4"
```

### Task 6: Three-bit PIPE rate on the VCU118 PHY port

**Files:**
- Modify: `rtl/phy/rivet_pcie_phy_wrap.sv`

**Interfaces:**
- Consumes: `pipe_rate[2:0]`
- Produces: parameter `PHY_RATE_W` default 2. The PG239 instance connects `.phy_rate(pipe_rate[PHY_RATE_W-1:0])`

- [ ] **Step 1: Add the parameter**

Next to `PIPE_DATA_WIDTH`:

```systemverilog
parameter int unsigned PHY_RATE_W = 2
```

Replace the VCU118 `.phy_rate (pipe_rate[1:0])` with:

```systemverilog
.phy_rate (pipe_rate[PHY_RATE_W-1:0])
```

Leave the VMK180 `.phy_rate (pipe_rate)` connection as it is. Default `PHY_RATE_W=2` keeps the Gen2 PG239 port two bits wide.

- [ ] **Step 2: Commit**

```text
git add rtl/phy/rivet_pcie_phy_wrap.sv
git commit -m "feat(phy): drive a selectable PG239 rate width"
```

### Task 7: VCU118 project arguments

**Files:**
- Modify: `fpga/vcu118/create_project.tcl`
- Modify: `fpga/vcu118/create_project.cmd`
- Modify: `fpga/vcu118/synth.tcl`
- Modify: `fpga/vcu118/synth.cmd`
- Modify: `fpga/vcu118/impl.tcl`
- Modify: `fpga/vcu118/impl.cmd`

**Interfaces:**
- Consumes: the shell parameters from Task 5
- Produces: `4 ep` builds `fpga/vcu118/build/gen4_ep/rivet_vcu118.xpr` and `rivet_vcu118_gen4_ep.bit`. No arguments keep `fpga/vcu118/build/rivet_vcu118.xpr`

- [ ] **Step 1: Reject bad arguments before Vivado**

In `create_project.cmd`, `synth.cmd`, and `impl.cmd`, replace the usage check so it runs before the Vivado search:

```bat
if "%~1"=="" (
  set "RIVET_TCLARGS="
) else if /I "%~1"=="4" if /I "%~2"=="ep" if "%~3"=="" (
  set "RIVET_TCLARGS=4 ep"
) else (
  echo Usage: %SELF% [4 ep]
  exit /b 1
)
```

Pass `-tclargs %RIVET_TCLARGS%` only when `RIVET_TCLARGS` is set. `create_project.cmd synth` is no longer accepted; `synth.cmd` is the synth entry.

- [ ] **Step 2: Point Tcl at the Gen4 directory**

At the top of each Tcl file, after `script_dir`:

```tcl
set gen4 0
if {[info exists argv] && [llength $argv] == 2 &&
    [lindex $argv 0] eq "4" && [lindex $argv 1] eq "ep"} {
  set gen4 1
} elseif {[info exists argv] && [llength $argv] != 0} {
  error "usage: no arguments, or: 4 ep"
}
set build_dir [file join $script_dir build [expr {$gen4 ? "gen4_ep" : ""}]]
```

`create_project.tcl` already has `build_dir`. Replace that assignment with this block. Keep the direct `vivado -tclargs synth` path only when `gen4` is 0, so the old one-shot Gen2 synth still works for a raw Vivado call. `synth.tcl` and `impl.tcl` open `[file join $build_dir rivet_vcu118.xpr]`.

- [ ] **Step 3: Ask PG239 for 16.0 GT/s and check the ports**

When `gen4` is 1, `rivet_try_ip_config` of `phy_max_speed` uses `16.0_GT/s`. When it returns 0, `error` after the helper has printed the legal values. When `gen4` is 0, keep `5.0_GT/s`. Keep `phy_userclk_freq` at `250_MHz`.

Add `fpga/common/rivet_fpga_pio256.sv` with `add_files`.

After `generate_target`, glob `*.v` under the generated IP directory. The first `phy_txdata` declaration must be `[63:0]` or `[255:0]`. The first `phy_rate` declaration on a Gen4 run must be `[2:0]`. Any other width is `error` and synthesis is not started. On that successful Gen4 check:

```tcl
set_property generic {GEN=4 PHY_RATE_W=3} [current_fileset]
```

`impl.tcl`, when `gen4` is 1, after progress is `100%`, copies the `impl_1` `.bit` to `fpga/vcu118/build/gen4_ep/rivet_vcu118_gen4_ep.bit`. A negative WNS still errors, as it does today.

- [ ] **Step 4: Check the argument gate without Vivado**

```text
fpga\vcu118\create_project.cmd 3 ep
echo %ERRORLEVEL%
fpga\vcu118\create_project.cmd 4 rc
echo %ERRORLEVEL%
fpga\vcu118\create_project.cmd 4
echo %ERRORLEVEL%
```

Expected: each command prints `Usage` and `ERRORLEVEL` is 1. Vivado is not started.

- [ ] **Step 5: Commit**

```text
git add fpga/vcu118/create_project.tcl fpga/vcu118/create_project.cmd fpga/vcu118/synth.tcl fpga/vcu118/synth.cmd fpga/vcu118/impl.tcl fpga/vcu118/impl.cmd
git commit -m "build(vcu118): add a Gen4 EP project argument"
```

### Task 8: VMK180 project arguments

**Files:**
- Modify: `fpga/vmk180/create_project.tcl`
- Modify: `fpga/vmk180/create_project.cmd`
- Modify: `fpga/vmk180/synth.tcl`
- Modify: `fpga/vmk180/synth.cmd`
- Modify: `fpga/vmk180/impl.tcl`
- Modify: `fpga/vmk180/impl.cmd`

**Interfaces:**
- Consumes: `rivet_automate` in `fpga/vmk180/create_project.tcl`
- Produces: `fpga/vmk180/build/gen4_ep/rivet_vmk180_gen4_ep.bit`

- [ ] **Step 1: Use the same argument gate as Task 7**

The three `.cmd` files accept only no arguments or `4 ep`, and they check that before searching for Vivado. Tcl `build_dir` gains `gen4_ep` the same way. The project file is `rivet_vmk180.xpr`. The bitstream copy target is `rivet_vmk180_gen4_ep.bit`.

- [ ] **Step 2: Pass link_speed 4**

Change `rivet_automate` so the config string uses a `link_speed` variable. Gen2 sets that variable to 2 and keeps today's fallback when the explicit config is rejected. Gen4 sets it to 4. If that call fails, `error` and do not call `apply_bd_automation` without a config.

After generation, apply the same `phy_txdata` / `phy_rate` width check as Task 7. On success:

```tcl
set_property generic {GEN=4 PHY_RATE_W=3} [current_fileset]
```

Add `fpga/common/rivet_fpga_pio256.sv` to the project.

- [ ] **Step 3: Check the argument gate**

```text
fpga\vmk180\create_project.cmd 3 ep
echo %ERRORLEVEL%
```

Expected: `Usage` and `ERRORLEVEL` 1.

- [ ] **Step 4: Commit**

```text
git add fpga/vmk180/create_project.tcl fpga/vmk180/create_project.cmd fpga/vmk180/synth.tcl fpga/vmk180/synth.cmd fpga/vmk180/impl.tcl fpga/vmk180/impl.cmd
git commit -m "build(vmk180): add a Gen4 EP project argument"
```

### Task 9: Build queue

**Files:**
- Create: `fpga/build_gen4_ep.ps1`
- Create: `fpga/build_gen4_ep.sh`

**Interfaces:**
- Consumes: the `4 ep` commands from Tasks 7 and 8
- Produces: a dry run that prints four lines, VCU118 before VMK180, and a real run that stops on the first non-zero exit

- [ ] **Step 1: Write the PowerShell queue**

```powershell
# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
param([switch]$DryRun)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
$steps = @(
  "fpga\vcu118\create_project.cmd 4 ep",
  "fpga\vcu118\impl.cmd 4 ep",
  "fpga\vmk180\create_project.cmd 4 ep",
  "fpga\vmk180\impl.cmd 4 ep"
)
foreach ($step in $steps) {
  Write-Output $step
  if (-not $DryRun) {
    cmd.exe /c $step
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
}
```

- [ ] **Step 2: Write the shell queue**

```bash
#!/usr/bin/env bash
# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
steps=(
  "fpga/vcu118/create_project.cmd 4 ep"
  "fpga/vcu118/impl.cmd 4 ep"
  "fpga/vmk180/create_project.cmd 4 ep"
  "fpga/vmk180/impl.cmd 4 ep"
)
dry=0
if [[ "${1:-}" == "--dry-run" ]]; then dry=1; fi
if [[ "${1:-}" != "" && "${1:-}" != "--dry-run" ]]; then
  echo "Usage: fpga/build_gen4_ep.sh [--dry-run]" >&2
  exit 1
fi
for step in "${steps[@]}"; do
  printf '%s\n' "$step"
  if [[ "$dry" -eq 0 ]]; then
    # shellcheck disable=SC2086
    cmd.exe /c $step
  fi
done
```

On a Linux host, `cmd.exe` is absent. If `command -v cmd.exe` fails and this is not a dry run, print `vivado.bat not found` plus the search hint from `create_project.cmd` (`VIVADO_PATH`, `XILINX_VIVADO`, `PATH`, `C:\Xilinx\Vivado`, `Program Files\Xilinx\Vivado`) and exit 1. Then, still in that branch, call `vivado -mode batch -source` on `fpga/vcu118/create_project.tcl -tclargs 4 ep`, `fpga/vcu118/impl.tcl -tclargs 4 ep`, and the two VMK180 twins, in that order, when `vivado` is on `PATH`. A missing `vivado` uses the same error text and exits 1.

- [ ] **Step 3: Run the dry checks**

```text
powershell -File fpga/build_gen4_ep.ps1 -DryRun
bash fpga/build_gen4_ep.sh --dry-run
```

Expected: both print the four `4 ep` lines with both VCU118 lines before either VMK180 line, and both exit 0.

- [ ] **Step 4: Commit**

```text
git add fpga/build_gen4_ep.ps1 fpga/build_gen4_ep.sh
git commit -m "build(fpga): queue the two Gen4 EP bitstreams"
```

### Task 10: Docs

**Files:**
- Modify: `fpga/vcu118/README.md` (the Gen2-only bitstream sentence)
- Modify: `fpga/vmk180/README.md` (the same sentence)
- Modify: `docs/hardware.md` (the sentence that Gen3/Gen4 stay simulation-only)
- Modify: `docs/roadmap.md` (the FPGA-lab backlog bullet)

- [ ] **Step 1: Replace the bitstream sentences**

In `fpga/vcu118/README.md`, replace the sentence that says the bitstream stays Gen2 with:

```markdown
No arguments still generate PG239 at Gen2 x4 into `fpga/vcu118/build/`. `create_project.cmd 4 ep` generates PG239 at 16.0 GT/s into `fpga/vcu118/build/gen4_ep/` and the bitstream is `rivet_vcu118_gen4_ep.bit`. Gen3, RC, DSP, and USP images are a later plan. The vendor netlist is not in git.
```

In `fpga/vmk180/README.md`, use the same paragraph with PG345, `link_speed 4`, `fpga/vmk180/build/gen4_ep/`, and `rivet_vmk180_gen4_ep.bit`.

In `docs/hardware.md`, state that the no-argument project is still Gen2 x4 and that `fpga/build_gen4_ep.ps1` is the Gen4 EP x4 lab image for both kits. Leave the kit table's Gen2 row in place and add a Gen4 EP row for the `4 ep` command.

In `docs/roadmap.md`, under the FPGA-lab backlog, add that the Gen4 EP x4 project scripts exist for VCU118 and VMK180, and that Gen3 and the other port roles remain later work. Do not mark the lab phase closed.

- [ ] **Step 2: Commit**

```text
git add fpga/vcu118/README.md fpga/vmk180/README.md docs/hardware.md docs/roadmap.md
git commit -m "docs(fpga): describe the Gen4 EP bitstream command"
```

### Task 11: Produce the bitstreams when Vivado is present

**Files:**
- The scripts from Tasks 7 through 9. This task does not add a source file.

- [ ] **Step 1: Run the queue**

```text
powershell -File fpga/build_gen4_ep.ps1
```

Expected when Vivado and both device licenses are installed: the log contains `PASS: bitstream timing closed` twice, and these files exist:

- `fpga/vcu118/build/gen4_ep/rivet_vcu118_gen4_ep.bit`
- `fpga/vmk180/build/gen4_ep/rivet_vmk180_gen4_ep.bit`

Expected when Vivado is missing: the process prints the Vivado search path and exits non-zero. Do not invent a bitstream. Record "bitstream deferred — Vivado not installed" in the commit message only if a source file also changed; this task has nothing to commit when the tools are missing.

Expected when a license or a PHY enum is rejected: the queue stops on that image. Fix the enum only by using a value the script printed as legal, then rerun. Do not fall back to 5.0 GT/s or `link_speed 2`.

Programming the card and watching `link_up` is not a gate.

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| Two bitstreams, VCU118 then VMK180 | 9, 11 |
| Gen2 no-arg project preserved | 5, 7, 8 |
| `4 ep` only | 7, 8 |
| Controller parameters | 5 |
| 256-bit CQ/CC field layout | 1, 2, 3 |
| 64-bit path unchanged | 3 |
| Lab PIO, 256 dwords, drop other beats | 4 |
| LEDs unchanged | 5 (no LED assign is edited) |
| PG239 16.0 GT/s, PG345 link_speed 4, no fallback | 7, 8 |
| 64-bit PHY data, 3-bit rate | 6, 7, 8 |
| Dry run and bad-arg exits | 7, 8, 9 |
| Verilator PIO test and Gen4 lint | 3, 4 |
| Docs | 10 |
| Board `link_up` not a gate | 11 |
