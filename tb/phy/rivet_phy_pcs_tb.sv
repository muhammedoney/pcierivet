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
  logic                             pclk_gen1;

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
    .pclk_gen1           (pclk_gen1),
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
    logic saw_comma;
    saw_valid_early = 1'b0;
    saw_dec = 1'b0;
    saw_disp = 1'b0;
    saw_comma = 1'b0;
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
    repeat (32) begin
      @(posedge clk);
      if (pipe_rxvalid[0] && pipe_rxdata[7:0] == rivet_pkg::RIVET_SYM_COM &&
          pipe_rxdatak[0] === 1'b1 && pipe_rxdata[15:8] == 8'h4A) begin
        pipe_txdata[15:0] <= 16'h0000;
        pipe_txdatak[1:0] <= 2'b00;
        repeat (6) @(posedge clk);
        inject_code_err = 1'b1;
        repeat (16) begin
          @(posedge clk);
          if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_DECODE_ERR)
            saw_dec = 1'b1;
          if (pipe_rxstatus[2:0] != rivet_pkg::RIVET_RXSTATUS_DECODE_ERR && saw_dec)
            inject_code_err = 1'b0;
        end
        inject_code_err = 1'b0;
        if (!saw_dec)
          $fatal(1, "expected a decode error");
        repeat (8) @(posedge clk);
        inject_disp_err = 1'b1;
        repeat (16) begin
          @(posedge clk);
          if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_DISPARITY)
            saw_disp = 1'b1;
        end
        inject_disp_err = 1'b0;
        if (!saw_disp)
          $fatal(1, "expected a disparity error");
        saw_comma = 1'b1;
        $display("PASS: phy 8b10b");
        $finish;
      end
    end
    if (!saw_comma)
      $fatal(1, "comma was not returned");
  end
