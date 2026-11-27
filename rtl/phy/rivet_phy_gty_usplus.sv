// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// VCU118 GTY PMA for the soft PCS. Generated port tie-offs come from
// the Vivado 2024.2 unisims via scripts/gen_gty_usplus.py.
// GTYE4_CHANNEL and GTYE4_COMMON are the only vendor cells.
//
// The fabric PCS owns 8b/10b and 128b/130b. The channel encoder is
// bypassed while SOFT_8B10B is 1. PMA_BITS follows the elaborated PIPE
// width (20, 32, or 64). TXRATE/RXRATE select the PLL. A DRP write that
// changes the parallel width at run time is not in this wrapper.
//
// Quad 227: lane 0 is GTYE4_CHANNEL_X1Y35, then Y34, Y33, Y32.
// The common for that quad is GTYE4_COMMON_X1Y8.
// pclk and user_clk are separate BUFG_GT outputs. They are not tied.

module rivet_phy_gty_usplus #(
  parameter int unsigned LANES           = 1,
  parameter int unsigned PIPE_DATA_WIDTH = 16,
  parameter int unsigned SOFT_8B10B      = 1
) (
  input  logic                    phy_refclk,
  input  logic                    phy_gtrefclk,
  input  logic                    phy_rst_n,

  output logic                    pclk,
  output logic                    user_clk,
  output logic [LANES-1:0]        gt_gtpowergood,

  output logic [LANES-1:0]        pci_exp_txp,
  output logic [LANES-1:0]        pci_exp_txn,
  input  logic [LANES-1:0]        pci_exp_rxp,
  input  logic [LANES-1:0]        pci_exp_rxn,

  input  logic [64*LANES-1:0]     pma_txdata,
  input  logic [5:0]              pma_txwidth,
  input  logic                    pma_txelecidle,
  input  logic                    pma_txdetectrx,
  input  logic                    pma_txpolarity,
  input  logic [4:0]              pma_txdiffctrl,
  input  logic [4:0]              pma_txprecursor,
  input  logic [6:0]              pma_txmaincursor,
  input  logic [4:0]              pma_txpostcursor,
  input  logic                    pma_rxslide,
  input  logic [2:0]              pma_rate,

  output logic [64*LANES-1:0]     pma_rxdata,
  output logic                    pma_rxelecidle,
  output logic                    pma_rxdetected,
  output logic                    pma_resetdone,
  output logic                    pma_pll_lock
);

  localparam int unsigned PMA_BITS = (PIPE_DATA_WIDTH == 64) ? 64 :
                                     (PIPE_DATA_WIDTH == 32) ? 32 : 20;

  // UG578 TXPLLCLKSEL: 00 CPLL, 10 QPLL1, 11 QPLL0.
  // TXSYSCLKSEL:       00 CPLL, 11 QPLL1, 10 QPLL0.
  wire [1:0] pll_sel = (pma_rate == 3'd0) ? 2'b00 :
                       (pma_rate == 3'd3) ? 2'b11 : 2'b10;
  wire [1:0] sys_sel = (pma_rate == 3'd0) ? 2'b00 :
                       (pma_rate == 3'd3) ? 2'b10 : 2'b11;
  wire use_hard_8b10b = (SOFT_8B10B == 0);

  logic qpll0lock, qpll1lock, qpll0clk, qpll0refclk, qpll1clk, qpll1refclk;
  logic [LANES-1:0] rxelecidle_l, phystatus_l, txoutclk_l;
  logic [LANES-1:0] txresetdone_l, rxresetdone_l, txdivdone_l, rxdivdone_l, cplllock_l;
  logic [2:0] rxstatus_l [LANES];
  logic [127:0] rx_raw [LANES];
  logic [127:0] tx_pad [LANES];

  typedef enum logic [2:0] {
    ST_PWR, ST_PLL, ST_DIV, ST_USR, ST_SYNC, ST_RUN
  } rst_st_e;

  rst_st_e st_q;
  logic [2:0] sync_q;
  wire pll_reset = (st_q == ST_PWR);
  wire div_reset = (st_q == ST_PWR) || (st_q == ST_PLL);
  wire gt_reset  = (st_q == ST_PWR) || (st_q == ST_PLL) || (st_q == ST_DIV);
  wire gt_userrdy = (st_q == ST_USR) || (st_q == ST_SYNC) || (st_q == ST_RUN);
  wire pll_locked = (pll_sel == 2'b00) ? cplllock_l[0] :
                    (pll_sel == 2'b11) ? qpll0lock : qpll1lock;

  assign pma_pll_lock = (st_q == ST_RUN);
  assign pma_rxelecidle = rxelecidle_l[0];

  always_comb begin
    for (int li = 0; li < LANES; li++) begin
      tx_pad[li] = '0;
      tx_pad[li][63:0] = pma_txdata[64*li +: 64];
      pma_rxdata[64*li +: 64] = rx_raw[li][63:0];
    end
  end

  always_ff @(posedge phy_refclk or negedge phy_rst_n) begin
    if (!phy_rst_n) begin
      st_q          <= ST_PWR;
      sync_q        <= '0;
      pma_resetdone <= 1'b0;
    end else begin
      case (st_q)
        ST_PWR: if (&gt_gtpowergood) st_q <= ST_PLL;
        ST_PLL: if (pll_locked) st_q <= ST_DIV;
        ST_DIV: if (txdivdone_l[0] && rxdivdone_l[0]) st_q <= ST_USR;
        ST_USR: if (txresetdone_l[0] && rxresetdone_l[0]) begin
          st_q   <= ST_SYNC;
          sync_q <= '0;
        end
        ST_SYNC: begin
          sync_q <= sync_q + 3'd1;
          if (sync_q == 3'd3) begin
            st_q          <= ST_RUN;
            pma_resetdone <= 1'b1;
          end
        end
        ST_RUN: if (!pll_locked) begin
          st_q          <= ST_PLL;
          pma_resetdone <= 1'b0;
        end
        default: st_q <= ST_PWR;
      endcase
    end
  end

  logic det_q;
  always_ff @(posedge pclk or negedge phy_rst_n) begin
    if (!phy_rst_n) begin
      det_q          <= 1'b0;
      pma_rxdetected <= 1'b0;
    end else begin
      det_q <= pma_txdetectrx && phystatus_l[0] && (rxstatus_l[0] == 3'b011);
      pma_rxdetected <= pma_txdetectrx && phystatus_l[0] &&
                        (rxstatus_l[0] == 3'b011) && !det_q;
    end
  end

  // Two buffers on one TXOUTCLK. Vivado requires the same CLR net
  // (Opt 31-215). CLRMASK keeps user_clk running. pclk is held until
  // the reset FSM reaches ST_RUN, and it divides by two at Gen1.
  wire bufg_clr = (st_q != ST_RUN);
  BUFG_GT u_pclk (
    .CE      (gt_gtpowergood[0]),
    .CEMASK  (1'b0),
    .CLR     (bufg_clr),
    .CLRMASK (1'b0),
    .DIV     (pma_rate == 3'd0 ? 3'd1 : 3'd0),
    .I       (txoutclk_l[0]),
    .O       (pclk)
  );
  BUFG_GT u_user (
    .CE      (gt_gtpowergood[0]),
    .CEMASK  (1'b0),
    .CLR     (bufg_clr),
    .CLRMASK (1'b1),
    .DIV     (3'd0),
    .I       (txoutclk_l[0]),
    .O       (user_clk)
  );

    wire [15:0] u_DRPDO;
    wire  u_DRPRDY;
    wire [7:0] u_PMARSVDOUT0;
    wire [7:0] u_PMARSVDOUT1;
    wire  u_QPLL0FBCLKLOST;
    wire  u_QPLL0REFCLKLOST;
    wire  u_QPLL1FBCLKLOST;
    wire  u_QPLL1REFCLKLOST;
    wire [7:0] u_QPLLDMONITOR0;
    wire [7:0] u_QPLLDMONITOR1;
    wire  u_REFCLKOUTMONITOR0;
    wire  u_REFCLKOUTMONITOR1;
    wire [1:0] u_RXRECCLK0SEL;
    wire [1:0] u_RXRECCLK1SEL;
    wire [3:0] u_SDM0FINALOUT;
    wire [14:0] u_SDM0TESTDATA;
    wire [3:0] u_SDM1FINALOUT;
    wire [14:0] u_SDM1TESTDATA;
    wire [15:0] u_UBDADDR;
    wire  u_UBDEN;
    wire [15:0] u_UBDI;
    wire  u_UBDWE;
    wire  u_UBMDMTDO;
    wire  u_UBRSVDOUT;
    wire  u_UBTXUART;

    (* LOC = "GTYE4_COMMON_X1Y8" *)
    GTYE4_COMMON u_common (
      .DRPDO(u_DRPDO),
      .DRPRDY(u_DRPRDY),
      .PMARSVDOUT0(u_PMARSVDOUT0),
      .PMARSVDOUT1(u_PMARSVDOUT1),
      .QPLL0FBCLKLOST(u_QPLL0FBCLKLOST),
      .QPLL0LOCK(qpll0lock),
      .QPLL0OUTCLK(qpll0clk),
      .QPLL0OUTREFCLK(qpll0refclk),
      .QPLL0REFCLKLOST(u_QPLL0REFCLKLOST),
      .QPLL1FBCLKLOST(u_QPLL1FBCLKLOST),
      .QPLL1LOCK(qpll1lock),
      .QPLL1OUTCLK(qpll1clk),
      .QPLL1OUTREFCLK(qpll1refclk),
      .QPLL1REFCLKLOST(u_QPLL1REFCLKLOST),
      .QPLLDMONITOR0(u_QPLLDMONITOR0),
      .QPLLDMONITOR1(u_QPLLDMONITOR1),
      .REFCLKOUTMONITOR0(u_REFCLKOUTMONITOR0),
      .REFCLKOUTMONITOR1(u_REFCLKOUTMONITOR1),
      .RXRECCLK0SEL(u_RXRECCLK0SEL),
      .RXRECCLK1SEL(u_RXRECCLK1SEL),
      .SDM0FINALOUT(u_SDM0FINALOUT),
      .SDM0TESTDATA(u_SDM0TESTDATA),
      .SDM1FINALOUT(u_SDM1FINALOUT),
      .SDM1TESTDATA(u_SDM1TESTDATA),
      .UBDADDR(u_UBDADDR),
      .UBDEN(u_UBDEN),
      .UBDI(u_UBDI),
      .UBDWE(u_UBDWE),
      .UBMDMTDO(u_UBMDMTDO),
      .UBRSVDOUT(u_UBRSVDOUT),
      .UBTXUART(u_UBTXUART),
      .BGBYPASSB('0),
      .BGMONITORENB('0),
      .BGPDB('0),
      .BGRCALOVRD('0),
      .BGRCALOVRDENB('0),
      .DRPADDR('0),
      .DRPCLK('0),
      .DRPDI('0),
      .DRPEN('0),
      .DRPWE('0),
      .GTGREFCLK0('0),
      .GTGREFCLK1('0),
      .GTNORTHREFCLK00('0),
      .GTNORTHREFCLK01('0),
      .GTNORTHREFCLK10('0),
      .GTNORTHREFCLK11('0),
      .GTREFCLK00(phy_gtrefclk),
      .GTREFCLK01('0),
      .GTREFCLK10(phy_gtrefclk),
      .GTREFCLK11('0),
      .GTSOUTHREFCLK00('0),
      .GTSOUTHREFCLK01('0),
      .GTSOUTHREFCLK10('0),
      .GTSOUTHREFCLK11('0),
      .PCIERATEQPLL0('0),
      .PCIERATEQPLL1('0),
      .PMARSVD0('0),
      .PMARSVD1('0),
      .QPLL0CLKRSVD0('0),
      .QPLL0CLKRSVD1('0),
      .QPLL0FBDIV('0),
      .QPLL0LOCKDETCLK(phy_refclk),
      .QPLL0LOCKEN(1'b1),
      .QPLL0PD(1'b0),
      .QPLL0REFCLKSEL(3'b001),
      .QPLL0RESET(pll_reset),
      .QPLL1CLKRSVD0('0),
      .QPLL1CLKRSVD1('0),
      .QPLL1FBDIV('0),
      .QPLL1LOCKDETCLK(phy_refclk),
      .QPLL1LOCKEN(1'b1),
      .QPLL1PD(1'b0),
      .QPLL1REFCLKSEL(3'b001),
      .QPLL1RESET(pll_reset),
      .QPLLRSVD1('0),
      .QPLLRSVD2('0),
      .QPLLRSVD3('0),
      .QPLLRSVD4('0),
      .RCALENB('0),
      .SDM0DATA('0),
      .SDM0RESET('0),
      .SDM0TOGGLE('0),
      .SDM0WIDTH('0),
      .SDM1DATA('0),
      .SDM1RESET('0),
      .SDM1TOGGLE('0),
      .SDM1WIDTH('0),
      .UBCFGSTREAMEN('0),
      .UBDO('0),
      .UBDRDY('0),
      .UBENABLE('0),
      .UBGPI('0),
      .UBINTR('0),
      .UBIOLMBRST('0),
      .UBMBRST('0),
      .UBMDMCAPTURE('0),
      .UBMDMDBGRST('0),
      .UBMDMDBGUPDATE('0),
      .UBMDMREGEN('0),
      .UBMDMSHIFT('0),
      .UBMDMSYSRST('0),
      .UBMDMTCK('0),
      .UBMDMTDI('0)
    );

  for (genvar li = 0; li < LANES; li++) begin : g_lane
      wire  u_BUFGTCE;
      wire [2:0] u_BUFGTCEMASK;
      wire [8:0] u_BUFGTDIV;
      wire  u_BUFGTRESET;
      wire [2:0] u_BUFGTRSTMASK;
      wire  u_CPLLFBCLKLOST;
      wire  u_CPLLREFCLKLOST;
      wire [15:0] u_DMONITOROUT;
      wire  u_DMONITOROUTCLK;
      wire [15:0] u_DRPDO;
      wire  u_DRPRDY;
      wire  u_EYESCANDATAERROR;
      wire  u_GTREFCLKMONITOR;
      wire  u_PCIERATEGEN3;
      wire  u_PCIERATEIDLE;
      wire [1:0] u_PCIERATEQPLLPD;
      wire [1:0] u_PCIERATEQPLLRESET;
      wire  u_PCIESYNCTXSYNCDONE;
      wire  u_PCIEUSERGEN3RDY;
      wire  u_PCIEUSERPHYSTATUSRST;
      wire  u_PCIEUSERRATESTART;
      wire [15:0] u_PCSRSVDOUT;
      wire [15:0] u_PINRSRVDAS;
      wire  u_POWERPRESENT;
      wire  u_RESETEXCEPTION;
      wire [2:0] u_RXBUFSTATUS;
      wire  u_RXBYTEISALIGNED;
      wire  u_RXBYTEREALIGN;
      wire  u_RXCDRLOCK;
      wire  u_RXCDRPHDONE;
      wire  u_RXCHANBONDSEQ;
      wire  u_RXCHANISALIGNED;
      wire  u_RXCHANREALIGN;
      wire [4:0] u_RXCHBONDO;
      wire  u_RXCKCALDONE;
      wire [1:0] u_RXCLKCORCNT;
      wire  u_RXCOMINITDET;
      wire  u_RXCOMMADET;
      wire  u_RXCOMSASDET;
      wire  u_RXCOMWAKEDET;
      wire [15:0] u_RXCTRL0;
      wire [15:0] u_RXCTRL1;
      wire [7:0] u_RXCTRL2;
      wire [7:0] u_RXCTRL3;
      wire [7:0] u_RXDATAEXTENDRSVD;
      wire [1:0] u_RXDATAVALID;
      wire  u_RXDLYSRESETDONE;
      wire [5:0] u_RXHEADER;
      wire [1:0] u_RXHEADERVALID;
      wire  u_RXLFPSTRESETDET;
      wire  u_RXLFPSU2LPEXITDET;
      wire  u_RXLFPSU3WAKEDET;
      wire [7:0] u_RXMONITOROUT;
      wire  u_RXOSINTDONE;
      wire  u_RXOSINTSTARTED;
      wire  u_RXOSINTSTROBEDONE;
      wire  u_RXOSINTSTROBESTARTED;
      wire  u_RXOUTCLK;
      wire  u_RXOUTCLKFABRIC;
      wire  u_RXOUTCLKPCS;
      wire  u_RXPHALIGNDONE;
      wire  u_RXPHALIGNERR;
      wire  u_RXPMARESETDONE;
      wire  u_RXPRBSERR;
      wire  u_RXPRBSLOCKED;
      wire  u_RXRATEDONE;
      wire  u_RXRECCLKOUT;
      wire  u_RXSLIDERDY;
      wire  u_RXSLIPDONE;
      wire  u_RXSLIPOUTCLKRDY;
      wire  u_RXSLIPPMARDY;
      wire [1:0] u_RXSTARTOFSEQ;
      wire  u_RXSYNCDONE;
      wire  u_RXSYNCOUT;
      wire  u_RXVALID;
      wire [1:0] u_TXBUFSTATUS;
      wire  u_TXCOMFINISH;
      wire  u_TXDCCDONE;
      wire  u_TXDLYSRESETDONE;
      wire  u_TXOUTCLKFABRIC;
      wire  u_TXOUTCLKPCS;
      wire  u_TXPHALIGNDONE;
      wire  u_TXPHINITDONE;
      wire  u_TXPMARESETDONE;
      wire  u_TXRATEDONE;
      wire  u_TXSYNCDONE;
      wire  u_TXSYNCOUT;

      GTYE4_CHANNEL #(
        .TX_DATA_WIDTH      (PMA_BITS),
        .RX_DATA_WIDTH      (PMA_BITS),
        .RXSLIDE_MODE       ("PMA"),
        .DEC_MCOMMA_DETECT  ("FALSE"),
        .DEC_PCOMMA_DETECT  ("FALSE"),
        .ALIGN_COMMA_ENABLE (10'b0000000000)
      ) u_ch (
        .BUFGTCE(u_BUFGTCE),
        .BUFGTCEMASK(u_BUFGTCEMASK),
        .BUFGTDIV(u_BUFGTDIV),
        .BUFGTRESET(u_BUFGTRESET),
        .BUFGTRSTMASK(u_BUFGTRSTMASK),
        .CPLLFBCLKLOST(u_CPLLFBCLKLOST),
        .CPLLLOCK(cplllock_l[li]),
        .CPLLREFCLKLOST(u_CPLLREFCLKLOST),
        .DMONITOROUT(u_DMONITOROUT),
        .DMONITOROUTCLK(u_DMONITOROUTCLK),
        .DRPDO(u_DRPDO),
        .DRPRDY(u_DRPRDY),
        .EYESCANDATAERROR(u_EYESCANDATAERROR),
        .GTPOWERGOOD(gt_gtpowergood[li]),
        .GTREFCLKMONITOR(u_GTREFCLKMONITOR),
        .GTYTXN(pci_exp_txn[li]),
        .GTYTXP(pci_exp_txp[li]),
        .PCIERATEGEN3(u_PCIERATEGEN3),
        .PCIERATEIDLE(u_PCIERATEIDLE),
        .PCIERATEQPLLPD(u_PCIERATEQPLLPD),
        .PCIERATEQPLLRESET(u_PCIERATEQPLLRESET),
        .PCIESYNCTXSYNCDONE(u_PCIESYNCTXSYNCDONE),
        .PCIEUSERGEN3RDY(u_PCIEUSERGEN3RDY),
        .PCIEUSERPHYSTATUSRST(u_PCIEUSERPHYSTATUSRST),
        .PCIEUSERRATESTART(u_PCIEUSERRATESTART),
        .PCSRSVDOUT(u_PCSRSVDOUT),
        .PHYSTATUS(phystatus_l[li]),
        .PINRSRVDAS(u_PINRSRVDAS),
        .POWERPRESENT(u_POWERPRESENT),
        .RESETEXCEPTION(u_RESETEXCEPTION),
        .RXBUFSTATUS(u_RXBUFSTATUS),
        .RXBYTEISALIGNED(u_RXBYTEISALIGNED),
        .RXBYTEREALIGN(u_RXBYTEREALIGN),
        .RXCDRLOCK(u_RXCDRLOCK),
        .RXCDRPHDONE(u_RXCDRPHDONE),
        .RXCHANBONDSEQ(u_RXCHANBONDSEQ),
        .RXCHANISALIGNED(u_RXCHANISALIGNED),
        .RXCHANREALIGN(u_RXCHANREALIGN),
        .RXCHBONDO(u_RXCHBONDO),
        .RXCKCALDONE(u_RXCKCALDONE),
        .RXCLKCORCNT(u_RXCLKCORCNT),
        .RXCOMINITDET(u_RXCOMINITDET),
        .RXCOMMADET(u_RXCOMMADET),
        .RXCOMSASDET(u_RXCOMSASDET),
        .RXCOMWAKEDET(u_RXCOMWAKEDET),
        .RXCTRL0(u_RXCTRL0),
        .RXCTRL1(u_RXCTRL1),
        .RXCTRL2(u_RXCTRL2),
        .RXCTRL3(u_RXCTRL3),
        .RXDATA(rx_raw[li]),
        .RXDATAEXTENDRSVD(u_RXDATAEXTENDRSVD),
        .RXDATAVALID(u_RXDATAVALID),
        .RXDLYSRESETDONE(u_RXDLYSRESETDONE),
        .RXELECIDLE(rxelecidle_l[li]),
        .RXHEADER(u_RXHEADER),
        .RXHEADERVALID(u_RXHEADERVALID),
        .RXLFPSTRESETDET(u_RXLFPSTRESETDET),
        .RXLFPSU2LPEXITDET(u_RXLFPSU2LPEXITDET),
        .RXLFPSU3WAKEDET(u_RXLFPSU3WAKEDET),
        .RXMONITOROUT(u_RXMONITOROUT),
        .RXOSINTDONE(u_RXOSINTDONE),
        .RXOSINTSTARTED(u_RXOSINTSTARTED),
        .RXOSINTSTROBEDONE(u_RXOSINTSTROBEDONE),
        .RXOSINTSTROBESTARTED(u_RXOSINTSTROBESTARTED),
        .RXOUTCLK(u_RXOUTCLK),
        .RXOUTCLKFABRIC(u_RXOUTCLKFABRIC),
        .RXOUTCLKPCS(u_RXOUTCLKPCS),
        .RXPHALIGNDONE(u_RXPHALIGNDONE),
        .RXPHALIGNERR(u_RXPHALIGNERR),
        .RXPMARESETDONE(u_RXPMARESETDONE),
        .RXPRBSERR(u_RXPRBSERR),
        .RXPRBSLOCKED(u_RXPRBSLOCKED),
        .RXPRGDIVRESETDONE(rxdivdone_l[li]),
        .RXRATEDONE(u_RXRATEDONE),
        .RXRECCLKOUT(u_RXRECCLKOUT),
        .RXRESETDONE(rxresetdone_l[li]),
        .RXSLIDERDY(u_RXSLIDERDY),
        .RXSLIPDONE(u_RXSLIPDONE),
        .RXSLIPOUTCLKRDY(u_RXSLIPOUTCLKRDY),
        .RXSLIPPMARDY(u_RXSLIPPMARDY),
        .RXSTARTOFSEQ(u_RXSTARTOFSEQ),
        .RXSTATUS(rxstatus_l[li]),
        .RXSYNCDONE(u_RXSYNCDONE),
        .RXSYNCOUT(u_RXSYNCOUT),
        .RXVALID(u_RXVALID),
        .TXBUFSTATUS(u_TXBUFSTATUS),
        .TXCOMFINISH(u_TXCOMFINISH),
        .TXDCCDONE(u_TXDCCDONE),
        .TXDLYSRESETDONE(u_TXDLYSRESETDONE),
        .TXOUTCLK(txoutclk_l[li]),
        .TXOUTCLKFABRIC(u_TXOUTCLKFABRIC),
        .TXOUTCLKPCS(u_TXOUTCLKPCS),
        .TXPHALIGNDONE(u_TXPHALIGNDONE),
        .TXPHINITDONE(u_TXPHINITDONE),
        .TXPMARESETDONE(u_TXPMARESETDONE),
        .TXPRGDIVRESETDONE(txdivdone_l[li]),
        .TXRATEDONE(u_TXRATEDONE),
        .TXRESETDONE(txresetdone_l[li]),
        .TXSYNCDONE(u_TXSYNCDONE),
        .TXSYNCOUT(u_TXSYNCOUT),
        .CDRSTEPDIR('0),
        .CDRSTEPSQ('0),
        .CDRSTEPSX('0),
        .CFGRESET('0),
        .CLKRSVD0('0),
        .CLKRSVD1('0),
        .CPLLFREQLOCK('0),
        .CPLLLOCKDETCLK(phy_refclk),
        .CPLLLOCKEN(1'b1),
        .CPLLPD('0),
        .CPLLREFCLKSEL(3'b001),
        .CPLLRESET(pll_reset),
        .DMONFIFORESET('0),
        .DMONITORCLK('0),
        .DRPADDR('0),
        .DRPCLK('0),
        .DRPDI('0),
        .DRPEN('0),
        .DRPRST('0),
        .DRPWE('0),
        .EYESCANRESET('0),
        .EYESCANTRIGGER('0),
        .FREQOS('0),
        .GTGREFCLK('0),
        .GTNORTHREFCLK0('0),
        .GTNORTHREFCLK1('0),
        .GTREFCLK0(phy_gtrefclk),
        .GTREFCLK1('0),
        .GTRSVD('0),
        .GTRXRESET(gt_reset),
        .GTRXRESETSEL('0),
        .GTSOUTHREFCLK0('0),
        .GTSOUTHREFCLK1('0),
        .GTTXRESET(gt_reset),
        .GTTXRESETSEL('0),
        .GTYRXN(pci_exp_rxn[li]),
        .GTYRXP(pci_exp_rxp[li]),
        .INCPCTRL('0),
        .LOOPBACK('0),
        .PCIEEQRXEQADAPTDONE('0),
        .PCIERSTIDLE('0),
        .PCIERSTTXSYNCSTART('0),
        .PCIEUSERRATEDONE('0),
        .PCSRSVDIN('0),
        .QPLL0CLK(qpll0clk),
        .QPLL0FREQLOCK('0),
        .QPLL0REFCLK(qpll0refclk),
        .QPLL1CLK(qpll1clk),
        .QPLL1FREQLOCK('0),
        .QPLL1REFCLK(qpll1refclk),
        .RESETOVRD('0),
        .RX8B10BEN(use_hard_8b10b),
        .RXAFECFOKEN('0),
        .RXBUFRESET('0),
        .RXCDRFREQRESET('0),
        .RXCDRHOLD('0),
        .RXCDROVRDEN('0),
        .RXCDRRESET('0),
        .RXCHBONDEN('0),
        .RXCHBONDI('0),
        .RXCHBONDLEVEL('0),
        .RXCHBONDMASTER('0),
        .RXCHBONDSLAVE('0),
        .RXCKCALRESET('0),
        .RXCKCALSTART('0),
        .RXCOMMADETEN('0),
        .RXDFEAGCHOLD('0),
        .RXDFEAGCOVRDEN('0),
        .RXDFECFOKFCNUM('0),
        .RXDFECFOKFEN('0),
        .RXDFECFOKFPULSE('0),
        .RXDFECFOKHOLD('0),
        .RXDFECFOKOVREN('0),
        .RXDFEKHHOLD('0),
        .RXDFEKHOVRDEN('0),
        .RXDFELFHOLD('0),
        .RXDFELFOVRDEN('0),
        .RXDFELPMRESET('0),
        .RXDFETAP10HOLD('0),
        .RXDFETAP10OVRDEN('0),
        .RXDFETAP11HOLD('0),
        .RXDFETAP11OVRDEN('0),
        .RXDFETAP12HOLD('0),
        .RXDFETAP12OVRDEN('0),
        .RXDFETAP13HOLD('0),
        .RXDFETAP13OVRDEN('0),
        .RXDFETAP14HOLD('0),
        .RXDFETAP14OVRDEN('0),
        .RXDFETAP15HOLD('0),
        .RXDFETAP15OVRDEN('0),
        .RXDFETAP2HOLD('0),
        .RXDFETAP2OVRDEN('0),
        .RXDFETAP3HOLD('0),
        .RXDFETAP3OVRDEN('0),
        .RXDFETAP4HOLD('0),
        .RXDFETAP4OVRDEN('0),
        .RXDFETAP5HOLD('0),
        .RXDFETAP5OVRDEN('0),
        .RXDFETAP6HOLD('0),
        .RXDFETAP6OVRDEN('0),
        .RXDFETAP7HOLD('0),
        .RXDFETAP7OVRDEN('0),
        .RXDFETAP8HOLD('0),
        .RXDFETAP8OVRDEN('0),
        .RXDFETAP9HOLD('0),
        .RXDFETAP9OVRDEN('0),
        .RXDFEUTHOLD('0),
        .RXDFEUTOVRDEN('0),
        .RXDFEVPHOLD('0),
        .RXDFEVPOVRDEN('0),
        .RXDFEXYDEN('0),
        .RXDLYBYPASS('0),
        .RXDLYEN('0),
        .RXDLYOVRDEN('0),
        .RXDLYSRESET('0),
        .RXELECIDLEMODE('0),
        .RXEQTRAINING('0),
        .RXGEARBOXSLIP('0),
        .RXLATCLK('0),
        .RXLPMEN('0),
        .RXLPMGCHOLD('0),
        .RXLPMGCOVRDEN('0),
        .RXLPMHFHOLD('0),
        .RXLPMHFOVRDEN('0),
        .RXLPMLFHOLD('0),
        .RXLPMLFKLOVRDEN('0),
        .RXLPMOSHOLD('0),
        .RXLPMOSOVRDEN('0),
        .RXMCOMMAALIGNEN('0),
        .RXMONITORSEL('0),
        .RXOOBRESET('0),
        .RXOSCALRESET('0),
        .RXOSHOLD('0),
        .RXOSOVRDEN('0),
        .RXOUTCLKSEL(3'b101),
        .RXPCOMMAALIGNEN('0),
        .RXPCSRESET('0),
        .RXPD(2'b00),
        .RXPHALIGN('0),
        .RXPHALIGNEN('0),
        .RXPHDLYPD('0),
        .RXPHDLYRESET('0),
        .RXPLLCLKSEL(pll_sel),
        .RXPMARESET('0),
        .RXPOLARITY(1'b0),
        .RXPRBSCNTRESET('0),
        .RXPRBSSEL('0),
        .RXPROGDIVRESET(div_reset),
        .RXRATE(pma_rate),
        .RXRATEMODE('0),
        .RXSLIDE(pma_rxslide),
        .RXSLIPOUTCLK('0),
        .RXSLIPPMA('0),
        .RXSYNCALLIN('0),
        .RXSYNCIN('0),
        .RXSYNCMODE('0),
        .RXSYSCLKSEL(sys_sel),
        .RXTERMINATION('0),
        .RXUSERRDY(gt_userrdy),
        .RXUSRCLK(pclk),
        .RXUSRCLK2(pclk),
        .SIGVALIDCLK('0),
        .TSTIN('0),
        .TX8B10BBYPASS('0),
        .TX8B10BEN(use_hard_8b10b),
        .TXCOMINIT('0),
        .TXCOMSAS('0),
        .TXCOMWAKE('0),
        .TXCTRL0('0),
        .TXCTRL1('0),
        .TXCTRL2('0),
        .TXDATA(tx_pad[li]),
        .TXDATAEXTENDRSVD('0),
        .TXDCCFORCESTART('0),
        .TXDCCRESET('0),
        .TXDEEMPH('0),
        .TXDETECTRX(pma_txdetectrx),
        .TXDIFFCTRL(pma_txdiffctrl),
        .TXDLYBYPASS('0),
        .TXDLYEN('0),
        .TXDLYHOLD('0),
        .TXDLYOVRDEN('0),
        .TXDLYSRESET('0),
        .TXDLYUPDOWN('0),
        .TXELECIDLE(pma_txelecidle),
        .TXHEADER('0),
        .TXINHIBIT('0),
        .TXLATCLK('0),
        .TXLFPSTRESET('0),
        .TXLFPSU2LPEXIT('0),
        .TXLFPSU3WAKE('0),
        .TXMAINCURSOR(pma_txmaincursor),
        .TXMARGIN('0),
        .TXMUXDCDEXHOLD('0),
        .TXMUXDCDORWREN('0),
        .TXONESZEROS('0),
        .TXOUTCLKSEL(3'b101),
        .TXPCSRESET('0),
        .TXPD(2'b00),
        .TXPDELECIDLEMODE('0),
        .TXPHALIGN('0),
        .TXPHALIGNEN('0),
        .TXPHDLYPD('0),
        .TXPHDLYRESET('0),
        .TXPHDLYTSTCLK('0),
        .TXPHINIT('0),
        .TXPHOVRDEN('0),
        .TXPIPPMEN('0),
        .TXPIPPMOVRDEN('0),
        .TXPIPPMPD('0),
        .TXPIPPMSEL('0),
        .TXPIPPMSTEPSIZE('0),
        .TXPISOPD('0),
        .TXPLLCLKSEL(pll_sel),
        .TXPMARESET('0),
        .TXPOLARITY(pma_txpolarity),
        .TXPOSTCURSOR(pma_txpostcursor),
        .TXPRBSFORCEERR('0),
        .TXPRBSSEL('0),
        .TXPRECURSOR(pma_txprecursor),
        .TXPROGDIVRESET(div_reset),
        .TXRATE(pma_rate),
        .TXRATEMODE('0),
        .TXSEQUENCE('0),
        .TXSWING('0),
        .TXSYNCALLIN('0),
        .TXSYNCIN('0),
        .TXSYNCMODE('0),
        .TXSYSCLKSEL(sys_sel),
        .TXUSERRDY(gt_userrdy),
        .TXUSRCLK(pclk),
        .TXUSRCLK2(pclk)
      );
  end

  wire _unused = |pma_txwidth;

endmodule : rivet_phy_gty_usplus
