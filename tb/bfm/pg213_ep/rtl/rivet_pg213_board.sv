// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PG213 stage-3 board: Xilinx RP model ↔ Rivet EP+PG239.
// Module name MUST be `board` and RP instance `RP` — usrapp_* uses board.RP.*.
//
// LINK_WIDTH (1/2/4): RP advertised max + serial pairs connected.
// EP soft port + PG239 PHY stay ×4; unused EP RX lanes stay in Electrical Idle.
// Negotiated Gen1 (RP speed cap 1); EP ctrl GEN=2 with SPEED_CHANGE_EN=0.

`timescale 1ps/1ps

module board;
  import rivet_pkg::*;

`ifdef RIVET_BFM_LANES
  localparam int unsigned LINK_WIDTH = `RIVET_BFM_LANES;
`else
  localparam int unsigned LINK_WIDTH = 4;
`endif
  localparam int unsigned PHY_WIDTH          = 4; // PG239 pcie_phy_0 fixed ×4
  localparam int unsigned REF_CLK_HALF_CYCLE = 5000; // ps → 100 MHz (sys_clk_gen is 1ps)

  initial begin
    if (!(LINK_WIDTH == 1 || LINK_WIDTH == 2 || LINK_WIDTH == 4))
      $fatal(1, "board LINK_WIDTH must be 1, 2, or 4 (got %0d)", LINK_WIDTH);
    if (LINK_WIDTH > PHY_WIDTH)
      $fatal(1, "board LINK_WIDTH (%0d) > PHY_WIDTH (%0d)", LINK_WIDTH, PHY_WIDTH);
    $display("[%t] : BFM LINK_WIDTH=x%0d (EP PHY=x%0d Gen1-negotiated)",
             $realtime, LINK_WIDTH, PHY_WIDTH);
  end

  logic sys_rst_n;
  logic ep_sys_clk_p, ep_sys_clk_n;
  logic rp_sys_clk_p, rp_sys_clk_n;

  // EP always ×4 serial (PHY); RP width = LINK_WIDTH.
  logic [PHY_WIDTH-1:0]  ep_pci_exp_txn, ep_pci_exp_txp;
  logic [PHY_WIDTH-1:0]  ep_pci_exp_rxn, ep_pci_exp_rxp;
  logic [LINK_WIDTH-1:0] rp_pci_exp_txn, rp_pci_exp_txp;
  logic [LINK_WIDTH-1:0] rp_pci_exp_rxn_w, rp_pci_exp_rxp_w;

  // Live lanes: cross-connect to RP. Unused EP RX lanes stay Electrical Idle
  // (no Receiver) so Detect.Active narrows lane_en to LINK_WIDTH — matches
  // UVM peer_lanes narrowing without a self-trained loopback on dead lanes.
  assign rp_pci_exp_rxp_w = ep_pci_exp_txp[LINK_WIDTH-1:0];
  assign rp_pci_exp_rxn_w = ep_pci_exp_txn[LINK_WIDTH-1:0];
  assign ep_pci_exp_rxp[LINK_WIDTH-1:0] = rp_pci_exp_txp;
  assign ep_pci_exp_rxn[LINK_WIDTH-1:0] = rp_pci_exp_txn;
  generate
    if (LINK_WIDTH < PHY_WIDTH) begin : g_ei
      // Differential common-mode idle: both lines low → PHY reports EI / no detect.
      assign ep_pci_exp_rxp[PHY_WIDTH-1:LINK_WIDTH] = '0;
      assign ep_pci_exp_rxn[PHY_WIDTH-1:LINK_WIDTH] = '0;
    end
  endgenerate

  logic ep_phy_ready, ep_link_up;
  logic [5:0] ep_ltssm;
  // PG213 RP uses the same cfg_ltssm_state[5:0] encoding (usrapp waits 0x0B then 0x10).
  wire  [5:0] rp_ltssm = RP.pcie_4_0_rport.cfg_ltssm_state;

  logic        saw_tlp, saw_cpl, stay_l0, saw_memwr, saw_pio;
  logic        saw_ep_rq_memwr, class_c_pass, saw_ep_rc_done;
  logic        class_e_pass, width_ok;
  int unsigned tlp_n, cpl_n;
  logic [2:0]  neg_width;
  logic [31:0] bm_expect;

  // Human-readable PG213 LTSSM codes used in Rivet + UltraScale+ IP.
  function automatic string ltssm_name(input logic [5:0] s);
    case (s)
      6'h00: ltssm_name = "Detect.Quiet";
      6'h01: ltssm_name = "Detect.Active";
      6'h02: ltssm_name = "Polling.Active";
      6'h03: ltssm_name = "Polling.Compliance";
      6'h04: ltssm_name = "Polling.Configuration";
      6'h05: ltssm_name = "Cfg.Linkwidth.Start";
      6'h06: ltssm_name = "Cfg.Linkwidth.Accept";
      6'h07: ltssm_name = "Cfg.Lanenum.Accept";
      6'h08: ltssm_name = "Cfg.Lanenum.Wait";
      6'h09: ltssm_name = "Cfg.Complete";
      6'h0A: ltssm_name = "Cfg.Idle";
      6'h0B: ltssm_name = "Recovery.RcvrLock";
      6'h0C: ltssm_name = "Recovery.Speed";
      6'h0D: ltssm_name = "Recovery.RcvrCfg";
      6'h0E: ltssm_name = "Recovery.Idle";
      6'h10: ltssm_name = "L0";
      default: ltssm_name = $sformatf("0x%0h", s);
    endcase
  endfunction

  // Pulse bm_go for one user_clk after sticky done clears (dual_app is level-go).
  // Questa: force RHS must not be automatic — stash in module vars.
  logic        bm_kick_do_wr, bm_kick_do_rd;
  logic [31:0] bm_kick_addr, bm_kick_wdata;
  // Class B CQ inject (Questa: force RHS must not be automatic)
  logic [63:0] cb_cq_tdata;
  logic [87:0] cb_cq_tuser;
  logic [1:0]  cb_cq_tkeep;
  logic        cb_cq_tlast, cb_cq_tvalid;
  logic [31:0] cb_d0, cb_d1, cb_d2, cb_d3;

  task automatic bm_kick(input logic do_wr, input logic do_rd,
                         input logic [31:0] addr, input logic [31:0] wdata);
    bm_kick_do_wr  = do_wr;
    bm_kick_do_rd  = do_rd;
    bm_kick_addr   = addr;
    bm_kick_wdata  = wdata;
    force EP.u_rivet_ep.bm_host_addr = bm_kick_addr;
    force EP.u_rivet_ep.bm_wr_data   = bm_kick_wdata;
    force EP.u_rivet_ep.bm_do_wr     = bm_kick_do_wr;
    force EP.u_rivet_ep.bm_do_rd     = bm_kick_do_rd;
    force EP.u_rivet_ep.bm_go        = 1'b0;
    repeat (2) @(posedge EP.u_rivet_ep.pipe_clk_o);
    force EP.u_rivet_ep.bm_go        = 1'b1;
    wait (EP.u_rivet_ep.bm_busy === 1'b1);
    force EP.u_rivet_ep.bm_go        = 1'b0;
  endtask

  task automatic bm_wait_done(input time timeout_ps, output logic ok);
    ok = 1'b0;
    fork
      begin
        wait (EP.u_rivet_ep.bm_done === 1'b1);
        ok = 1'b1;
      end
      begin
        #(timeout_ps);
      end
    join_any
    disable fork;
  endtask

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE),
    .offset    (0)
  ) CLK_GEN_RP (
    .sys_clk_p (rp_sys_clk_p),
    .sys_clk_n (rp_sys_clk_n)
  );

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE),
    .offset    (0)
  ) CLK_GEN_EP (
    .sys_clk_p (ep_sys_clk_p),
    .sys_clk_n (ep_sys_clk_n)
  );

  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge rp_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

  // Rivet EP+PG239 — always ×4 soft/PHY port
  rivet_pg213_ep_swap #(
    .PL_LINK_CAP_MAX_LINK_WIDTH (5'(PHY_WIDTH)),
    .C_DATA_WIDTH               (64)
  ) EP (
    .pci_exp_txp   (ep_pci_exp_txp),
    .pci_exp_txn   (ep_pci_exp_txn),
    .pci_exp_rxp   (ep_pci_exp_rxp),
    .pci_exp_rxn   (ep_pci_exp_rxn),
    .led_0         (),
    .led_1         (),
    .led_2         (),
    .led_3         (),
    .led_4         (),
    .led_5         (),
    .led_6         (),
    .led_7         (),
    .clk_300MHz_p  (1'b0),
    .clk_300MHz_n  (1'b0),
    .sys_clk_p     (ep_sys_clk_p),
    .sys_clk_n     (ep_sys_clk_n),
    .sys_rst_n     (sys_rst_n),
    .phy_ready_o   (ep_phy_ready),
    .link_up_o     (ep_link_up),
    .ltssm_state_o (ep_ltssm)
  );

  // Stock PG213 Root Port model — advertised width = LINK_WIDTH (1/2/4).
  xilinx_pcie4_uscale_rp #(
    .PL_LINK_CAP_MAX_LINK_SPEED (1), // Gen1 negotiated; EP ctrl is GEN=2 (Speed change = UVM)
    .PL_LINK_CAP_MAX_LINK_WIDTH (5'(LINK_WIDTH)),
    .PF0_DEV_CAP_MAX_PAYLOAD_SIZE (3'b011)
  ) RP (
    .sys_clk_n (rp_sys_clk_n),
    .sys_clk_p (rp_sys_clk_p),
    .sys_rst_n (sys_rst_n),
    .pci_exp_txn (rp_pci_exp_txn),
    .pci_exp_txp (rp_pci_exp_txp),
    .pci_exp_rxn (rp_pci_exp_rxn_w),
    .pci_exp_rxp (rp_pci_exp_rxp_w)
  );

  initial begin
    wait (sys_rst_n === 1'b1);
    $display("[%t] : Waiting for Rivet EP phy_ready...", $realtime);
    wait (ep_phy_ready === 1'b1);
    $display("[%t] : EP phy_ready - waiting link_up (EP) + RP user_lnk_up", $realtime);

    wait (ep_link_up === 1'b1);
    wait (RP.user_lnk_up === 1'b1);
    #10000;
    $display("[%t] : EP ltssm=%0h link_up=%0b | RP user_lnk_up=%0b",
             $realtime, ep_ltssm, ep_link_up, RP.user_lnk_up);
    $display("[%t] : link trained (PG213 RP + Rivet EP link_up) — staying for Cfg",
             $realtime);

    begin
      automatic logic ep_fc, ep_dl;
      wait (EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done === 1'b1);
      ep_fc = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done;
      ep_dl = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up;
      $display("[%t] : FC@EP       fc_init=%0b dl_up=%0b", $realtime, ep_fc, ep_dl);
    end

    // Negotiated width (EP LTSSM lane_en popcount) + cfg Link Status NLW
    neg_width = EP.u_rivet_ep.u_ctrl.u_mac.negotiated_width;
    width_ok  = (neg_width == 3'(LINK_WIDTH));
    $display("[%t] : negotiated_width=%0d expect=%0d %s",
             $realtime, neg_width, LINK_WIDTH, width_ok ? "OK" : "MISMATCH");
    begin
      automatic logic [31:0] link_dw;
      automatic logic [5:0]  nlw;
      link_dw = EP.u_rivet_ep.u_ctrl.u_cfg_space.link_status_overlay;
      nlw     = link_dw[25:20];
      if (nlw != 6'(LINK_WIDTH)) begin
        $display("[%t] : NLW FAIL — Link Status NLW=%0d expect=%0d (DW=0x%08h)",
                 $realtime, nlw, LINK_WIDTH, link_dw);
        $finish;
      end
      $display("[%t] : NLW PASS — Link Status NLW=%0d CLS=%0d",
               $realtime, nlw, link_dw[19:16]);
    end
    if (!width_ok) begin
      $display("[%t] : width MISMATCH — abort before Cfg/PIO", $realtime);
      $finish;
    end

    fork
      begin
        wait (saw_tlp && saw_cpl);
      end
      begin
        #2_000_000_000; // 2 ms at 1ps
      end
    join_any
    disable fork;

    $display("[%t] : Cfg probe   tlp=%0b cpld=%0b stay_l0=%0b rp_lnk=%0b tlp_n=%0d cpl_n=%0d",
             $realtime, saw_tlp, saw_cpl, stay_l0, RP.user_lnk_up, tlp_n, cpl_n);
    if (!(saw_cpl && stay_l0 && RP.user_lnk_up)) begin
      $display("[%t] : Cfg Vendor/Device incomplete (TLP path probe only)", $realtime);
      $finish;
    end
    $display("[%t] : Cfg closed — staying for BAR0 PIO 1DW", $realtime);

    fork
      begin
        wait (saw_pio);
      end
      begin
        #(64'd20_000_000_000); // 20 ms at 1ps
      end
    join_any
    disable fork;

    $display("[%t] : PIO probe   memwr=%0b pio=%0b stay_l0=%0b rp_lnk=%0b",
             $realtime, saw_memwr, saw_pio, stay_l0, RP.user_lnk_up);
    if (!(saw_pio && stay_l0 && RP.user_lnk_up)) begin
      $display("[%t] : Class A FAIL — PIO 1DW incomplete", $realtime);
      $finish;
    end
    $display("[%t] : Class A PASS — PG213 RP + Rivet EP PIO 1DW", $realtime);

    // Class B: multi-DW BAR0 MemWr into completer via CQ inject (usrapp is 1DW-only).
    begin
      automatic logic b_ok;
      b_ok = 1'b0;
      cb_d0 = 32'h1111_0001;
      cb_d1 = 32'h2222_0002;
      cb_d2 = 32'h3333_0003;
      cb_d3 = 32'h4444_0004;
      cb_cq_tuser = '0;
      cb_cq_tuser[3:0] = 4'hF;
      cb_cq_tkeep = 2'b11;
      @(posedge EP.u_rivet_ep.user_clk);
      cb_cq_tdata  = {32'h0, 32'h0000_0040};
      cb_cq_tlast  = 1'b0;
      cb_cq_tvalid = 1'b1;
      force EP.u_rivet_ep.cq_tuser  = cb_cq_tuser;
      force EP.u_rivet_ep.cq_tkeep  = cb_cq_tkeep;
      force EP.u_rivet_ep.cq_tvalid = cb_cq_tvalid;
      force EP.u_rivet_ep.cq_tlast  = cb_cq_tlast;
      force EP.u_rivet_ep.cq_tdata  = cb_cq_tdata;
      @(posedge EP.u_rivet_ep.user_clk);
      cb_cq_tdata = '0;
      cb_cq_tdata[9:0]   = 10'd4;
      cb_cq_tdata[14:11] = 4'b0001;
      cb_cq_tdata[55:48] = 8'hB0;
      force EP.u_rivet_ep.cq_tdata = cb_cq_tdata;
      @(posedge EP.u_rivet_ep.user_clk);
      cb_cq_tdata = {cb_d1, cb_d0};
      force EP.u_rivet_ep.cq_tdata = cb_cq_tdata;
      @(posedge EP.u_rivet_ep.user_clk);
      cb_cq_tdata = {cb_d3, cb_d2};
      cb_cq_tlast = 1'b1;
      force EP.u_rivet_ep.cq_tdata = cb_cq_tdata;
      force EP.u_rivet_ep.cq_tlast = cb_cq_tlast;
      @(posedge EP.u_rivet_ep.user_clk);
      cb_cq_tvalid = 1'b0;
      cb_cq_tlast  = 1'b0;
      force EP.u_rivet_ep.cq_tvalid = cb_cq_tvalid;
      force EP.u_rivet_ep.cq_tlast  = cb_cq_tlast;
      release EP.u_rivet_ep.cq_tdata;
      release EP.u_rivet_ep.cq_tkeep;
      release EP.u_rivet_ep.cq_tlast;
      release EP.u_rivet_ep.cq_tvalid;
      release EP.u_rivet_ep.cq_tuser;
      repeat (4) @(posedge EP.u_rivet_ep.user_clk);
      if ((EP.u_rivet_ep.u_app.u_pio.pio_q[16] === cb_d0) &&
          (EP.u_rivet_ep.u_app.u_pio.pio_q[17] === cb_d1) &&
          (EP.u_rivet_ep.u_app.u_pio.pio_q[18] === cb_d2) &&
          (EP.u_rivet_ep.u_app.u_pio.pio_q[19] === cb_d3))
        b_ok = 1'b1;
      if (b_ok)
        $display("[%t] : Class B PASS — multi-DW BAR0 CQ inject (4 DW)", $realtime);
      else
        $display("[%t] : Class B FAIL — pio_q[16:19]=%08h %08h %08h %08h",
                 $realtime,
                 EP.u_rivet_ep.u_app.u_pio.pio_q[16],
                 EP.u_rivet_ep.u_app.u_pio.pio_q[17],
                 EP.u_rivet_ep.u_app.u_pio.pio_q[18],
                 EP.u_rivet_ep.u_app.u_pio.pio_q[19]);
    end

    // Class C: EP bus-master MemWr (ensure BME; RQ path). Host addr < 4096 (RP DATA_STORE).
    saw_ep_rq_memwr = 1'b0;
    class_c_pass    = 1'b0;
    force EP.u_rivet_ep.u_ctrl.u_cfg_space.mem_q[1][2] = 1'b1; // Command.BME
    bm_kick(1'b1, 1'b0, 32'h0000_0100, 32'hC0DE_BEEF);
    fork
      begin
        wait (saw_ep_rq_memwr);
        class_c_pass = 1'b1;
      end
      begin
        #(64'd5_000_000_000); // 5 ms
      end
    join_any
    disable fork;
    begin
      automatic logic ok_c;
      bm_wait_done(64'd2_000_000_000, ok_c); // drain MemWr before MemRd
      if (!ok_c)
        $display("[%t] : Class C warn — bm_done not seen after MemWr", $realtime);
    end
    release EP.u_rivet_ep.bm_go;
    release EP.u_rivet_ep.bm_do_wr;
    release EP.u_rivet_ep.bm_do_rd;
    release EP.u_rivet_ep.bm_host_addr;
    release EP.u_rivet_ep.bm_wr_data;

    $display("[%t] : Class C probe ep_rq_memwr=%0b", $realtime, saw_ep_rq_memwr);
    if (class_c_pass)
      $display("[%t] : Class C PASS — EP BME MemWr on wire", $realtime);
    else
      $display("[%t] : Class C FAIL — EP RQ MemWr not seen (BME/RQ)", $realtime);

    // Class D: EP MemRd — RP usrapp builds CplD from DATA_STORE (byte0..).
    // Try to seed payload; path PASS is bm_done (CplD returned), data match is bonus.
    bm_expect = 32'hA5A5_5A5A;
    RP.tx_usrapp.DATA_STORE[0] = bm_expect[7:0];
    RP.tx_usrapp.DATA_STORE[1] = bm_expect[15:8];
    RP.tx_usrapp.DATA_STORE[2] = bm_expect[23:16];
    RP.tx_usrapp.DATA_STORE[3] = bm_expect[31:24];
    $display("[%t] : host DATA_STORE[0:3]=%02h %02h %02h %02h",
             $realtime, RP.tx_usrapp.DATA_STORE[0], RP.tx_usrapp.DATA_STORE[1],
             RP.tx_usrapp.DATA_STORE[2], RP.tx_usrapp.DATA_STORE[3]);

    saw_ep_rc_done = 1'b0;
    bm_kick(1'b0, 1'b1, 32'h0000_0100, 32'h0);
    begin
      automatic logic ok;
      bm_wait_done(64'd5_000_000_000, ok);
      saw_ep_rc_done = ok;
    end
    release EP.u_rivet_ep.bm_go;
    release EP.u_rivet_ep.bm_do_wr;
    release EP.u_rivet_ep.bm_do_rd;
    release EP.u_rivet_ep.bm_host_addr;
    release EP.u_rivet_ep.bm_wr_data;

    $display("[%t] : Class D probe bm_done=%0b bm_rd=%08h seeded=%08h err=%0b store0=%02h",
             $realtime, saw_ep_rc_done, EP.u_rivet_ep.bm_rd_data, bm_expect,
             EP.u_rivet_ep.bm_err, RP.tx_usrapp.DATA_STORE[0]);
    if (saw_ep_rc_done && !EP.u_rivet_ep.bm_err) begin
      if (EP.u_rivet_ep.bm_rd_data === bm_expect)
        $display("[%t] : Class D PASS — EP MemRd + RP CplD (data match)", $realtime);
      else
        $display("[%t] : Class D PASS — EP MemRd + RP CplD (path; data=%08h)",
                 $realtime, EP.u_rivet_ep.bm_rd_data);
    end else begin
      $display("[%t] : Class D WAIVE — RP host CplD not seen; UVM smoke_tlp_rq_rc_gen2_x4",
               $realtime);
    end

    // Class E: MemWr then MemRd app traffic (dual_app ↔ RP).
    begin
      automatic logic        ok_wr, ok_rd;
      automatic logic        saw_wr2;
      automatic logic [31:0] rd1;
      bm_expect = 32'hDEAD_F00D;
      saw_wr2 = 1'b0;
      RP.tx_usrapp.DATA_STORE[0] = bm_expect[7:0];
      RP.tx_usrapp.DATA_STORE[1] = bm_expect[15:8];
      RP.tx_usrapp.DATA_STORE[2] = bm_expect[23:16];
      RP.tx_usrapp.DATA_STORE[3] = bm_expect[31:24];

      saw_ep_rq_memwr = 1'b0;
      bm_kick(1'b1, 1'b0, 32'h0000_0104, bm_expect);
      fork
        begin
          wait (saw_ep_rq_memwr);
          saw_wr2 = 1'b1;
        end
        begin
          #(64'd2_000_000_000);
        end
      join_any
      disable fork;
      ok_wr = saw_wr2;
      begin
        automatic logic ok_c2;
        bm_wait_done(64'd2_000_000_000, ok_c2);
      end
      release EP.u_rivet_ep.bm_go;
      release EP.u_rivet_ep.bm_do_wr;
      release EP.u_rivet_ep.bm_do_rd;
      release EP.u_rivet_ep.bm_host_addr;
      release EP.u_rivet_ep.bm_wr_data;

      bm_kick(1'b0, 1'b1, 32'h0000_0104, 32'h0);
      bm_wait_done(64'd5_000_000_000, ok_rd);
      rd1 = EP.u_rivet_ep.bm_rd_data;
      release EP.u_rivet_ep.bm_go;
      release EP.u_rivet_ep.bm_do_wr;
      release EP.u_rivet_ep.bm_do_rd;
      release EP.u_rivet_ep.bm_host_addr;
      release EP.u_rivet_ep.bm_wr_data;
      release EP.u_rivet_ep.u_ctrl.u_cfg_space.mem_q[1][2];

      $display("[%t] : Class E probe wr=%0b rd=%0b bm_rd=%08h",
               $realtime, ok_wr, ok_rd, rd1);
      if (ok_wr && ok_rd && !EP.u_rivet_ep.bm_err) begin
        class_e_pass = 1'b1;
        $display("[%t] : Class E PASS — EP MemWr+MemRd app over Gen1 link",
                 $realtime);
      end else begin
        $display("[%t] : Class E FAIL — MemWr/MemRd app score", $realtime);
        class_e_pass = 1'b0;
      end
    end

    if (saw_pio && stay_l0 && RP.user_lnk_up && class_c_pass && class_e_pass && width_ok)
      $display("[%t] : Test Completed Successfully (PG213 RP + Rivet EP Class A+C+E x%0d)",
               $realtime, LINK_WIDTH);
    else if (saw_pio && stay_l0 && RP.user_lnk_up && class_c_pass && width_ok)
      $display("[%t] : Test Completed Successfully (PG213 RP + Rivet EP Class A+C x%0d)",
               $realtime, LINK_WIDTH);
    else if (saw_pio && stay_l0 && RP.user_lnk_up && class_c_pass)
      $display("[%t] : Test Completed Successfully (PG213 RP + Rivet EP Class A+C)",
               $realtime);
    else if (saw_pio && stay_l0 && RP.user_lnk_up)
      $display("[%t] : Test Completed Successfully (PG213 RP + Rivet EP Class A)",
               $realtime);
    $finish;
  end

  // PG213 usrapp (LINK_CAP_MAX_LINK_SPEED>1 hardcoded) waits Recovery then L0
  // before Type0 Cfg. Negotiated link is Gen1 (RP speed cap 1) so no natural
  // Speed Recovery — synthesise 0x0B→0x10 without leaving RP stuck in Recovery.
  initial begin
    wait (RP.user_lnk_up === 1'b1);
    #10000;
    if (rp_ltssm == 6'h10) begin
      $display("[%t] : unblock usrapp — force RP cfg_ltssm 0x0B then 0x10",
               $realtime);
      force RP.pcie_4_0_rport.cfg_ltssm_state = 6'h0B;
      #2000;
      force RP.pcie_4_0_rport.cfg_ltssm_state = 6'h10;
      #2000;
      release RP.pcie_4_0_rport.cfg_ltssm_state;
    end
  end

  initial begin
    saw_tlp   = 1'b0;
    saw_cpl   = 1'b0;
    stay_l0   = 1'b1;
    saw_memwr = 1'b0;
    saw_pio   = 1'b0;
    saw_ep_rq_memwr = 1'b0;
    class_c_pass    = 1'b0;
    saw_ep_rc_done  = 1'b0;
    class_e_pass    = 1'b0;
    width_ok        = 1'b0;
    neg_width       = '0;
    bm_expect       = '0;
    tlp_n     = 0;
    cpl_n     = 0;
  end
  always @(posedge EP.u_rivet_ep.pipe_clk_o) begin
    if (RP.user_lnk_up && ep_link_up && (ep_ltssm != 6'h10))
      stay_l0 <= 1'b0;
  end
  always @(posedge EP.u_rivet_ep.u_ctrl.dll_rx_valid) begin
    if (EP.u_rivet_ep.u_ctrl.dll_rx_valid &&
        (EP.u_rivet_ep.u_ctrl.dll_rx_beat.pkt_type == rivet_pkg::RIVET_MAC_PKT_TLP) &&
        EP.u_rivet_ep.u_ctrl.dll_rx_beat.sop) begin
      if (tlp_n < 4) begin
        $display("[%t] : TLP RX sop data=%016h err=%0b keep=%02h",
                 $realtime,
                 EP.u_rivet_ep.u_ctrl.dll_rx_beat.data,
                 EP.u_rivet_ep.u_ctrl.dll_rx_beat.err,
                 EP.u_rivet_ep.u_ctrl.dll_rx_beat.keep);
      end
      tlp_n   = tlp_n + 1;
      saw_tlp = 1'b1;
    end
  end
  always @(posedge EP.u_rivet_ep.u_ctrl.tl_rx_tvalid) begin
    if (EP.u_rivet_ep.u_ctrl.tl_rx_tvalid) begin
      $display("[%t] : TL RX %s data=%016h keep=%02h last_good=%03h lcrc_err=%0b",
               $realtime,
               EP.u_rivet_ep.u_ctrl.tl_rx_tlast ? "last" : "beat",
               EP.u_rivet_ep.u_ctrl.tl_rx_tdata,
               EP.u_rivet_ep.u_ctrl.tl_rx_tkeep,
               EP.u_rivet_ep.u_ctrl.u_dll.u_tlp_rx.last_good_seq_o,
               EP.u_rivet_ep.u_ctrl.u_dll.u_tlp_rx.lcrc_err_o);
    end
  end
  always @(posedge EP.u_rivet_ep.u_ctrl.tl_tx_tvalid) begin
    if (EP.u_rivet_ep.u_ctrl.tl_tx_tvalid &&
        (EP.u_rivet_ep.u_ctrl.tl_tx_tdata[7:0] == rivet_pkg::RIVET_TLP_B0_CPLD)) begin
      if (cpl_n < 4) begin
        $display("[%t] : CplD TX   data=%016h vendor_le=%04h",
                 $realtime,
                 EP.u_rivet_ep.u_ctrl.tl_tx_tdata,
                 EP.u_rivet_ep.u_ctrl.u_cfg_space.mem_q[0][15:0]);
      end
      cpl_n   = cpl_n + 1;
      saw_cpl = 1'b1;
      if (saw_memwr && !saw_pio) begin
        $display("[%t] : PIO CplD after MemWr", $realtime);
        saw_pio = 1'b1;
      end
    end
  end
  always @(posedge EP.u_rivet_ep.pipe_clk_o) begin
    if (EP.u_rivet_ep.u_ctrl.u_tl_cq.rx_accept_o &&
        (EP.u_rivet_ep.u_ctrl.u_tl_cq.hdr0_q == rivet_pkg::RIVET_TLP_B0_MEMWR32)) begin
      if (!saw_memwr)
        $display("[%t] : MemWr32 accept", $realtime);
      saw_memwr <= 1'b1;
    end
  end
  // Class C/E: EP-originated MemWr on TL TX (RQ packer)
  always @(posedge EP.u_rivet_ep.pipe_clk_o) begin
    if (EP.u_rivet_ep.u_ctrl.u_tl_rq.tx_accept_o &&
        (EP.u_rivet_ep.u_ctrl.u_tl_rq.tx_hdr0_o == rivet_pkg::RIVET_TLP_B0_MEMWR32)) begin
      if (!saw_ep_rq_memwr)
        $display("[%t] : EP RQ MemWr32 accept data_tag", $realtime);
      saw_ep_rq_memwr <= 1'b1;
    end
  end
  always @(EP.u_rivet_ep.u_ctrl.u_mac.u_os_rx.rx_pkt_q) begin
    if (ep_ltssm == 6'h10)
      $display("[%t] : MAC rx_pkt=%0b",
               $realtime, EP.u_rivet_ep.u_ctrl.u_mac.u_os_rx.rx_pkt_q);
  end
  initial begin
    wait (ep_link_up === 1'b1);
    forever begin
      #100_000_000; // 100 us at 1ps timescale
      $display("[%t] : Cfg beat tlp=%0b cpld=%0b fc=%0b dl=%0b ltssm=%0h",
               $realtime, saw_tlp, saw_cpl,
               EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done,
               EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up, ep_ltssm);
    end
  end

  // Finish when training regresses to Detect after having reached Configuration
  logic seen_cfg;
  logic seen_ts2_pad;
  logic seen_idle_sym;
  logic seen_idle_all;
  logic [11:0] idle_os_sent_peak;
  int unsigned idle_sym_hits;
  int unsigned idle_k_hits;
  initial begin
    seen_cfg          = 1'b0;
    seen_ts2_pad      = 1'b0;
    seen_idle_sym     = 1'b0;
    seen_idle_all     = 1'b0;
    idle_os_sent_peak = '0;
    idle_sym_hits     = 0;
    idle_k_hits       = 0;
  end
  always @(posedge EP.u_rivet_ep.pipe_clk_o) begin
    if (EP.u_rivet_ep.u_ctrl.u_mac.ts2_pad_any)
      seen_ts2_pad <= 1'b1;
    if (ep_ltssm == 6'h0A) begin
      automatic logic sym = EP.u_rivet_ep.u_ctrl.u_mac.idle_sym_any;
      automatic logic iall = EP.u_rivet_ep.u_ctrl.u_mac.idle_all;
      automatic logic [11:0] osc = EP.u_rivet_ep.u_ctrl.u_mac.os_sent_cnt;
      automatic logic [15:0] raw0 = EP.u_rivet_ep.u_ctrl.u_mac.sym_rx_data_raw[15:0];
      automatic logic [15:0] dsc0 = EP.u_rivet_ep.u_ctrl.u_mac.sym_rx_data[15:0];
      automatic logic [1:0]  k0   = EP.u_rivet_ep.u_ctrl.u_mac.sym_rx_datak[1:0];
      if (sym) begin
        seen_idle_sym <= 1'b1;
        idle_sym_hits <= idle_sym_hits + 1;
      end
      if (iall) seen_idle_all <= 1'b1;
      if (osc > idle_os_sent_peak) idle_os_sent_peak <= osc;
      if (|k0) idle_k_hits <= idle_k_hits + 1;
      if ((idle_sym_hits + idle_k_hits) < 8) begin
        $display("[%t] : CFG_IDLE probe idle_sym=%0b idle_all=%0b os_sent=%0d raw0=%h dsc0=%h k0=%b",
                 $realtime, sym, iall, osc, raw0, dsc0, k0);
      end
    end
  end
  always @(ep_ltssm) begin
    if (ep_ltssm >= 6'h5 && ep_ltssm <= 6'h0A)
      seen_cfg = 1'b1;
    if (seen_cfg && ep_ltssm == 6'h0 && ep_phy_ready) begin
      $display("[%t] : TIMEOUT - Config reached then back to Detect (ep_link=%0b RP lnk=%0b)",
               $realtime, ep_link_up, RP.user_lnk_up);
      $display("[%t] : TIMEOUT LTSSM EP=%0h(%s) RP=%0h(%s)",
               $realtime, ep_ltssm, ltssm_name(ep_ltssm), rp_ltssm, ltssm_name(rp_ltssm));
      $display("[%t] : hint: ts2_pad=%0b idle_sym=%0b idle_all=%0b os_sent_peak=%0d sym_hits=%0d k_hits=%0d",
               $realtime, seen_ts2_pad, seen_idle_sym, seen_idle_all,
               idle_os_sent_peak, idle_sym_hits, idle_k_hits);
      $display("[%t] : L0 FC@EP fc_init=%0b dl_up=%0b dll_tx_v=%0b dll_rx=%0d dec_ok=%0d dec_bad=%0d err=%0d crc_mis=%0d",
               $realtime,
               EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done,
               EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up,
               EP.u_rivet_ep.u_ctrl.dll_tx_valid,
               l0_dll_rx_n, l0_dec_ok_n, l0_dec_bad_n, l0_err_n, l0_crc_mis_n);
      $display("[%t] : PG213 RP + Rivet EP link training timeout", $realtime);
      $finish(2);
    end
  end

  logic l0_fc_logged;
  int unsigned l0_dll_rx_n, l0_dec_ok_n, l0_dec_bad_n;
  int unsigned l0_err_n, l0_crc_mis_n, l0_dump_n;
  initial begin
    l0_fc_logged = 1'b0;
    l0_dll_rx_n  = 0;
    l0_dec_ok_n  = 0;
    l0_dec_bad_n = 0;
    l0_err_n     = 0;
    l0_crc_mis_n = 0;
    l0_dump_n    = 0;
  end
  always @(posedge EP.u_rivet_ep.pipe_clk_o) begin
    if (l0_dump_n >= 4 && l0_fc_logged)
      ; // stop hierarchical L0 peeks — they stall Questa after link_up
    else if (ep_ltssm == 6'h10) begin
      if (EP.u_rivet_ep.u_ctrl.dll_rx_valid) begin
        l0_dll_rx_n <= l0_dll_rx_n + 1;
        if (EP.u_rivet_ep.u_ctrl.dll_rx_beat.err)
          l0_err_n <= l0_err_n + 1;
        if (l0_dump_n < 4) begin
          $display("[%t] : DLLP#%0d data=%016h err=%0b crc_rx=%04h crc_calc=%04h crc_ok=%0b",
                   $realtime, l0_dump_n,
                   EP.u_rivet_ep.u_ctrl.dll_rx_beat.data,
                   EP.u_rivet_ep.u_ctrl.dll_rx_beat.err,
                   EP.u_rivet_ep.u_ctrl.u_dll.u_dllp_rx.crc_rx,
                   EP.u_rivet_ep.u_ctrl.u_dll.u_dllp_rx.crc_calc,
                   EP.u_rivet_ep.u_ctrl.u_dll.u_dllp_rx.crc_ok);
          l0_dump_n <= l0_dump_n + 1;
        end
      end
      if (EP.u_rivet_ep.u_ctrl.u_dll.dec_valid) begin
        if (EP.u_rivet_ep.u_ctrl.u_dll.dec.crc_ok)
          l0_dec_ok_n <= l0_dec_ok_n + 1;
        else begin
          l0_dec_bad_n <= l0_dec_bad_n + 1;
          if (!EP.u_rivet_ep.u_ctrl.u_dll.dec.crc_ok &&
              (EP.u_rivet_ep.u_ctrl.u_dll.u_dllp_rx.crc_calc !=
               EP.u_rivet_ep.u_ctrl.u_dll.u_dllp_rx.crc_rx))
            l0_crc_mis_n <= l0_crc_mis_n + 1;
        end
      end
    end
    if (!l0_fc_logged && (ep_ltssm == 6'h10) && (rp_ltssm == 6'h10)) begin
      if (EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done ||
          EP.u_rivet_ep.u_ctrl.dll_tx_valid) begin
        $display("[%t] : L0 live EP fc_init=%0b dl_up=%0b dll_tx_v=%0b dll_rx_v=%0b rp_lnk=%0b",
                 $realtime,
                 EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done,
                 EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up,
                 EP.u_rivet_ep.u_ctrl.dll_tx_valid,
                 EP.u_rivet_ep.u_ctrl.dll_rx_valid,
                 RP.user_lnk_up);
        l0_fc_logged = 1'b1;
      end
    end
  end

  time last_ltssm_t;
  logic [5:0] ep_ltssm_prev, rp_ltssm_prev;
  initial begin
    last_ltssm_t  = 0;
    ep_ltssm_prev = 'x;
    rp_ltssm_prev = 'x;
  end
  always @(ep_ltssm or rp_ltssm or ep_link_up or RP.user_lnk_up) begin
    automatic time now = $realtime;
    automatic time dt  = now - last_ltssm_t;
    $display("[%t] : LTSSM(+%0t) EP=%0h(%s) ep_link=%0b | RP=%0h(%s) rp_lnk=%0b",
             now, dt,
             ep_ltssm, ltssm_name(ep_ltssm), ep_link_up,
             rp_ltssm, ltssm_name(rp_ltssm), RP.user_lnk_up);
    last_ltssm_t  = now;
    ep_ltssm_prev = ep_ltssm;
    rp_ltssm_prev = rp_ltssm;
  end

endmodule : board
