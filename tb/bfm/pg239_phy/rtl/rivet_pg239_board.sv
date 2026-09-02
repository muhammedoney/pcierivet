// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// BFM stage-2 board: EP (Upstream) + RC (Downstream) Rivet+PG239 shells
// linked over serial ×4. PASS when both report link_up (Config.Idle / L0 path).

`timescale 1ps/1ps

module rivet_pg239_board;

  localparam int unsigned LANES = 4;
  // Example refclk half-period: 100 MHz differential (5 ns half = 10 ns period).
  localparam int unsigned REF_CLK_HALF_CYCLE = 5000; // ps

  logic sys_rst_n;
  logic ep_sys_clk_p, ep_sys_clk_n;
  logic rp_sys_clk_p, rp_sys_clk_n;

  logic [LANES-1:0] ep_txp, ep_txn, ep_rxp, ep_rxn;
  logic [LANES-1:0] rp_txp, rp_txn, rp_rxp, rp_rxn;

  logic ep_phy_ready, rp_phy_ready;
  logic ep_link_up, rp_link_up;
  logic [5:0] ep_ltssm, rp_ltssm;

  // Serial cross-connect
  assign ep_rxp = rp_txp;
  assign ep_rxn = rp_txn;
  assign rp_rxp = ep_txp;
  assign rp_rxn = ep_txn;

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE)
  ) u_clk_ep (
    .sys_clk_p (ep_sys_clk_p),
    .sys_clk_n (ep_sys_clk_n)
  );

  sys_clk_gen_ds #(
    .halfcycle (REF_CLK_HALF_CYCLE)
  ) u_clk_rp (
    .sys_clk_p (rp_sys_clk_p),
    .sys_clk_n (rp_sys_clk_n)
  );

  rivet_pg239_ep #(
    .MODE  (0), // EP / Upstream
    .LANES (LANES)
  ) u_ep (
    .sys_clk_p       (ep_sys_clk_p),
    .sys_clk_n       (ep_sys_clk_n),
    .sys_rst_n       (sys_rst_n),
    .pci_exp_txp     (ep_txp),
    .pci_exp_txn     (ep_txn),
    .pci_exp_rxp     (ep_rxp),
    .pci_exp_rxn     (ep_rxn),
    .phy_ready       (ep_phy_ready),
    .link_up         (ep_link_up),
    .cfg_ltssm_state (ep_ltssm),
    .pipe_clk_o      (),
    .user_clk_o      ()
  );

  // Root Port shell: Downstream Port Config (offers Link# / Lane#).
  rivet_pg239_ep #(
    .MODE  (1), // RC / Downstream
    .LANES (LANES)
  ) u_rp (
    .sys_clk_p       (rp_sys_clk_p),
    .sys_clk_n       (rp_sys_clk_n),
    .sys_rst_n       (sys_rst_n),
    .pci_exp_txp     (rp_txp),
    .pci_exp_txn     (rp_txn),
    .pci_exp_rxp     (rp_rxp),
    .pci_exp_rxn     (rp_rxn),
    .phy_ready       (rp_phy_ready),
    .link_up         (rp_link_up),
    .cfg_ltssm_state (rp_ltssm),
    .pipe_clk_o      (),
    .user_clk_o      ()
  );

  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge ep_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

  initial begin
    wait (sys_rst_n === 1'b1);
    $display("[%t] : Waiting for both PHY ready...", $realtime);
    wait (ep_phy_ready && rp_phy_ready);
    $display("[%t] : Both PHY ready — Rivet LTSSM running", $realtime);

    fork
      begin
        wait (ep_link_up && rp_link_up);
        wait (ep_ltssm == 6'h10 && rp_ltssm == 6'h10); // L0
        #10000;
        $display("[%t] : EP ltssm=%0h RP ltssm=%0h", $realtime, ep_ltssm, rp_ltssm);
        $display("[%t] : Test Completed Successfully (Rivet+PG239 link_up)", $realtime);

        // Post-link DLL status (FC / TLP). Hierarchical probes into soft ctrl.
        begin
          automatic logic ep_fc, rp_fc, ep_dl, rp_dl;
          automatic logic ep_acc, rp_acc, ep_tv, ep_tr, ep_rv, rp_tv, rp_tr, rp_rv;
          automatic int unsigned i;
          ep_acc = u_ep.u_ctrl.mac_to_dll_sb.accept_dll_tlp;
          rp_acc = u_rp.u_ctrl.mac_to_dll_sb.accept_dll_tlp;
          ep_fc = u_ep.u_ctrl.dll_to_tl_fc.fc_init_done;
          rp_fc = u_rp.u_ctrl.dll_to_tl_fc.fc_init_done;
          ep_dl = u_ep.u_ctrl.dll_to_tl_fc.dl_up;
          rp_dl = u_rp.u_ctrl.dll_to_tl_fc.dl_up;
          $display("[%t] : FC@L0       EP acc=%0b fc=%0b dl=%0b | RP acc=%0b fc=%0b dl=%0b",
                   $realtime, ep_acc, ep_fc, ep_dl, rp_acc, rp_fc, rp_dl);
          for (i = 0; i < 500000; i++) begin
            @(posedge u_ep.pipe_clk_o);
            ep_fc = u_ep.u_ctrl.dll_to_tl_fc.fc_init_done;
            rp_fc = u_rp.u_ctrl.dll_to_tl_fc.fc_init_done;
            ep_dl = u_ep.u_ctrl.dll_to_tl_fc.dl_up;
            rp_dl = u_rp.u_ctrl.dll_to_tl_fc.dl_up;
            ep_tv = u_ep.u_ctrl.dll_tx_valid;
            ep_tr = u_ep.u_ctrl.dll_tx_ready;
            ep_rv = u_ep.u_ctrl.dll_rx_valid;
            rp_tv = u_rp.u_ctrl.dll_tx_valid;
            rp_tr = u_rp.u_ctrl.dll_tx_ready;
            rp_rv = u_rp.u_ctrl.dll_rx_valid;
            if (ep_fc && rp_fc && ep_dl && rp_dl) break;
          end
          $display("[%t] : FC@post     EP fc=%0b dl=%0b tv/tr/rv=%0b%0b%0b | RP fc=%0b dl=%0b tv/tr/rv=%0b%0b%0b",
                   $realtime, ep_fc, ep_dl, ep_tv, ep_tr, ep_rv, rp_fc, rp_dl, rp_tv, rp_tr, rp_rv);
          $display("[%t] : TLP note    RC/EP tl_tx tied idle in rivet_pcie_ctrl (no app TLP inject)",
                   $realtime);
          if (ep_fc && rp_fc && ep_dl && rp_dl)
            $display("[%t] : FC RESULT  PASS — both sides fc_init_done + dl_up", $realtime);
          else begin
            $display("[%t] : FC RESULT  FAIL — FC init / dl_up incomplete", $realtime);
            $fatal(1, "Rivet+PG239 FC init failed after link_up");
          end

          // After InitFC: count RC→EP UpdateFC for a short window (default gap=32 pclk).
          begin
            automatic int unsigned rp_upd_tx, ep_upd_rx, j;
            automatic logic [3:0] k;
            rp_upd_tx = 0;
            ep_upd_rx = 0;
            for (j = 0; j < 512; j++) begin
              @(posedge u_ep.pipe_clk_o);
              if (u_rp.u_ctrl.u_dll.u_fc.state_q == 2'd3 &&
                  u_rp.u_ctrl.u_dll.fc_req_valid &&
                  u_rp.u_ctrl.u_dll.fc_req_ready) begin
                k = u_rp.u_ctrl.u_dll.u_fc.req_o.fc_kind;
                if (k == 4'h8 || k == 4'h9 || k == 4'hA) rp_upd_tx++;
              end
              if (u_ep.u_ctrl.u_dll.dec_valid &&
                  u_ep.u_ctrl.u_dll.dec.crc_ok &&
                  (u_ep.u_ctrl.u_dll.dec.kind == rivet_pkg::RIVET_DLLP_KIND_FC)) begin
                k = u_ep.u_ctrl.u_dll.dec.fc_kind;
                if (k == 4'h8 || k == 4'h9 || k == 4'hA) ep_upd_rx++;
              end
            end
            $display("[%t] : UPDATEFC   RC_tx_accept=%0d EP_rx_decode=%0d (512 pclk window)",
                     $realtime, rp_upd_tx, ep_upd_rx);
            if (rp_upd_tx == 0 || ep_upd_rx == 0)
              $display("[%t] : UPDATEFC   NOTE — none observed in window", $realtime);
            else
              $display("[%t] : UPDATEFC   PASS — periodic UpdateFC seen RC→EP", $realtime);
          end
        end
        $finish;
      end
      begin
        // 500 ms @ 1ps timescale — PG239 bring-up + scaled LTSSM need headroom.
        #(64'd500000000000);
        $display("[%t] : TIMEOUT — EP link_up=%0b ltssm=%0h RP link_up=%0b ltssm=%0h",
                 $realtime, ep_link_up, ep_ltssm, rp_link_up, rp_ltssm);
        $fatal(1, "Rivet+PG239 link training timeout");
      end
    join
  end

  always @(ep_ltssm or rp_ltssm) begin
    $display("[%t] : LTSSM ep=%0h rp=%0h link_up ep=%0b rp=%0b",
             $realtime, ep_ltssm, rp_ltssm, ep_link_up, rp_link_up);
  end

endmodule
