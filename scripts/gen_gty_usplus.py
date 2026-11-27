#!/usr/bin/env python3
# Copyright 2026 Rivet contributors
# Emit rtl/phy/rivet_phy_gty_usplus.sv from the Vivado unisim port lists.
# Every primitive port is connected. Inputs that this PHY does not drive
# are tied off. Re-run if the unisim port list changes:
#   python scripts/gen_gty_usplus.py

import re
from pathlib import Path

UNISIM = Path(r"D:\Xilinx\Vivado\2024.2\data\verilog\src\unisims")
OUT = Path(__file__).resolve().parents[1] / "rtl" / "phy" / "rivet_phy_gty_usplus.sv"

# line ranges are the port lists only (1-based, inclusive)
CHANNEL_PORTS = (521, 853)
COMMON_PORTS = (119, 223)


def parse_ports(path: Path, start: int, end: int):
    lines = path.read_text(encoding="latin1").splitlines()
    found = []
    for line in lines[start - 1 : end]:
        text = line.strip().rstrip(",")
        if text == "":
            continue
        match = re.match(r"(input|output|inout)\s+(\[[^\]]+\])?\s*(\w+)\s*$", text)
        if not match:
            raise SystemExit(f"unparsed port line in {path.name}: {line}")
        found.append((match.group(1), match.group(2) or "", match.group(3)))
    return found


def width_of(spec: str) -> int:
    if not spec:
        return 1
    match = re.match(r"\[(\d+)\s*:\s*(\d+)\]", spec)
    if not match:
        raise SystemExit(f"bad width {spec}")
    hi, lo = int(match.group(1)), int(match.group(2))
    return abs(hi - lo) + 1


CH_IN = {
    "GTYRXP": "pci_exp_rxp[li]",
    "GTYRXN": "pci_exp_rxn[li]",
    "GTREFCLK0": "phy_gtrefclk",
    "TXDATA": "tx_pad[li]",
    "TXELECIDLE": "pma_txelecidle",
    "TXDETECTRX": "pma_txdetectrx",
    "TXDIFFCTRL": "pma_txdiffctrl",
    "TXPRECURSOR": "pma_txprecursor",
    "TXPOSTCURSOR": "pma_txpostcursor",
    "TXMAINCURSOR": "pma_txmaincursor",
    "TXPOLARITY": "pma_txpolarity",
    "RXPOLARITY": "1'b0",
    "TXRATE": "pma_rate",
    "RXRATE": "pma_rate",
    "RXSLIDE": "pma_rxslide",
    "TX8B10BEN": "use_hard_8b10b",
    "RX8B10BEN": "use_hard_8b10b",
    "CPLLRESET": "pll_reset",
    "GTTXRESET": "gt_reset",
    "GTRXRESET": "gt_reset",
    "TXUSERRDY": "gt_userrdy",
    "RXUSERRDY": "gt_userrdy",
    "TXPROGDIVRESET": "div_reset",
    "RXPROGDIVRESET": "div_reset",
    "TXUSRCLK": "pclk",
    "TXUSRCLK2": "pclk",
    "RXUSRCLK": "pclk",
    "RXUSRCLK2": "pclk",
    "TXPLLCLKSEL": "pll_sel",
    "RXPLLCLKSEL": "pll_sel",
    "TXSYSCLKSEL": "sys_sel",
    "RXSYSCLKSEL": "sys_sel",
    "QPLL0CLK": "qpll0clk",
    "QPLL0REFCLK": "qpll0refclk",
    "QPLL1CLK": "qpll1clk",
    "QPLL1REFCLK": "qpll1refclk",
    "TXPD": "2'b00",
    "RXPD": "2'b00",
    # UG578: 001 selects GTREFCLK0. 101 is TX/RXPROGDIVCLK, the PIPE pclk.
    "CPLLREFCLKSEL": "3'b001",
    "CPLLLOCKEN": "1'b1",
    "CPLLLOCKDETCLK": "phy_refclk",
    "TXOUTCLKSEL": "3'b101",
    "RXOUTCLKSEL": "3'b101",
}

CH_OUT = {
    "GTYTXP": "pci_exp_txp[li]",
    "GTYTXN": "pci_exp_txn[li]",
    "RXDATA": "rx_raw[li]",
    "RXELECIDLE": "rxelecidle_l[li]",
    "RXSTATUS": "rxstatus_l[li]",
    "PHYSTATUS": "phystatus_l[li]",
    "TXOUTCLK": "txoutclk_l[li]",
    "TXRESETDONE": "txresetdone_l[li]",
    "RXRESETDONE": "rxresetdone_l[li]",
    "TXPRGDIVRESETDONE": "txdivdone_l[li]",
    "RXPRGDIVRESETDONE": "rxdivdone_l[li]",
    "CPLLLOCK": "cplllock_l[li]",
    "GTPOWERGOOD": "gt_gtpowergood[li]",
}