`elsif CASE_EB
  initial begin
    logic saw_add;
    logic saw_rem;
    logic saw_ovf;
    integer si;
    saw_add = 1'b0;
    saw_rem = 1'b0;
    saw_ovf = 1'b0;

    repeat (4) @(posedge clk);
    eb_delete_skp = 1'b1;
    preset_n = 1'b1;
    pipe_powerdown = 2'b00;
    pipe_txelecidle = '0;
    pipe_rate = 3'd1;
    wait (pipe_phystatus_rst[0] === 1'b0);
    for (si = 0; si < 64; si++) begin
      @(posedge clk);
      pipe_txdata[15:0] <= {rivet_pkg::RIVET_SYM_SKP, rivet_pkg::RIVET_SYM_COM};
      pipe_txdatak[1:0] <= 2'b11;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_SKP_ADDED)
        saw_add = 1'b1;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_EB_OVERFLOW)
        saw_ovf = 1'b1;
      @(posedge clk);
      pipe_txdata[15:0] <= {rivet_pkg::RIVET_SYM_SKP, rivet_pkg::RIVET_SYM_SKP};
      pipe_txdatak[1:0] <= 2'b11;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_SKP_ADDED)
        saw_add = 1'b1;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_EB_OVERFLOW)
        saw_ovf = 1'b1;
    end
    repeat (16) begin
      @(posedge clk);
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_SKP_ADDED)
        saw_add = 1'b1;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_EB_OVERFLOW)
        saw_ovf = 1'b1;
    end
    if (!saw_add)
      $fatal(1, "expected SKP_ADDED while the model deletes SKP");
    if (saw_ovf)
      $fatal(1, "delete run overflowed the elastic buffer");

    saw_rem = 1'b0;
    saw_ovf = 1'b0;
    preset_n = 1'b0;
    eb_delete_skp = 1'b0;
    eb_insert_skp = 1'b1;
    repeat (4) @(posedge clk);
    preset_n = 1'b1;
    wait (pipe_phystatus_rst[0] === 1'b0);
    for (si = 0; si < 64; si++) begin
      @(posedge clk);
      pipe_txdata[15:0] <= {rivet_pkg::RIVET_SYM_SKP, rivet_pkg::RIVET_SYM_COM};
      pipe_txdatak[1:0] <= 2'b11;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_SKP_REMOVED)
        saw_rem = 1'b1;
      @(posedge clk);
      pipe_txdata[15:0] <= {rivet_pkg::RIVET_SYM_SKP, rivet_pkg::RIVET_SYM_SKP};
      pipe_txdatak[1:0] <= 2'b11;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_SKP_REMOVED)
        saw_rem = 1'b1;
    end
    repeat (16) begin
      @(posedge clk);
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_SKP_REMOVED)
        saw_rem = 1'b1;
    end
    if (!saw_rem)
      $fatal(1, "expected SKP_REMOVED while the model inserts SKP");

    saw_ovf = 1'b0;
    preset_n = 1'b0;
    eb_insert_skp = 1'b0;
    eb_flood = 1'b0;
    repeat (4) @(posedge clk);
    preset_n = 1'b1;
    wait (pipe_phystatus_rst[0] === 1'b0);
    for (si = 0; si < 16; si++) begin
      @(posedge clk);
      pipe_txdata[15:0] <= {rivet_pkg::RIVET_SYM_SKP, rivet_pkg::RIVET_SYM_COM};
      pipe_txdatak[1:0] <= 2'b11;
      @(posedge clk);
      pipe_txdata[15:0] <= {rivet_pkg::RIVET_SYM_SKP, rivet_pkg::RIVET_SYM_SKP};
      pipe_txdatak[1:0] <= 2'b11;
    end
    eb_flood = 1'b1;
    repeat (40) begin
      @(posedge clk);
      pipe_txdata[15:0] <= 16'h0000;
      pipe_txdatak[1:0] <= 2'b00;
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_EB_OVERFLOW)
        saw_ovf = 1'b1;
    end
    repeat (8) begin
      @(posedge clk);
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_EB_OVERFLOW)
        saw_ovf = 1'b1;
    end
    if (!saw_ovf)
      $fatal(1, "expected EB_OVERFLOW while the model floods symbols");
    $display("PASS: phy elastic buffer");
    $finish;
  end
`elsif CASE_CMD
  initial begin
    logic saw_pulse;
    logic saw_bad;
    saw_pulse = 1'b0;
    saw_bad = 1'b0;

    repeat (4) @(posedge clk);
    preset_n = 1'b1;
    pipe_powerdown = 2'b00;
    pipe_txdetectrx = 1'b0;
    pipe_txelecidle = '0;
    pipe_rate = 3'd1;
    wait (pipe_phystatus_rst[0] === 1'b0);

    pipe_txelecidle = '1;
    repeat (4) @(posedge clk);
    if (pipe_rxelecidle[0] !== 1'b1 || u_phy.pma_txelecidle !== 1'b1)
      $fatal(1, "rxelecidle must follow electrical idle");
    pipe_txelecidle = '0;
    pipe_txdetectrx = 1'b0;
    repeat (3) @(posedge clk);
    if (pipe_rxelecidle[0] !== 1'b0)
      $fatal(1, "leaving electrical idle must be accepted");

    pipe_txdetectrx = 1'b1;
    pipe_txelecidle = '1;
    repeat (8) begin
      @(posedge clk);
      if (pipe_phystatus[0] && !pipe_phystatus_rst[0])
        saw_bad = 1'b1;
      if (pipe_rxelecidle[0] !== 1'b0)
        saw_bad = 1'b1;
    end
    if (saw_bad)
      $fatal(1, "illegal P0 detect request must hold the previous command");
    pipe_txdetectrx = 1'b0;
    pipe_txelecidle = '0;
    repeat (2) @(posedge clk);

    pipe_powerdown = 2'b10;
    pipe_txdetectrx = 1'b1;
    pipe_txelecidle = '1;
    saw_pulse = 1'b0;
    repeat (24) begin
      @(posedge clk);
      if (pipe_phystatus[0] && !pipe_phystatus_rst[0] &&
          pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_RX_DETECTED)
        saw_pulse = 1'b1;
    end
    if (!saw_pulse)
      $fatal(1, "receiver detect did not pulse phystatus");

    pipe_powerdown = 2'b00;
    pipe_txdetectrx = 1'b0;
    pipe_txelecidle = '0;
    pipe_rate = 3'd1;
    repeat (4) @(posedge clk);

    pipe_rate = 3'd0;
    saw_pulse = 1'b0;
    repeat (32) begin
      @(posedge clk);
      if (pipe_phystatus[0] && !pipe_phystatus_rst[0]) begin
        saw_pulse = 1'b1;
        if (pclk_gen1 !== 1'b1)
          $fatal(1, "pclk_gen1 must be 1 after the Gen1 rate");
      end
    end
    if (!saw_pulse)
      $fatal(1, "Gen1 rate did not pulse phystatus");

    pipe_rate = 3'd1;
    saw_pulse = 1'b0;
    repeat (32) begin
      @(posedge clk);
      if (pipe_phystatus[0] && !pipe_phystatus_rst[0]) begin
        saw_pulse = 1'b1;
        if (pclk_gen1 !== 1'b0)
          $fatal(1, "pclk_gen1 must be 0 after the Gen2 rate");
      end
    end
    if (!saw_pulse)
      $fatal(1, "Gen2 rate did not pulse phystatus");

    pipe_txdata[15:0] = {8'h00, rivet_pkg::RIVET_SYM_COM};
    pipe_txdatak[1:0] = 2'b01;
    pipe_rxpolarity = '0;
    repeat (8) @(posedge clk);
    pipe_txdata[15:0] = {8'h00, 8'h4A};
    pipe_txdatak[1:0] = 2'b00;
    repeat (20) @(posedge clk);
    saw_pulse = 1'b0;
    repeat (24) begin
      @(posedge clk);
      if (pipe_rxdata[7:0] == 8'h4A)
        saw_pulse = 1'b1;
    end
    if (!saw_pulse)
      $fatal(1, "D10.2 was not returned with polarity clear");

    pipe_rxpolarity = '1;
    saw_pulse = 1'b0;
    repeat (24) begin
      @(posedge clk);
      if (pipe_rxdata[7:0] == 8'hB5)
        saw_pulse = 1'b1;
    end
    if (!saw_pulse)
      $fatal(1, "inverted D10.2 must decode as D21.5");
    pipe_rxpolarity = '0;

    pipe_txdata[15:0] = {8'h00, 8'h00};
    pipe_txdatak[1:0] = 2'b00;
    repeat (16) @(posedge clk);
    pipe_as_cdr_hold_req = 1'b1;
    repeat (4) @(posedge clk);
    inject_code_err = 1'b1;
    saw_bad = 1'b0;
    repeat (8) begin
      @(posedge clk);
      if (pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_DECODE_ERR)
        saw_bad = 1'b1;
    end
    inject_code_err = 1'b0;
    if (saw_bad)
      $fatal(1, "CDR hold invented a decode error");
    pipe_txelecidle = '1;
    repeat (4) @(posedge clk);
    if (pipe_rxelecidle[0] !== 1'b1)
      $fatal(1, "rxelecidle must follow the pin during CDR hold");
    pipe_txelecidle = '0;
    pipe_as_cdr_hold_req = 1'b0;

    pipe_txdata[15:0] = {8'h00, rivet_pkg::RIVET_SYM_COM};
    pipe_txdatak[1:0] = 2'b01;
    pipe_txcompliance = '0;
    repeat (6) begin
      @(posedge clk);
      if (u_phy.u_pcs.rd_tx_q === 1'b0)
        break;
    end
    if (u_phy.u_pcs.rd_tx_q !== 1'b0)
      $fatal(1, "running disparity did not become positive");
    pipe_txcompliance = '1;
    #1;
    if (u_phy.pma_txdata[9:0] !== 10'b0011111010)
      $fatal(1, "compliance must force the negative-disparity comma");
    @(posedge clk);
    pipe_txcompliance = '0;
    saw_bad = 1'b0;
    repeat (20) begin
      @(posedge clk);
      if (pipe_rxvalid[0] && pipe_rxdata[7:0] == rivet_pkg::RIVET_SYM_COM &&
          pipe_rxstatus[2:0] == rivet_pkg::RIVET_RXSTATUS_DISPARITY)
        saw_bad = 1'b1;
    end
    if (saw_bad)
      $fatal(1, "a legal compliance symbol reported disparity");

    $display("PASS: phy command");
    $finish;
  end
`else
  initial begin
    $fatal(1, "rivet_phy_pcs_tb: no CASE define");
  end
`endif

endmodule : rivet_phy_pcs_tb
