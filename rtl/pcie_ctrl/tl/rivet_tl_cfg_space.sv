// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PF0 Type 0 config space (4 KiB) shared by fabric Cfg TLPs and cfg_mgmt_*.

module rivet_tl_cfg_space (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Fabric DW access (from Cfg completer). One-cycle req; ack next cycle.
  input  logic        fab_req_i,
  input  logic        fab_write_i,
  input  logic [9:0]  fab_addr_i,
  input  logic [3:0]  fab_be_i,
  input  logic [31:0] fab_wdata_i,
  output logic [31:0] fab_rdata_o,
  output logic        fab_ack_o,
  output logic        fab_busy_o,

  // PG213 Table 26 cfg_mgmt (same clock domain for now)
  input  logic [9:0]  cfg_mgmt_addr_i,
  input  logic [7:0]  cfg_mgmt_function_number_i,
  input  logic        cfg_mgmt_write_i,
  input  logic [31:0] cfg_mgmt_write_data_i,
  input  logic [3:0]  cfg_mgmt_byte_enable_i,
  input  logic        cfg_mgmt_read_i,
  output logic [31:0] cfg_mgmt_read_data_o,
  output logic        cfg_mgmt_read_write_done_o,
  input  logic        cfg_mgmt_debug_access_i,

  // BAR0 decode for CQ routing
  output logic [31:0] bar0_base_o,
  output logic [31:0] bar0_mask_o,
  output logic        bar0_mem_en_o,
  output logic        bus_master_en_o,

  // MSI capability snapshot
  output logic        msi_enable_o,
  output logic [31:0] msi_addr_o,
  output logic [15:0] msi_data_o,

  // AER sticky inject into Device Status
  input  logic        aer_set_cor_i,
  input  logic        aer_set_nonfatal_i,

  // Link Status inject (negotiated)
  input  logic        link_up_i,
  input  logic [3:0]  link_speed_i,
  input  logic [5:0]  link_width_i
);

  import rivet_pkg::*;

  // Block RAM. A 1024:1 flip-flop mux does not close at Gen2 pclk.
  // Combo snapshots of the dwords the datapath reads every cycle live in
  // sh_* so those bits are not a RAM read.
  (* ram_style = "block" *) logic [31:0] mem_q [0:RIVET_CFG_DW_N-1];
  logic [31:0] ram_rdata_q;
  logic [9:0]  ram_raddr;
  logic        mem_we;
  logic [9:0]  mem_waddr;
  logic [31:0] mem_wdata;
  logic [31:0] dev_now_c;
  logic [9:0]  init_q;
  logic        init_done_q;
  logic [31:0] sh_cmd_q;
  logic [31:0] sh_bar0_q;
  logic [31:0] sh_msi_ctrl_q;
  logic [31:0] sh_msi_addr_q;
  logic [31:0] sh_msi_data_q;
  logic [31:0] sh_dev_q;
  logic [31:0] sh_link_q;

  function automatic logic [31:0] cfg_reset_dw(input logic [9:0] dw);
    unique case (dw)
      10'd0:  return {RIVET_CFG_DEVICE_ID, RIVET_CFG_VENDOR_ID};
      10'd1:  return 32'h0010_0000;
      10'd2:  return {RIVET_CFG_CLASS, RIVET_CFG_REV_ID};
      10'd11: return {RIVET_CFG_SUBSYS_ID, RIVET_CFG_SUBSYS_VEN};
      10'd13: return {24'h0, RIVET_CFG_CAP_PTR};
      10'd15: return 32'h0000_0100;
      10'd16: return {16'h0003, RIVET_CFG_MSI_OFF, 8'h01};
      10'd20: return {16'h0080, RIVET_CFG_PCIE_OFF, 8'h05};
      10'd28: return {16'h0002, 8'h00, 8'h10};
      10'd29: return {29'h0, RIVET_CFG_CMPS};
      10'd31: return {22'h0, RIVET_CFG_LINK_WIDTH_CAP, RIVET_CFG_LINK_SPEED_CAP};
      default: return 32'h0;
    endcase
  endfunction

  // -------------------------------------------------------------------------
  // Writable / W1C / BAR masks
  // -------------------------------------------------------------------------
  function automatic logic [31:0] bar_mask(input logic [9:0] dw);
    unique case (dw)
      10'd4:  return RIVET_CFG_BAR0_MASK;
      10'd5:  return RIVET_CFG_BAR1_MASK;
      10'd6:  return RIVET_CFG_BAR2_MASK;
      10'd7:  return RIVET_CFG_BAR3_MASK;
      10'd8:  return RIVET_CFG_BAR4_MASK;
      10'd9:  return RIVET_CFG_BAR5_MASK;
      10'd12: return RIVET_CFG_ROM_MASK;
      default: return 32'h0;
    endcase
  endfunction

  function automatic logic is_bar_dw(input logic [9:0] dw);
    return (dw >= 10'd4 && dw <= 10'd9) || (dw == 10'd12);
  endfunction

  // Bits software may write (before BAR sizing / W1C).
  function automatic logic [31:0] wr_mask(input logic [9:0] dw);
    unique case (dw)
      10'd1:  return 32'h0000_0547; // Command: IO/Mem/BM/Parity/SERR/IntDisable
      10'd3:  return 32'h0000_FF00; // Latency timer (Cache Line RO for EP smoke)
      10'd4, 10'd5, 10'd6, 10'd7, 10'd8, 10'd9, 10'd12:
              return 32'hFFFF_FFFF; // sized via bar_mask
      10'd15: return 32'h0000_00FF; // Interrupt Line
      10'd17: return 32'h0000_0003; // PMCSR power state (D0 only sticky)
      10'd20: return 32'h0071_0000; // MSI MsgCtrl: Enable + MME (CapID/Next RO)
      10'd21: return 32'hFFFF_FFFC; // MSI Message Address (dword aligned)
      10'd22: return 32'hFFFF_FFFF; // MSI addr hi
      10'd23: return 32'h0000_FFFF; // MSI data
      10'd30: return 32'h0000_7FFF; // Device Control (Status W1C overlay)
      10'd32: return 32'h0000_FFFF; // Link Control (Status is RO overlay)
      default: return 32'h0;
    endcase
  endfunction

  // Status register W1C bits in DW1[31:16]
  localparam logic [31:0] STATUS_W1C = 32'hF900_0000;

  function automatic logic [31:0] apply_write(
      input logic [9:0]  dw,
      input logic [31:0] cur,
      input logic [31:0] wdata,
      input logic [3:0]  be);
    logic [31:0] merged, masked, bm, wm;
    merged = cur;
    if (be[0]) merged[7:0]   = wdata[7:0];
    if (be[1]) merged[15:8]  = wdata[15:8];
    if (be[2]) merged[23:16] = wdata[23:16];
    if (be[3]) merged[31:24] = wdata[31:24];

    if (is_bar_dw(dw)) begin
      bm = bar_mask(dw);
      // Size probe / program: keep only mask bits (attrs in [3:0] stay 0 for Mem32).
      return merged & bm;
    end

    wm = wr_mask(dw);
    masked = (cur & ~wm) | (merged & wm);

    if (dw == 10'd1) begin
      // Status W1C in [31:16]
      masked[31:16] = cur[31:16] & ~(merged[31:16] & STATUS_W1C[31:16]);
      // Cap List always set
      masked[20] = 1'b1;
    end
    if (dw == 10'd32) begin
      // Preserve Link Status [31:16]; only Link Control writable
      masked[31:16] = cur[31:16];
    end
    if (dw == 10'd17) begin
      // Force D0
      masked[1:0] = 2'b00;
    end
    if (dw == 10'd30) begin
      // Device Status [19:16] W1C; preserve upper sticky RO overlay bits
      masked[31:16] = cur[31:16] & ~(merged[31:16] & 16'h000F);
    end
    return masked;
  endfunction

  // -------------------------------------------------------------------------
  // Arbitration: fabric beats cfg_mgmt when both request
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_FAB  = 2'd1,
    ST_MGMT = 2'd2
  } st_e;

  st_e          st_q;
  logic [9:0]   addr_q;
  logic         write_q;
  logic [3:0]   be_q;
  logic [31:0]  wdata_q;
  logic [31:0]  rdata_q;
  logic         fab_ack_q;
  logic         mgmt_done_q;
  logic         mgmt_pend_q;
  logic         mgmt_pf0_q;
  logic [9:0]   mgmt_addr_q;
  logic         mgmt_write_q;
  logic [3:0]   mgmt_be_q;
  logic [31:0]  mgmt_wdata_q;

  logic mgmt_pulse;
  assign mgmt_pulse = cfg_mgmt_read_i || cfg_mgmt_write_i;

  assign fab_busy_o = (st_q != ST_IDLE) || !init_done_q;
  assign fab_ack_o  = fab_ack_q;
  assign fab_rdata_o = rdata_q;
  assign cfg_mgmt_read_data_o       = rdata_q;
  assign cfg_mgmt_read_write_done_o = mgmt_done_q;

  assign bar0_base_o     = sh_bar0_q & RIVET_CFG_BAR0_MASK;
  assign bar0_mask_o     = RIVET_CFG_BAR0_MASK;
  assign bar0_mem_en_o   = sh_cmd_q[1]; // Command.Memory Space Enable
  assign bus_master_en_o = sh_cmd_q[2]; // Command.Bus Master Enable
  assign msi_enable_o    = sh_msi_ctrl_q[16]; // Message Control.MSI Enable
  assign msi_addr_o      = sh_msi_addr_q;
  assign msi_data_o      = sh_msi_data_q[15:0];

  // Live Link Status overlay on DW32
  logic [31:0] link_status_overlay;
  always_comb begin
    link_status_overlay = sh_link_q;
    if (link_up_i) begin
      link_status_overlay[19:16] = link_speed_i;
      link_status_overlay[25:20] = link_width_i;
    end
  end

  // Address presented this cycle; ram_rdata_q is that dword on the next.
  always_comb begin
    ram_raddr = addr_q;
    if (!init_done_q)
      ram_raddr = init_q;
    else if (st_q == ST_IDLE) begin
      if (fab_req_i)
        ram_raddr = fab_addr_i;
      else if (mgmt_pend_q || mgmt_pulse)
        ram_raddr = mgmt_pulse ? cfg_mgmt_addr_i : mgmt_addr_q;
    end
  end

  function automatic logic [31:0] snap_dw(
      input logic [9:0]  dw,
      input logic [31:0] dev_now);
    if (dw == 10'd32)
      return link_status_overlay;
    else if (dw == 10'd1)
      return sh_cmd_q;
    else if (dw == 10'd4)
      return sh_bar0_q;
    else if (dw == 10'd20)
      return sh_msi_ctrl_q;
    else if (dw == 10'd21)
      return sh_msi_addr_q;
    else if (dw == 10'd23)
      return sh_msi_data_q;
    else if (dw == 10'd30)
      return dev_now;
    else
      return ram_rdata_q;
  endfunction

  // Write port is its own clocked process so Vivado can infer block RAM.
  // An asynchronous reset on the same process keeps the array in flip-flops.
  always_comb begin
    dev_now_c = sh_dev_q;
    if (init_done_q && aer_set_cor_i)      dev_now_c[16] = 1'b1;
    if (init_done_q && aer_set_nonfatal_i) dev_now_c[17] = 1'b1;

    mem_we    = 1'b0;
    mem_waddr = init_q;
    mem_wdata = cfg_reset_dw(init_q);
    if (!init_done_q) begin
      mem_we = 1'b1;
    end else if (((st_q == ST_FAB) || ((st_q == ST_MGMT) && mgmt_pf0_q)) &&
                 write_q) begin
      mem_we    = 1'b1;
      mem_waddr = addr_q;
      mem_wdata = apply_write(addr_q,
                    (addr_q == 10'd30) ? dev_now_c : snap_dw(addr_q, sh_dev_q),
                    wdata_q, be_q);
    end else if (dev_now_c != sh_dev_q) begin
      mem_we    = 1'b1;
      mem_waddr = 10'd30;
      mem_wdata = dev_now_c;
    end
  end

  always_ff @(posedge clk_i) begin
    ram_rdata_q <= mem_q[ram_raddr];
    if (mem_we)
      mem_q[mem_waddr] <= mem_wdata;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q          <= ST_IDLE;
      addr_q        <= '0;
      write_q       <= 1'b0;
      be_q          <= '0;
      wdata_q       <= '0;
      rdata_q       <= '0;
      fab_ack_q     <= 1'b0;
      mgmt_done_q   <= 1'b0;
      mgmt_pend_q   <= 1'b0;
      mgmt_pf0_q    <= 1'b1;
      mgmt_addr_q   <= '0;
      mgmt_write_q  <= 1'b0;
      mgmt_be_q     <= '0;
      mgmt_wdata_q  <= '0;
      init_q        <= '0;
      init_done_q   <= 1'b0;
      sh_cmd_q      <= cfg_reset_dw(10'd1);
      sh_bar0_q     <= '0;
      sh_msi_ctrl_q <= cfg_reset_dw(10'd20);
      sh_msi_addr_q <= '0;
      sh_msi_data_q <= '0;
      sh_dev_q      <= '0;
      sh_link_q     <= '0;
    end else begin
      logic [31:0] cur;
      logic [31:0] nxt;
      sh_dev_q    <= dev_now_c;
      fab_ack_q   <= 1'b0;
      mgmt_done_q <= 1'b0;

      if (mgmt_pulse && !mgmt_pend_q) begin
        mgmt_pend_q  <= 1'b1;
        mgmt_pf0_q   <= (cfg_mgmt_function_number_i == 8'h00);
        mgmt_addr_q  <= cfg_mgmt_addr_i;
        mgmt_write_q <= cfg_mgmt_write_i;
        mgmt_be_q    <= cfg_mgmt_byte_enable_i;
        mgmt_wdata_q <= cfg_mgmt_write_data_i;
      end

      if (!init_done_q) begin
        // One dword per cycle after reset. fab_busy stays high until this ends.
        if (init_q == 10'(RIVET_CFG_DW_N - 1))
          init_done_q <= 1'b1;
        else
          init_q <= init_q + 10'd1;
      end else begin
        unique case (st_q)
          ST_IDLE: begin
            if (fab_req_i) begin
              addr_q  <= fab_addr_i;
              write_q <= fab_write_i;
              be_q    <= fab_be_i;
              wdata_q <= fab_wdata_i;
              st_q    <= ST_FAB;
            end else if (mgmt_pend_q || mgmt_pulse) begin
              addr_q  <= mgmt_pulse ? cfg_mgmt_addr_i : mgmt_addr_q;
              write_q <= mgmt_pulse ? cfg_mgmt_write_i : mgmt_write_q;
              be_q    <= mgmt_pulse ? cfg_mgmt_byte_enable_i : mgmt_be_q;
              wdata_q <= mgmt_pulse ? cfg_mgmt_write_data_i : mgmt_wdata_q;
              if (mgmt_pulse)
                mgmt_pf0_q <= (cfg_mgmt_function_number_i == 8'h00);
              st_q        <= ST_MGMT;
              mgmt_pend_q <= 1'b0;
            end
          end
          ST_FAB, ST_MGMT: begin
            if ((st_q == ST_MGMT) && !mgmt_pf0_q) begin
              rdata_q <= '0;
            end else begin
              cur = (addr_q == 10'd30) ? dev_now_c : snap_dw(addr_q, sh_dev_q);
              nxt = apply_write(addr_q, cur, wdata_q, be_q);
              rdata_q <= snap_dw(addr_q, sh_dev_q);
              if (write_q) begin
                if (addr_q == 10'd1)  sh_cmd_q      <= nxt;
                if (addr_q == 10'd4)  sh_bar0_q     <= nxt;
                if (addr_q == 10'd20) sh_msi_ctrl_q <= nxt;
                if (addr_q == 10'd21) sh_msi_addr_q <= nxt;
                if (addr_q == 10'd23) sh_msi_data_q <= nxt;
                if (addr_q == 10'd30) sh_dev_q      <= nxt;
                if (addr_q == 10'd32) sh_link_q     <= nxt;
              end
            end
            if (st_q == ST_FAB)
              fab_ack_q <= 1'b1;
            else
              mgmt_done_q <= 1'b1;
            st_q <= ST_IDLE;
          end
          default: st_q <= ST_IDLE;
        endcase
      end
    end
  end

  // Silence unused
  wire unused_dbg = cfg_mgmt_debug_access_i;

endmodule : rivet_tl_cfg_space