CM_IN = {
    "GTREFCLK00": "phy_gtrefclk",
    # QPLL1's 001 mux is GTREFCLK10, not GTREFCLK00. Same 100 MHz pin.
    "GTREFCLK10": "phy_gtrefclk",
    "QPLL0REFCLKSEL": "3'b001",
    "QPLL1REFCLKSEL": "3'b001",
    "QPLL0LOCKEN": "1'b1",
    "QPLL1LOCKEN": "1'b1",
    "QPLL0LOCKDETCLK": "phy_refclk",
    "QPLL1LOCKDETCLK": "phy_refclk",
    "QPLL0RESET": "pll_reset",
    "QPLL1RESET": "pll_reset",
    "QPLL0PD": "1'b0",
    "QPLL1PD": "1'b0",
}

CM_OUT = {
    "QPLL0LOCK": "qpll0lock",
    "QPLL1LOCK": "qpll1lock",
    "QPLL0OUTCLK": "qpll0clk",
    "QPLL0OUTREFCLK": "qpll0refclk",
    "QPLL1OUTCLK": "qpll1clk",
    "QPLL1OUTREFCLK": "qpll1refclk",
}


def emit_instance(kind, inst, ports, driven_in, driven_out, indent="    "):
    names = {name for _, _, name in ports}
    for name in list(driven_in) + list(driven_out):
        if name not in names:
            raise SystemExit(f"{kind} has no port {name}")
    lines = []
    if kind == "GTYE4_CHANNEL":
        # A LOC attribute cannot index an unpacked string array. Vivado
        # reports Synth 8-281 and then rejects the generate. Channel sites
        # are set from vcu118_pcie.xdc. The common LOC is a string literal.
        lines.append(f"{indent}GTYE4_CHANNEL #(")
        lines.append(f"{indent}  .TX_DATA_WIDTH      (PMA_BITS),")
        lines.append(f"{indent}  .RX_DATA_WIDTH      (PMA_BITS),")
        lines.append(f'{indent}  .RXSLIDE_MODE       ("PMA"),')
        lines.append(f'{indent}  .DEC_MCOMMA_DETECT  ("FALSE"),')
        lines.append(f'{indent}  .DEC_PCOMMA_DETECT  ("FALSE"),')
        lines.append(f"{indent}  .ALIGN_COMMA_ENABLE (10'b0000000000)")
        lines.append(f"{indent}) {inst} (")
    else:
        lines.append(f'{indent}(* LOC = "GTYE4_COMMON_X1Y8" *)')
        lines.append(f"{indent}GTYE4_COMMON {inst} (")
    body = []
    for direction, spec, name in ports:
        if direction == "input":
            conn = driven_in.get(name, "'0")
        elif direction == "output":
            if name in driven_out:
                conn = driven_out[name]
            else:
                conn = f"u_{name}"
        else:
            conn = f"u_{name}"
        body.append(f"{indent}  .{name}({conn})")
    lines.append(",\n".join(body))
    lines.append(f"{indent});")
    return "\n".join(lines), [
        (spec, name) for direction, spec, name in ports
        if direction != "input" and name not in driven_out
    ]


def main():
    channel = parse_ports(UNISIM / "GTYE4_CHANNEL.v", *CHANNEL_PORTS)
    common = parse_ports(UNISIM / "GTYE4_COMMON.v", *COMMON_PORTS)
    ch_text, ch_unused = emit_instance(
        "GTYE4_CHANNEL", "u_ch", channel, CH_IN, CH_OUT, indent="      ")
    cm_text, cm_unused = emit_instance(
        "GTYE4_COMMON", "u_common", common, CM_IN, CM_OUT, indent="    ")

    def decl(spec, name, prefix):
        return f"      wire {spec} {prefix}{name};"

    ch_wires = "\n".join(decl(spec, name, "u_") for spec, name in ch_unused)
    cm_wires = "\n".join(
        f"    wire {spec} u_{name};" for spec, name in cm_unused)

    text = f"""// Copyright 2026 Rivet contributors
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

  typedef enum logic [2:0] {{
    ST_PWR, ST_PLL, ST_DIV, ST_USR, ST_SYNC, ST_RUN
  }} rst_st_e;

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

{cm_wires}

{cm_text}

  for (genvar li = 0; li < LANES; li++) begin : g_lane
{ch_wires}

{ch_text}
  end

  wire _unused = |pma_txwidth;

endmodule : rivet_phy_gty_usplus
"""
    # The f-string doubled braces. CH_LOC initializer used '{{' which is correct
    # for a format string. Verify the enum braces survived.
    OUT.write_text(text.replace("\r\n", "\n"), encoding="utf-8", newline="\n")
    print(f"wrote {OUT} channel_ports={len(channel)} common_ports={len(common)}")


if __name__ == "__main__":
    main()
