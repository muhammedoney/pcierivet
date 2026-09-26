// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// PG213 stage-3 board: Xilinx RP model ↔ Rivet EP+PG239.
// Module name MUST be `board` and RP instance `RP` — usrapp_* uses board.RP.*.

`timescale 1ps/1ps

module board;
  import rivet_pkg::*;

  localparam int unsigned LINK_WIDTH         = 4;
  localparam int unsigned REF_CLK_HALF_CYCLE = 5000; // ps → 100 MHz (sys_clk_gen is 1ps)

  logic sys_rst_n;
  logic ep_sys_clk_p, ep_sys_clk_n;
  logic rp_sys_clk_p, rp_sys_clk_n;

  logic [LINK_WIDTH-1:0] ep_pci_exp_txn, ep_pci_exp_txp;
  logic [LINK_WIDTH-1:0] rp_pci_exp_txn, rp_pci_exp_txp;

  logic ep_phy_ready, ep_link_up;
  logic [5:0] ep_ltssm;
  // PG213 RP uses the same cfg_ltssm_state[5:0] encoding (usrapp waits 0x0B then 0x10).
  wire  [5:0] rp_ltssm = RP.pcie_4_0_rport.cfg_ltssm_state;

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

  // Rivet EP+PG239 (pin-compatible swap for xilinx_pcie4_uscale_ep)
  rivet_pg213_ep_swap #(
    .PL_LINK_CAP_MAX_LINK_WIDTH (5'(LINK_WIDTH)),
    .C_DATA_WIDTH               (64)
  ) EP (
    .pci_exp_txp   (ep_pci_exp_txp),
    .pci_exp_txn   (ep_pci_exp_txn),
    .pci_exp_rxp   (rp_pci_exp_txp),
    .pci_exp_rxn   (rp_pci_exp_txn),
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

  // Stock PG213 Root Port model — width matches Rivet EP (×4).
  xilinx_pcie4_uscale_rp #(
    .PL_LINK_CAP_MAX_LINK_SPEED (1), // Gen1 (temporary bring-up)
    .PL_LINK_CAP_MAX_LINK_WIDTH (5'(LINK_WIDTH)),
    .PF0_DEV_CAP_MAX_PAYLOAD_SIZE (3'b011)
  ) RP (
    .sys_clk_n (rp_sys_clk_n),
    .sys_clk_p (rp_sys_clk_p),
    .sys_rst_n (sys_rst_n),
    .pci_exp_txn (rp_pci_exp_txn),
    .pci_exp_txp (rp_pci_exp_txp),
    .pci_exp_rxn (ep_pci_exp_txn),
    .pci_exp_rxp (ep_pci_exp_txp)
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
    $display("[%t] : Test Completed Successfully (PG213 RP + Rivet EP link_up)",
             $realtime);

    begin
      automatic logic ep_fc, ep_dl;
      automatic int unsigned i;
      ep_fc = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done;
      ep_dl = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up;
      for (i = 0; i < 200000; i++) begin
        @(posedge EP.u_rivet_ep.pipe_clk_o);
        ep_fc = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.fc_init_done;
        ep_dl = EP.u_rivet_ep.u_ctrl.dll_to_tl_fc.dl_up;
        if (ep_fc && ep_dl) break;
      end
      $display("[%t] : FC@EP       fc_init=%0b dl_up=%0b", $realtime, ep_fc, ep_dl);
    end

    // Stay past link_up: dump first TLP and wait for Type 0 CplD (Vendor/Device).
    begin
      automatic int unsigned i;
      automatic logic saw_tlp, saw_cpl, stay_l0;
      automatic logic [7:0] tlp_b0;
      saw_tlp = 1'b0;
      saw_cpl = 1'b0;
      stay_l0 = 1'b1;
      for (i = 0; i < 2_000_000; i++) begin
        @(posedge EP.u_rivet_ep.pipe_clk_o);
        if (ep_ltssm != 6'h10) stay_l0 = 1'b0;
        if (!saw_tlp && EP.u_rivet_ep.u_ctrl.dll_rx_valid &&
            (EP.u_rivet_ep.u_ctrl.dll_rx_beat.pkt_type == rivet_pkg::RIVET_MAC_PKT_TLP) &&
            EP.u_rivet_ep.u_ctrl.dll_rx_beat.sop) begin
          tlp_b0 = EP.u_rivet_ep.u_ctrl.dll_rx_beat.data[7:0];
          $display("[%t] : TLP RX sop data=%016h err=%0b keep=%02h b0=%02h",
                   $realtime,
                   EP.u_rivet_ep.u_ctrl.dll_rx_beat.data,
                   EP.u_rivet_ep.u_ctrl.dll_rx_beat.err,
                   EP.u_rivet_ep.u_ctrl.dll_rx_beat.keep,
                   tlp_b0);
          saw_tlp = 1'b1;
        end
        if (!saw_cpl && EP.u_rivet_ep.u_ctrl.tl_tx_tvalid &&
            EP.u_rivet_ep.u_ctrl.tl_tx_tready &&
            (EP.u_rivet_ep.u_ctrl.tl_tx_tdata[7:0] == rivet_pkg::RIVET_TLP_B0_CPLD)) begin
          $display("[%t] : CplD TX   data=%016h vendor_le=%04h",
                   $realtime,
                   EP.u_rivet_ep.u_ctrl.tl_tx_tdata,
                   EP.u_rivet_ep.u_ctrl.u_tl_cfg.cfg_q[0][15:0]);
          saw_cpl = 1'b1;
        end
        if (saw_tlp && saw_cpl) break;
      end
      $display("[%t] : Cfg probe   tlp=%0b cpld=%0b stay_l0=%0b rp_lnk=%0b",
               $realtime, saw_tlp, saw_cpl, stay_l0, RP.user_lnk_up);
      if (saw_cpl && stay_l0 && RP.user_lnk_up) begin
        $display("[%t] : Test Completed Successfully (PG213 RP + Rivet EP Cfg Vendor/Device)",
                 $realtime);
      end else begin
        $display("[%t] : Cfg Vendor/Device incomplete (TLP path probe only)", $realtime);
      end
    end
    $finish;
  end

  // Finish when training regresses to Detect after having reached Configuration
  // (Polling is no longer the sticky fail — Config/Idle vs RP is).
  // CFG_IDLE probes per docs/ltssm.xlsx §4.2.6.3.6 Transition #19.
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

  // While both sides claim L0, sample EP FC / DLLP progress once.
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
    if (ep_ltssm == 6'h10) begin
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

  // Comparative EP vs RP LTSSM timeline (state change on either side).
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
