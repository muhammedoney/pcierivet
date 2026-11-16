# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Create a local Quartus project for the Cyclone 10 GX Gen2 x4 Endpoint.
# Generated IP and the project directory are gitignored.
#
#   quartus_sh -t fpga/c10gx/create_project.tcl
#   fpga\c10gx\create_project.cmd
#
# Requires Quartus Prime Pro with Cyclone 10 GX and the Arria 10
# transceiver Native PHY (PIPE). The first generate prints a port list
# and stops if a PIPE port width is not the contract in rivet_c10gx_ep.sv.

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set build_dir  [file join $script_dir build]
set ip_dir     [file join $build_dir ip]

proc rivet_patch_cdc_2phase {src build regs_svh} {
  set dst_dir [file join $build src]
  set inc_dir [file join $dst_dir common_cells]
  file mkdir $inc_dir
  set dst [file join $dst_dir cc_cdc_2phase.sv]
  set fh [open $src r]
  set text [read $fh]
  close $fh
  if {![string match "*data_t'('0)*" $text]} {
    error "cc_cdc_2phase.sv no longer contains data_t'('0); update the Quartus patch"
  }
  if {![string match {*`include "common_cells/registers.svh"*} $text]} {
    error "cc_cdc_2phase.sv no longer includes common_cells/registers.svh; update the Quartus patch"
  }
  set text [string map [list {data_t'('0)} {'0}] $text]
  set out [open $dst w]
  puts -nonewline $out $text
  close $out
  file copy -force $regs_svh [file join $inc_dir registers.svh]
  return [file normalize $dst]
}

proc rivet_quartus_bindir {} {
  set exe [info nameofexecutable]
  if {$exe eq ""} {
    error "quartus_sh did not identify its executable"
  }
  return [file dirname $exe]
}

proc rivet_tool {bindir name} {
  # Quartus 25.x keeps quartus_sh in bin64 and qsys-script in sopc_builder\bin
  # (and a sibling qsys\bin). Earlier releases put both next to quartus_sh.
  set roots [list \
    $bindir \
    [file normalize [file join $bindir .. sopc_builder bin]] \
    [file normalize [file join $bindir .. .. qsys bin]]]
  foreach root $roots {
    foreach ext {".exe" ""} {
      set path [file join $root $name$ext]
      if {[file exists $path]} {
        return $path
      }
    }
  }
  error "missing $name under $bindir, sopc_builder\\bin, or qsys\\bin"
}

proc rivet_parse_ports {path} {
  set fh [open $path r]
  set text [read $fh]
  close $fh
  set ports [dict create]
  set in_mod 0
  set in_ports 0
  foreach line [split $text \n] {
    if {!$in_mod} {
      if {[regexp {^\s*module\s+rivet_c10gx_xcvr\b} $line]} {
        set in_mod 1
        if {[regexp {\)\s*;} $line]} {
          break
        }
        if {[string match "*)*" $line] && [string match "*(*" $line] && ![string match "*#*" $line]} {
          set in_ports 1
        }
      }
      continue
    }
    if {!$in_ports} {
      if {[regexp {\)\s*\(} $line] || [regexp {^\s*\(} $line]} {
        set in_ports 1
      }
      continue
    }
    if {[regexp {^\s*\)\s*;} $line]} {
      break
    }
    if {![regexp {^\s*(input|output|inout)\s+((wire|logic|reg)\s+)?(\[([0-9]+)\s*:\s*([0-9]+)\])?\s*([A-Za-z_][A-Za-z0-9_]*)} $line -> dir _kind _word _range msb lsb name]} {
      continue
    }
    if {$msb eq ""} {
      set width 1
    } else {
      set width [expr {$msb - $lsb + 1}]
    }
    dict set ports $name [dict create dir $dir width $width]
  }
  if {[dict size $ports] == 0} {
    error "no ports parsed from $path"
  }
  return $ports
}

proc rivet_dump_ports {ports path} {
  set fh [open $path w]
  dict for {name spec} $ports {
    puts $fh "$name [dict get $spec dir] [dict get $spec width]"
  }
  close $fh
}

proc rivet_pick {ports dir glob required {excludes {}}} {
  set hits {}
  dict for {name spec} $ports {
    if {[dict get $spec dir] ne $dir} {
      continue
    }
    if {![string match $glob $name]} {
      continue
    }
    set skip 0
    foreach ex $excludes {
      if {[string match $ex $name]} {
        set skip 1
      }
    }
    if {$skip} {
      continue
    }
    lappend hits $name
  }
  if {[llength $hits] == 0} {
    if {$required} {
      error "no $dir port matching $glob excluding {$excludes}"
    }
    return ""
  }
  if {[llength $hits] != 1} {
    error "several $dir ports match $glob: $hits"
  }
  return [lindex $hits 0]
}

proc rivet_width {ports name} {
  return [dict get [dict get $ports $name] width]
}

proc rivet_require_width {ports name expect} {
  set got [rivet_width $ports $name]
  if {$got != $expect} {
    error "$name width is $got, the shell contract wants $expect. See the port report."
  }
}

proc rivet_emit_link {ports outpath} {
  set conn [dict create]
  set decls {}

  set pll_ref [rivet_pick $ports input *pll*refclk* 1]
  set phy_ref [rivet_pick $ports input *phy*refclk* 1]
  dict set conn $pll_ref refclk
  dict set conn $phy_ref refclk

  set pll_sclk [rivet_pick $ports output *serial_clk* 1]
  set phy_sclk [rivet_pick $ports input *serial_clk* 1]
  rivet_require_width $ports $pll_sclk [rivet_width $ports $phy_sclk]
  set sw [rivet_width $ports $pll_sclk]
  lappend decls "  wire \[[expr {$sw - 1}]:0\] w_serial_clk;"
  dict set conn $pll_sclk w_serial_clk
  dict set conn $phy_sclk w_serial_clk

  set tx_ser [rivet_pick $ports output *tx_serial_data* 1 {*clk*}]
  set rx_ser [rivet_pick $ports input *rx_serial_data* 1 {*clk*}]
  rivet_require_width $ports $tx_ser 4
  rivet_require_width $ports $rx_ser 4
  dict set conn $tx_ser tx_serial_data
  dict set conn $rx_ser rx_serial_data

  set tx_par [rivet_pick $ports input *tx_parallel_data* 1 {*unused*}]
  set rx_par [rivet_pick $ports output *rx_parallel_data* 1 {*unused*}]
  rivet_require_width $ports $tx_par 512
  rivet_require_width $ports $rx_par 512
  dict set conn $tx_par tx_parallel_data
  dict set conn $rx_par rx_parallel_data

  set tx_clkout [rivet_pick $ports output *tx_clkout* 1]
  set cw [rivet_width $ports $tx_clkout]
  lappend decls "  wire \[[expr {$cw - 1}]:0\] w_tx_clkout;"
  dict set conn $tx_clkout w_tx_clkout
  lappend decls "  assign pipe_clk = w_tx_clkout\[0\];"

  foreach core {tx_coreclkin rx_coreclkin} {
    set port [rivet_pick $ports input *$core* 1]
    set nw [rivet_width $ports $port]
    if {$nw <= 1} {
      dict set conn $port pipe_clk
    } else {
      dict set conn $port "\{${nw}\{pipe_clk\}\}"
    }
  }

  set prate [rivet_pick $ports input *pipe_rate* 1]
  rivet_require_width $ports $prate 2
  dict set conn $prate pipe_rate
  set pol [rivet_pick $ports input *polarity* 1]
  rivet_require_width $ports $pol 4
  dict set conn $pol rx_polarity
  set eidle [rivet_pick $ports output *rx*elecidle* 1]
  rivet_require_width $ports $eidle 4
  dict set conn $eidle rx_elecidle

  set hclk_in [rivet_pick $ports input *hclk* 1]
  set hclk_src [rivet_pick $ports output *pcie*clk* 1]
  rivet_require_width $ports $hclk_in [rivet_width $ports $hclk_src]
  set hw [rivet_width $ports $hclk_in]
  lappend decls "  wire \[[expr {$hw - 1}]:0\] w_hclk;"
  dict set conn $hclk_src w_hclk
  dict set conn $hclk_in w_hclk

  set rst_clk [rivet_pick $ports input *rst*clk* 1]
  rivet_require_width $ports $rst_clk 1
  dict set conn $rst_clk clk50
  set rst_pin [rivet_pick $ports input *rst*reset* 1 {*analog* *digital* *cal* *powerdown*}]
  if {[rivet_width $ports $rst_pin] != 1} {
    error "$rst_pin is not a 1-bit reset"
  }
  if {[string match *analog* $rst_pin] || [string match *digital* $rst_pin]} {
    error "reset pick hit $rst_pin; name the controller reset more specifically"
  }
  if {[string match -nocase *reset_n* $rst_pin] || [string match -nocase *resetn* $rst_pin]} {
    dict set conn $rst_pin reset_n
  } else {
    dict set conn $rst_pin "~reset_n"
  }

  set pll_lock [rivet_pick $ports output *pll_locked* 1]
  set rst_lock [rivet_pick $ports input *pll_locked* 1]
  rivet_require_width $ports $pll_lock [rivet_width $ports $rst_lock]
  set lw [rivet_width $ports $pll_lock]
  lappend decls "  wire \[[expr {$lw - 1}]:0\] w_pll_locked;"
  dict set conn $pll_lock w_pll_locked
  dict set conn $rst_lock w_pll_locked

  foreach kind {tx_analogreset tx_digitalreset rx_analogreset rx_digitalreset} {
    set src [rivet_pick $ports output *$kind* 1]
    set dst [rivet_pick $ports input *$kind* 1]
    rivet_require_width $ports $src [rivet_width $ports $dst]
    set kw [rivet_width $ports $src]
    lappend decls "  wire \[[expr {$kw - 1}]:0\] w_$kind;"
    dict set conn $src "w_$kind"
    dict set conn $dst "w_$kind"
  }

  set tx_ready [rivet_pick $ports output *tx_ready* 1]
  set rx_ready [rivet_pick $ports output *rx_ready* 1]
  set trw [rivet_width $ports $tx_ready]
  set rrw [rivet_width $ports $rx_ready]
  lappend decls "  wire \[[expr {$trw - 1}]:0\] w_tx_ready;"
  lappend decls "  wire \[[expr {$rrw - 1}]:0\] w_rx_ready;"
  dict set conn $tx_ready w_tx_ready
  dict set conn $rx_ready w_rx_ready
  lappend decls "  assign phy_ready = (&w_tx_ready) & (&w_rx_ready);"

  foreach kind {tx_cal_busy rx_cal_busy pll_cal_busy} {
    set src [rivet_pick $ports output *$kind* 0]
    set dst [rivet_pick $ports input *$kind* 0]
    if {$src eq "" && $dst eq ""} {
      continue
    }
    if {$src eq "" || $dst eq ""} {
      puts "WARN: $kind is only on one side (out=$src in=$dst); the input is tied off below if still open"
      continue
    }
    if {[rivet_width $ports $src] != [rivet_width $ports $dst]} {
      error "$kind width mismatch"
    }
    set bw [rivet_width $ports $src]
    lappend decls "  wire \[[expr {$bw - 1}]:0\] w_$kind;"
    dict set conn $src "w_$kind"
    dict set conn $dst "w_$kind"
  }

  set sw [rivet_pick $ports output *pipe_sw* 0 {*done*}]
  set sw_in [rivet_pick $ports input *pipe_sw* 0 {*done*}]
  set sw_done_o [rivet_pick $ports output *sw_done* 0]
  set sw_done_i [rivet_pick $ports input *sw_done* 0]
  if {$sw ne "" && $sw_in ne ""} {
    rivet_require_width $ports $sw [rivet_width $ports $sw_in]
    set sww [rivet_width $ports $sw]
    lappend decls "  wire \[[expr {$sww - 1}]:0\] w_pipe_sw;"
    dict set conn $sw w_pipe_sw
    dict set conn $sw_in w_pipe_sw
    if {$sw_done_o ne "" && $sw_done_i ne ""} {
      rivet_require_width $ports $sw_done_o [rivet_width $ports $sw_done_i]
      set dw [rivet_width $ports $sw_done_o]
      lappend decls "  wire \[[expr {$dw - 1}]:0\] w_sw_done;"
      dict set conn $sw_done_o w_sw_done
      dict set conn $sw_done_i w_sw_done
    }
  } elseif {$sw ne "" && $sw_done_i ne ""} {
    puts "WARN: pipe_sw has no PLL input. Tying pipe_sw_done to pipe_sw. Confirm the rate-switch handshake on the first compile."
    rivet_require_width $ports $sw [rivet_width $ports $sw_done_i]
    set sww [rivet_width $ports $sw]
    lappend decls "  wire \[[expr {$sww - 1}]:0\] w_pipe_sw;"
    dict set conn $sw w_pipe_sw
    dict set conn $sw_done_i w_pipe_sw
  }

  set pd_o [rivet_pick $ports output *pll_powerdown* 0]
  set pd_i [rivet_pick $ports input *powerdown* 0]
  if {$pd_o ne "" && $pd_i ne ""} {
    rivet_require_width $ports $pd_o [rivet_width $ports $pd_i]
    set pw [rivet_width $ports $pd_o]
    lappend decls "  wire \[[expr {$pw - 1}]:0\] w_pll_powerdown;"
    dict set conn $pd_o w_pll_powerdown
    dict set conn $pd_i w_pll_powerdown
  }

  dict for {name spec} $ports {
    if {[dict exists $conn $name]} {
      continue
    }
    if {[dict get $spec dir] ne "input"} {
      continue
    }
    set w [dict get $spec width]
    if {$w <= 1} {
      dict set conn $name "1'b0"
    } else {
      dict set conn $name "${w}'b0"
    }
  }

  set fh [open $outpath w]
  puts $fh "// Generated by fpga/c10gx/create_project.tcl. Do not edit."
  puts $fh "module rivet_c10gx_link ("
  puts $fh "  input  wire         refclk,"
  puts $fh "  input  wire         clk50,"
  puts $fh "  input  wire         reset_n,"
  puts $fh "  output wire \[3:0\]   tx_serial_data,"
  puts $fh "  input  wire \[3:0\]   rx_serial_data,"
  puts $fh "  output wire         pipe_clk,"
  puts $fh "  output wire         phy_ready,"
  puts $fh "  input  wire \[511:0\] tx_parallel_data,"
  puts $fh "  output wire \[511:0\] rx_parallel_data,"
  puts $fh "  input  wire \[3:0\]   rx_polarity,"
  puts $fh "  input  wire \[1:0\]   pipe_rate,"
  puts $fh "  output wire \[3:0\]   rx_elecidle"
  puts $fh ");"
  foreach decl $decls {
    puts $fh $decl
  }
  puts $fh "  rivet_c10gx_xcvr u ("
  set items {}
  dict for {name expr} $conn {
    lappend items "    .$name ($expr)"
  }
  puts $fh [join $items ",\n"]
  puts $fh "  );"
  puts $fh "endmodule"
  close $fh
}

proc rivet_find_named {dir tail} {
  set hits {}
  foreach f [glob -nocomplain -directory $dir *] {
    if {[file isdirectory $f]} {
      set hits [concat $hits [rivet_find_named $f $tail]]
    } elseif {[file tail $f] eq $tail} {
      lappend hits $f
    }
  }
  return $hits
}

proc rivet_emit_fixed_link {path} {
  set fh [open $path w]
  puts $fh {// Generated by fpga/c10gx/create_project.tcl.
// Stitches the three Quartus IP variations. The system qsys-generate
// hangs in quartus_sh --ipc_sh, so this wrapper is written here.
// Port list is the contract instantiated by rivet_c10gx_ep.
module rivet_c10gx_link (
  input  wire         refclk,
  input  wire         clk50,
  input  wire         reset_n,
  output wire [3:0]   tx_serial_data,
  input  wire [3:0]   rx_serial_data,
  output wire         pipe_clk,
  output wire         phy_ready,
  input  wire [511:0] tx_parallel_data,
  output wire [511:0] rx_parallel_data,
  input  wire [3:0]   rx_polarity,
  input  wire [1:0]   pipe_rate,
  output wire [3:0]   rx_elecidle
);

  wire        pll_powerdown;
  wire        pll_locked;
  wire        pll_pcie_clk;
  wire [5:0]  tx_bonding_clocks;
  wire [1:0]  pipe_sw;
  wire [1:0]  pipe_sw_done;
  wire [3:0]  tx_analogreset;
  wire [3:0]  tx_digitalreset;
  wire [3:0]  rx_analogreset;
  wire [3:0]  rx_digitalreset;
  wire [3:0]  tx_cal_busy;
  wire [3:0]  rx_cal_busy;
  wire [3:0]  tx_ready;
  wire [3:0]  rx_ready;
  wire [3:0]  rx_is_lockedtodata;

  assign phy_ready = (&tx_ready) & (&rx_ready);

  rivet_c10gx_xcvr_pll u_pll (
    .pll_powerdown     (pll_powerdown),
    .pll_refclk0       (refclk),
    .tx_serial_clk     (),
    .pll_locked        (pll_locked),
    .pll_pcie_clk      (pll_pcie_clk),
    .pll_cal_busy      (),
    .mcgb_rst          (pll_powerdown),
    .tx_bonding_clocks (tx_bonding_clocks),
    .pcie_sw           (pipe_sw),
    .pcie_sw_done      (pipe_sw_done)
  );

  rivet_c10gx_xcvr_rst u_rst (
    .clock              (clk50),
    .reset              (~reset_n),
    .pll_powerdown      (pll_powerdown),
    .tx_analogreset     (tx_analogreset),
    .tx_digitalreset    (tx_digitalreset),
    .tx_ready           (tx_ready),
    .pll_locked         (pll_locked),
    .pll_select         (1'b0),
    .tx_cal_busy        (tx_cal_busy),
    .rx_analogreset     (rx_analogreset),
    .rx_digitalreset    (rx_digitalreset),
    .rx_ready           (rx_ready),
    .rx_is_lockedtodata (rx_is_lockedtodata),
    .rx_cal_busy        (rx_cal_busy)
  );

  rivet_c10gx_xcvr_phy u_phy (
    .pipe_rate                 (pipe_rate),
    .pipe_sw_done              (pipe_sw_done),
    .pipe_sw                   (pipe_sw),
    .tx_analogreset_ch0        (tx_analogreset[0]),
    .tx_analogreset_ch1        (tx_analogreset[1]),
    .tx_analogreset_ch2        (tx_analogreset[2]),
    .tx_analogreset_ch3        (tx_analogreset[3]),
    .tx_digitalreset_ch0       (tx_digitalreset[0]),
    .tx_digitalreset_ch1       (tx_digitalreset[1]),
    .tx_digitalreset_ch2       (tx_digitalreset[2]),
    .tx_digitalreset_ch3       (tx_digitalreset[3]),
    .rx_analogreset_ch0        (rx_analogreset[0]),
    .rx_analogreset_ch1        (rx_analogreset[1]),
    .rx_analogreset_ch2        (rx_analogreset[2]),
    .rx_analogreset_ch3        (rx_analogreset[3]),
    .rx_digitalreset_ch0       (rx_digitalreset[0]),
    .rx_digitalreset_ch1       (rx_digitalreset[1]),
    .rx_digitalreset_ch2       (rx_digitalreset[2]),
    .rx_digitalreset_ch3       (rx_digitalreset[3]),
    .tx_cal_busy_ch0           (tx_cal_busy[0]),
    .tx_cal_busy_ch1           (tx_cal_busy[1]),
    .tx_cal_busy_ch2           (tx_cal_busy[2]),
    .tx_cal_busy_ch3           (tx_cal_busy[3]),
    .rx_cal_busy_ch0           (rx_cal_busy[0]),
    .rx_cal_busy_ch1           (rx_cal_busy[1]),
    .rx_cal_busy_ch2           (rx_cal_busy[2]),
    .rx_cal_busy_ch3           (rx_cal_busy[3]),
    .tx_bonding_clocks_ch0     (tx_bonding_clocks),
    .tx_bonding_clocks_ch1     (tx_bonding_clocks),
    .tx_bonding_clocks_ch2     (tx_bonding_clocks),
    .tx_bonding_clocks_ch3     (tx_bonding_clocks),
    .rx_cdr_refclk0            (refclk),
    .tx_serial_data_ch0        (tx_serial_data[0]),
    .tx_serial_data_ch1        (tx_serial_data[1]),
    .tx_serial_data_ch2        (tx_serial_data[2]),
    .tx_serial_data_ch3        (tx_serial_data[3]),
    .rx_serial_data_ch0        (rx_serial_data[0]),
    .rx_serial_data_ch1        (rx_serial_data[1]),
    .rx_serial_data_ch2        (rx_serial_data[2]),
    .rx_serial_data_ch3        (rx_serial_data[3]),
    .rx_is_lockedtoref_ch0     (),
    .rx_is_lockedtoref_ch1     (),
    .rx_is_lockedtoref_ch2     (),
    .rx_is_lockedtoref_ch3     (),
    .rx_is_lockedtodata_ch0    (rx_is_lockedtodata[0]),
    .rx_is_lockedtodata_ch1    (rx_is_lockedtodata[1]),
    .rx_is_lockedtodata_ch2    (rx_is_lockedtodata[2]),
    .rx_is_lockedtodata_ch3    (rx_is_lockedtodata[3]),
    .tx_coreclkin_ch0          (pipe_clk),
    .tx_coreclkin_ch1          (pipe_clk),
    .tx_coreclkin_ch2          (pipe_clk),
    .tx_coreclkin_ch3          (pipe_clk),
    .rx_coreclkin_ch0          (pipe_clk),
    .rx_coreclkin_ch1          (pipe_clk),
    .rx_coreclkin_ch2          (pipe_clk),
    .rx_coreclkin_ch3          (pipe_clk),
    .tx_clkout_ch0             (pipe_clk),
    .tx_clkout_ch1             (),
    .tx_clkout_ch2             (),
    .tx_clkout_ch3             (),
    .rx_clkout_ch0             (),
    .rx_clkout_ch1             (),
    .rx_clkout_ch2             (),
    .rx_clkout_ch3             (),
    .tx_parallel_data_ch0      (tx_parallel_data[127:0]),
    .tx_parallel_data_ch1      (tx_parallel_data[255:128]),
    .tx_parallel_data_ch2      (tx_parallel_data[383:256]),
    .tx_parallel_data_ch3      (tx_parallel_data[511:384]),
    .rx_parallel_data_ch0      (rx_parallel_data[127:0]),
    .rx_parallel_data_ch1      (rx_parallel_data[255:128]),
    .rx_parallel_data_ch2      (rx_parallel_data[383:256]),
    .rx_parallel_data_ch3      (rx_parallel_data[511:384]),
    .pipe_hclk_in              (pll_pcie_clk),
    .pipe_hclk_out             (),
    .pipe_rx_eidleinfersel_ch0 (1'b0),
    .pipe_rx_eidleinfersel_ch1 (1'b0),
    .pipe_rx_eidleinfersel_ch2 (1'b0),
    .pipe_rx_eidleinfersel_ch3 (1'b0),
    .pipe_rx_elecidle_ch0      (rx_elecidle[0]),
    .pipe_rx_elecidle_ch1      (rx_elecidle[1]),
    .pipe_rx_elecidle_ch2      (rx_elecidle[2]),
    .pipe_rx_elecidle_ch3      (rx_elecidle[3]),
    .pipe_rx_polarity_ch0      (rx_polarity[0]),
    .pipe_rx_polarity_ch1      (rx_polarity[1]),
    .pipe_rx_polarity_ch2      (rx_polarity[2]),
    .pipe_rx_polarity_ch3      (rx_polarity[3])
  );
endmodule
}
  close $fh
}

file mkdir $build_dir
file mkdir $ip_dir

set bindir [rivet_quartus_bindir]
set qsys [rivet_tool $bindir qsys-script]
set qgen [rivet_tool $bindir qsys-generate]
set gen_tcl [file join $script_dir ip gen_xcvr.tcl]

puts "rivet: $qsys"
puts "rivet: generating Native PHY PIPE system"
# Without --quartus-project, qsys-script writes gen_xcvr.qpf beside the Tcl.
set qsys_proj [file join $build_dir qsys_shell gen_xcvr.qpf]
file mkdir [file dirname $qsys_proj]
if {[file exists $qsys_proj]} {
  set qsys_flag --quartus-project=$qsys_proj
} else {
  set qsys_flag --new-quartus-project=$qsys_proj
}
# [info script] is "." inside qsys-script, so the output directory has
# to be handed in. file normalize is quartus_sh Tcl; qsys-script lacks it.
set build_abs [string map {\\ /} [file normalize $ip_dir]]
set qsys_cmd "--cmd=set ::rivet_c10gx_build $build_abs"
if {[catch {exec $qsys $qsys_flag $qsys_cmd --script=$gen_tcl 2>@1} err]} {
  error "qsys-script failed:\n$err"
}
puts $err

set qsys_file [file join $ip_dir rivet_c10gx_xcvr.qsys]
if {![file exists $qsys_file]} {
  error "missing $qsys_file"
}
puts "rivet: $qgen"
# Generating the .qsys system hangs in quartus_sh --ipc_sh on this host.
# Each .ip generates on its own in a few seconds. The link below stitches
# those three modules. Parallel generation is off: it dies with
# "Application error processing RPC".
set ip_files [list \
  [file join $ip_dir ip rivet_c10gx_xcvr rivet_c10gx_xcvr_pll.ip] \
  [file join $ip_dir ip rivet_c10gx_xcvr rivet_c10gx_xcvr_phy.ip] \
  [file join $ip_dir ip rivet_c10gx_xcvr rivet_c10gx_xcvr_rst.ip]]
foreach ip $ip_files {
  if {![file exists $ip]} {
    error "missing $ip"
  }
  puts "rivet: generating $ip"
  if {[catch {exec $qgen $ip --synthesis=VERILOG --part=10CX220YF780E5G --parallel=off 2>@1} err]} {
    error "qsys-generate failed for $ip:\n$err"
  }
  puts $err
}
rivet_emit_fixed_link [file join $build_dir rivet_c10gx_link.v]
puts "rivet: wrote [file join $build_dir rivet_c10gx_link.v]"

package require ::quartus::project
cd $build_dir
catch {project_close}
# A killed qsys-generate can leave qdb/dni locked ("file in use"). Drop the
# stale database and retry project_new before giving up.
set proj_err ""
set proj_ok 0
for {set attempt 1} {$attempt <= 3} {incr attempt} {
  foreach stale {qdb dni} {
    catch {file delete -force [file join $build_dir $stale]}
  }
  if {$attempt > 1} {
    puts "rivet: project_new retry $attempt after: $proj_err"
    after 2000 {set ::rivet_delay_done 1}
    vwait ::rivet_delay_done
    unset ::rivet_delay_done
  }
  if {![catch {project_new -family "Cyclone 10 GX" -part 10CX220YF780E5G -overwrite rivet_c10gx} proj_err]} {
    set proj_ok 1
    break
  }
}
if {!$proj_ok} {
  error "project_new failed:\n$proj_err"
}

set_global_assignment -name FAMILY "Cyclone 10 GX"
set_global_assignment -name DEVICE 10CX220YF780E5G
set_global_assignment -name TOP_LEVEL_ENTITY rivet_c10gx_ep
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2005
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 100
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
set_global_assignment -name SEARCH_PATH [file normalize [file join $build_dir src]]
set_global_assignment -name SEARCH_PATH [file normalize [file join $script_dir include]]
set_global_assignment -name SEARCH_PATH [file normalize [file join $repo_root rtl pcie_ctrl]]

proc rivet_add_filelist {repo listfile build regs_svh} {
  set fh [open $listfile r]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
      continue
    }
    if {[string match "-f *" $line]} {
      set sub [string trim [string range $line 3 end]]
      rivet_add_filelist $repo [file join $repo $sub] $build $regs_svh
      continue
    }
    set path [file normalize [file join $repo $line]]
    if {![file exists $path]} {
      close $fh
      error "missing source: $path"
    }
    if {[string match *cc_cdc_2phase.sv $path]} {
      set path [rivet_patch_cdc_2phase $path $build $regs_svh]
    }
    if {[string match *.sv $path]} {
      set_global_assignment -name SYSTEMVERILOG_FILE $path
    } else {
      set_global_assignment -name VERILOG_FILE $path
    }
  }
  close $fh
}

set regs_svh [file normalize [file join $script_dir include common_cells registers.svh]]
rivet_add_filelist $repo_root [file join $repo_root rtl filelist_core.f] $build_dir $regs_svh

set_global_assignment -name SYSTEMVERILOG_FILE [file normalize [file join $script_dir rtl rivet_c10gx_ep.sv]]
set_global_assignment -name VERILOG_FILE [file normalize [file join $build_dir rivet_c10gx_link.v]]

foreach tail {rivet_c10gx_xcvr_pll.qip rivet_c10gx_xcvr_phy.qip rivet_c10gx_xcvr_rst.qip} {
  set qips [rivet_find_named $ip_dir $tail]
  if {[llength $qips] != 1} {
    error "expected one $tail under $ip_dir, found [llength $qips]"
  }
  set_global_assignment -name QIP_FILE [lindex $qips 0]
  puts "rivet: QIP [lindex $qips 0]"
}

set_global_assignment -name SDC_FILE [file normalize [file join $script_dir constraints c10gx_pcie.sdc]]
source [file join $script_dir constraints c10gx_pins.tcl]

project_close
puts "PASS: Quartus project [file join $build_dir rivet_c10gx.qpf]"
puts "Next: fpga\\c10gx\\synth.cmd"
