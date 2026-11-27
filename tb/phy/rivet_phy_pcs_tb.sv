// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Soft PHY unit bench. One case per +define. Width via +define+PHY_WIDTH.

`timescale 1ns/1ps

module rivet_phy_pcs_tb;
`ifdef CASE_X4
  localparam int unsigned LANES = 4;
`else
  localparam int unsigned LANES = 1;
`endif
`ifdef PHY_WIDTH
  localparam int unsigned PIPE_DATA_WIDTH = `PHY_WIDTH;
`else
  localparam int unsigned PIPE_DATA_WIDTH = 16;
`endif

  logic clk = 1'b0;
  logic preset_n;
  logic phy_gtrefclk = 1'b0;
  logic pclk;
  logic user_clk;
  logic phy_ready;
  logic [LANES-1:0] gt_gtpowergood;
  logic [LANES-1:0] pci_exp_txp, pci_exp_txn, pci_exp_rxp, pci_exp_rxn;

  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_txdata;
  logic [2*LANES-1:0]               pipe_txdatak;
  logic [LANES-1:0]                 pipe_txdata_valid;
  logic [LANES-1:0]                 pipe_txstart_block;
  logic [2*LANES-1:0]               pipe_txsync_header;
  logic [PIPE_DATA_WIDTH*LANES-1:0] pipe_rxdata;
  logic [2*LANES-1:0]               pipe_rxdatak;
  logic [LANES-1:0]                 pipe_rxdata_valid;
  logic [2*LANES-1:0]               pipe_rxstart_block;
  logic [2*LANES-1:0]               pipe_rxsync_header;
  logic                             pipe_txdetectrx;
  logic [LANES-1:0]                 pipe_txelecidle;
  logic [LANES-1:0]                 pipe_txcompliance;
  logic [LANES-1:0]                 pipe_rxpolarity;
  logic [1:0]                       pipe_powerdown;
  logic [2:0]                       pipe_rate;
  logic [LANES-1:0]                 pipe_rxvalid;
  logic [LANES-1:0]                 pipe_phystatus;
  logic [LANES-1:0]                 pipe_phystatus_rst;
  logic [LANES-1:0]                 pipe_rxelecidle;
  logic [3*LANES-1:0]               pipe_rxstatus;
  logic [2:0]                       pipe_txmargin;
  logic                             pipe_txswing;
  logic                             pipe_txdeemph;
  logic [2*LANES-1:0]               pipe_txeq_ctrl;
  logic [4*LANES-1:0]               pipe_txeq_preset;
  logic [6*LANES-1:0]               pipe_txeq_coeff;
  logic [5:0]                       pipe_txeq_fs;
  logic [5:0]                       pipe_txeq_lf;
  logic [18*LANES-1:0]              pipe_txeq_new_coeff;
  logic [LANES-1:0]                 pipe_txeq_done;
  logic [2*LANES-1:0]               pipe_rxeq_ctrl;
  logic [4*LANES-1:0]               pipe_rxeq_txpreset;
  logic [LANES-1:0]                 pipe_rxeq_preset_sel;
  logic [18*LANES-1:0]              pipe_rxeq_new_txcoeff;
  logic [LANES-1:0]                 pipe_rxeq_adapt_done;
  logic [LANES-1:0]                 pipe_rxeq_done;
  logic                             pipe_as_mac_in_detect;
  logic                             pipe_as_cdr_hold_req;
  logic                             inject_code_err;
  logic                             inject_disp_err;
  logic                             eb_delete_skp;
  logic                             eb_insert_skp;
  logic                             eb_flood;

  always #2 clk = ~clk;

  rivet_pcie_phy_soft #(
    .LANES           (LANES),
    .PIPE_DATA_WIDTH (PIPE_DATA_WIDTH)
  ) u_phy (
    .phy_refclk          (clk),
    .phy_gtrefclk        (phy_gtrefclk),
    .phy_rst_n           (preset_n),
    .pclk                (pclk),
    .user_clk            (user_clk),
    .phy_ready           (phy_ready),
    .gt_gtpowergood      (gt_gtpowergood),
    .pci_exp_txp         (pci_exp_txp),
    .pci_exp_txn         (pci_exp_txn),
    .pci_exp_rxp         (pci_exp_rxp),
    .pci_exp_rxn         (pci_exp_rxn),
    .pipe_txdata         (pipe_txdata),
    .pipe_txdatak        (pipe_txdatak),
    .pipe_txdata_valid   (pipe_txdata_valid),
    .pipe_txstart_block  (pipe_txstart_block),
    .pipe_txsync_header  (pipe_txsync_header),
    .pipe_rxdata         (pipe_rxdata),
    .pipe_rxdatak        (pipe_rxdatak),
    .pipe_rxdata_valid   (pipe_rxdata_valid),
    .pipe_rxstart_block  (pipe_rxstart_block),
    .pipe_rxsync_header  (pipe_rxsync_header),
    .pipe_txdetectrx     (pipe_txdetectrx),
    .pipe_txelecidle     (pipe_txelecidle),
    .pipe_txcompliance   (pipe_txcompliance),
    .pipe_rxpolarity     (pipe_rxpolarity),
    .pipe_powerdown      (pipe_powerdown),
    .pipe_rate           (pipe_rate),
    .pipe_rxvalid        (pipe_rxvalid),
    .pipe_phystatus      (pipe_phystatus),
    .pipe_phystatus_rst  (pipe_phystatus_rst),
    .pipe_rxelecidle     (pipe_rxelecidle),
    .pipe_rxstatus       (pipe_rxstatus),
    .pipe_txmargin       (pipe_txmargin),
    .pipe_txswing        (pipe_txswing),
    .pipe_txdeemph       (pipe_txdeemph),
    .pipe_txeq_ctrl      (pipe_txeq_ctrl),
    .pipe_txeq_preset    (pipe_txeq_preset),
    .pipe_txeq_coeff     (pipe_txeq_coeff),
    .pipe_txeq_fs        (pipe_txeq_fs),
    .pipe_txeq_lf        (pipe_txeq_lf),
    .pipe_txeq_new_coeff (pipe_txeq_new_coeff),
    .pipe_txeq_done      (pipe_txeq_done),
    .pipe_rxeq_ctrl      (pipe_rxeq_ctrl),
    .pipe_rxeq_txpreset  (pipe_rxeq_txpreset),
    .pipe_rxeq_preset_sel (pipe_rxeq_preset_sel),
    .pipe_rxeq_new_txcoeff (pipe_rxeq_new_txcoeff),
    .pipe_rxeq_adapt_done (pipe_rxeq_adapt_done),
    .pipe_rxeq_done      (pipe_rxeq_done),
    .pipe_as_mac_in_detect (pipe_as_mac_in_detect),
    .pipe_as_cdr_hold_req  (pipe_as_cdr_hold_req),
    .inject_code_err     (inject_code_err),
    .inject_disp_err     (inject_disp_err),
    .eb_delete_skp       (eb_delete_skp),
    .eb_insert_skp       (eb_insert_skp),
    .eb_flood            (eb_flood)
  );

  initial begin
    pci_exp_rxp = '0;
    pci_exp_rxn = '1;
    pipe_txdata = '0;
    pipe_txdatak = '0;
    pipe_txdata_valid = '0;
    pipe_txstart_block = '0;
    pipe_txsync_header = '0;
    pipe_txdetectrx = 1'b0;
    pipe_txelecidle = '1;
    pipe_txcompliance = '0;
    pipe_rxpolarity = '0;
    pipe_powerdown = 2'b10;
    pipe_rate = 3'd1;
    pipe_txmargin = '0;
    pipe_txswing = 1'b0;
    pipe_txdeemph = 1'b1;
    pipe_txeq_ctrl = '0;
    pipe_txeq_preset = '0;
    pipe_txeq_coeff = '0;
    pipe_rxeq_ctrl = '0;
    pipe_rxeq_txpreset = '0;
    pipe_as_mac_in_detect = 1'b0;
    pipe_as_cdr_hold_req = 1'b0;
    inject_code_err = 1'b0;
    inject_disp_err = 1'b0;
    eb_delete_skp = 1'b0;
    eb_insert_skp = 1'b0;
    eb_flood = 1'b0;
    preset_n = 1'b0;
  end

`ifdef CASE_RESET
  initial begin
    repeat (8) @(posedge clk);
    preset_n = 1'b1;
    @(posedge clk);
    if (pipe_phystatus_rst[0] !== 1'b1)
      $fatal(1, "phystatus_rst must be high in reset");
    repeat (32) @(posedge clk);
    if (pipe_phystatus_rst[0] !== 1'b0)
      $fatal(1, "phystatus_rst must fall after reset");
    if (user_clk !== pclk)
      $fatal(1, "user_clk must track pclk");
    $display("PASS: phy reset");
    $finish;
  end
`elsif CASE_8B10B
  initial begin
    logic saw_valid_early;
    logic saw_dec;
    logic saw_disp;
    saw_valid_early = 1'b0;
    saw_dec = 1'b0;
    saw_disp = 1'b0;
    repeat (4) @(posedge clk);
    preset_n = 1'b1;
    pipe_powerdown = 2'b00;
    pipe_txelecidle = '0;
    pipe_rate = 3'd1;
    wait (pipe_phystatus_rst[0] === 1'b0);
    repeat (32) begin
      @(posedge clk);
      pipe_txdata[15:0] <= 16'h0000;
      pipe_txdatak[1:0] <= 2'b00;
      if (pipe_rxvalid[0])
        saw_valid_early = 1'b1;
    end
    if (saw_valid_early)
      $fatal(1, "rxvalid rose before the comma");
    @(posedge clk);
    pipe_txdata[15:0] <= {8'h4A, rivet_pkg::RIVET_SYM_COM};
    pipe_txdatak[1:0] <= 2'b01;
    repeat (12) begin
      @(posedge clk);
      if (pipe_rxvalid[0] && pipe_rxdata[7:0] == rivet_pkg::RIVET_SYM_COM &&
          pipe_rxdatak[0] === 1'b1 && pipe_rxdata[15:8] == 8'h4A) begin
        pipe_txdata[15:0] <= 16'h0000;
        pipe_txdatak[1:0] <= 2'b00;
        repeat (6) @(posedge clk);
        inject_code_err = 1'b1;
        repeat (4) begin
          @(posedge clk);
          if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_DECODE_ERR)
            saw_dec = 1'b1;
        end
        inject_code_err = 1'b0;
        if (!saw_dec)
          $fatal(1, "expected a decode error");
        repeat (4) @(posedge clk);
        inject_disp_err = 1'b1;
        repeat (4) begin
          @(posedge clk);
          if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_DISPARITY)
            saw_disp = 1'b1;
        end
        inject_disp_err = 1'b0;
        if (!saw_disp)
          $fatal(1, "expected a disparity error");
        $display("PASS: phy 8b10b");
        $finish;
      end
    end
    $fatal(1, "comma was not returned");
  end
`else
  initial begin
    $fatal(1, "rivet_phy_pcs_tb: no CASE define");
  end
`endif

endmodule : rivet_phy_pcs_tb
