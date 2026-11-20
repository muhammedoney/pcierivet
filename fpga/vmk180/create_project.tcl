# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
#
# Create a local Vivado project for the VMK180 Gen2 x4 Endpoint.
# Generated IP and the project directory are gitignored.
#
#   vivado -mode batch -source fpga/vmk180/create_project.tcl
#   vivado -mode batch -source fpga/vmk180/create_project.tcl -tclargs synth
#   fpga\vmk180\create_project.cmd
#   fpga\vmk180\create_project.cmd synth
#
# Requires a Vivado install that can generate PG345 (pcie_phy_versal) for
# XCVM1802 GTY. The GT quad is outside the PHY; block automation connects it.
# Board files for xilinx.com:vmk180 are optional; the part is set either way.

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set build_dir  [file join $script_dir build]
set part       xcvm1802-vsva2197-2MP-e-S
set boards {
  xilinx.com:vmk180:part0:3.4
  xilinx.com:vmk180:part0:3.3
  xilinx.com:vmk180:part0:3.2
  xilinx.com:vmk180:part0:3.1
  xilinx.com:vmk180:part0:1.2
}

# PCIe edge lanes 0-3. Quad 103 == GTY_QUAD_X0Y3 on XCVM1802.
# Wrapper port widths below match rivet_vmk180_ep (x4, 64-bit PHY pins).

proc rivet_patch_cdc_2phase {src build regs_svh} {
  set dst_dir [file join $build src]
  set inc_dir [file join $dst_dir common_cells]
  file mkdir $inc_dir
  set dst [file join $dst_dir cc_cdc_2phase.sv]
  set fh [open $src r]
  set text [read $fh]
  close $fh
  if {![string match "*data_t'('0)*" $text]} {
    error "cc_cdc_2phase.sv no longer contains data_t'('0); update the Vivado patch"
  }
  if {![string match {*`include "common_cells/registers.svh"*} $text]} {
    error "cc_cdc_2phase.sv no longer includes common_cells/registers.svh; update the Vivado patch"
  }
  set text [string map [list {data_t'('0)} {'0}] $text]
  set out [open $dst w]
  puts -nonewline $out $text
  close $out
  file copy -force $regs_svh [file join $inc_dir registers.svh]
  return [file normalize $dst]
}

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
    add_files -norecurse $path
  }
  close $fh
}

proc rivet_set_first {cell names values} {
  # set_property on a missing CONFIG.* prints a critical warning and still
  # returns success, so a guessed name must not hide the real parameter.
  set props [list_property $cell]
  foreach n $names {
    set key CONFIG.$n
    if {[lsearch -exact $props $key] < 0} {
      continue
    }
    foreach v $values {
      if {[catch {set_property $key $v $cell} err]} {
        puts "WARN: $key=$v rejected: $err"
        continue
      }
      set got [get_property -quiet $key $cell]
      if {$got eq $v} {
        puts "$key=$got"
        return 1
      }
      puts "WARN: $key write $v read back {$got}"
    }
    if {![catch {set legal [list_property_value $key $cell]} err]} {
      if {$legal ne ""} {
        puts "      $key legal: $legal"
      }
    }
  }
  puts "WARN: none of {$names} accepted {$values}"
  return 0
}

proc rivet_width {pin} {
  set l [get_property -quiet LEFT $pin]
  set r [get_property -quiet RIGHT $pin]
  if {$l ne "" && $r ne ""} {
    return [expr {abs($l - $r) + 1}]
  }
  set w [get_property -quiet WIDTH $pin]
  if {$w ne "" && [string is integer -strict $w] && $w > 0} {
    return $w
  }
  return 1
}

proc rivet_pin_dump {cell} {
  puts "Pins on $cell:"
  foreach p [lsort [get_bd_pins -quiet $cell/*]] {
    set tail [lindex [split $p /] end]
    puts "  [get_property DIR $p] [rivet_width $p] $tail"
  }
}

# Export a PHY pin (or the first matching alias) as a BD port with a fixed
# name and width. The name and width are the contract with rivet_vmk180_ep.
proc rivet_export {cell port dir aliases expect_w} {
  set pins {}
  foreach a $aliases {
    set p [get_bd_pins -quiet $cell/$a]
    if {$p ne ""} {
      lappend pins $p
    }
  }
  if {[llength $pins] == 0} {
    rivet_pin_dump $cell
    error "PG345 pin not found for $port (tried: $aliases)"
  }
  set w [rivet_width [lindex $pins 0]]
  if {$w != $expect_w} {
    rivet_pin_dump $cell
    error "PG345 $port width is $w, rivet_pcie_phy_wrap expects $expect_w"
  }
  foreach p [lrange $pins 1 end] {
    if {[rivet_width $p] != $w} {
      error "PG345 alias width mismatch on $port"
    }
  }
  set eport [get_bd_ports -quiet $port]
  if {$eport eq ""} {
    set net [get_bd_nets -quiet -of_objects [lindex $pins 0]]
    if {$net ne ""} {
      set eport [lindex [get_bd_ports -quiet -of_objects $net] 0]
    }
    if {$eport ne ""} {
      set_property NAME $port $eport
    } else {
      if {$w <= 1} {
        set eport [create_bd_port -dir $dir $port]
      } else {
        set eport [create_bd_port -dir $dir -from [expr {$w - 1}] -to 0 $port]
      }
      connect_bd_net $eport {*}[lrange $pins 0 0]
    }
  }
  foreach p $pins {
    set net [get_bd_nets -quiet -of_objects $p]
    if {$net eq ""} {
      connect_bd_net [get_bd_ports $port] $p
    }
  }
  return $eport
}

proc rivet_tie_open_inputs {cell} {
  set const_vlnv [get_ipdefs -filter {NAME == xlconstant}]
  if {$const_vlnv eq ""} {
    error "xlconstant is not in this Vivado catalog"
  }
  set i 0
  foreach pin [get_bd_pins -quiet -of_objects $cell -filter {DIR == I}] {
    if {[get_bd_nets -quiet -of_objects $pin] ne ""} {
      continue
    }
    set w [rivet_width $pin]
    set c [create_bd_cell -type ip -vlnv [lindex $const_vlnv 0] rivet_tie_$i]
    set_property -dict [list CONFIG.CONST_WIDTH $w CONFIG.CONST_VAL {0}] $c
    connect_bd_net [get_bd_pins $c/dout] $pin
    incr i
  }
  puts "Tied $i open PG345 inputs to 0"
}

proc rivet_delete_port {name} {
  set p [get_bd_intf_ports -quiet $name]
  if {$p ne ""} {
    delete_bd_objs $p
  }
  set p [get_bd_ports -quiet $name]
  if {$p ne ""} {
    delete_bd_objs $p
  }
}

proc rivet_automate {cell} {
  # hier false keeps gtwiz_versal_0 at the BD root. link_speed 2 is Gen2.
  # phy_refclk and phy_gtrefclk must still be open: the rule drives them
  # from the IBUF it inserts, and a pre-connected sink aborts the rule.
  set cmd {apply_bd_automation -rule xilinx.com:bd_rule:pcie_phy_versal -config {link_speed 2 link_width 4 hier false}}
  if {[catch {eval $cmd $cell} err]} {
    puts "WARN: automation with explicit config failed: $err"
    if {[catch {apply_bd_automation -rule xilinx.com:bd_rule:pcie_phy_versal $cell} err2]} {
      puts "WARN: $err2"
      return 0
    }
  }
  puts "Block automation: xilinx.com:bd_rule:pcie_phy_versal"
  return 1
}

# The shell already has IBUFDS_GTE5 and BUFG_GT. Drop the copies the
# automation inserted and export the two clock pins it was driving.
proc rivet_shell_owns_refclk {phy} {
  rivet_delete_port pcie_refclk
  rivet_delete_port CLK_IN_D
  rivet_delete_port BUFG_GT_CE
  rivet_delete_port gtwiz_freerun_clk

  foreach c {refclk_ibuf bufg_gt_sysclk} {
    set cell [get_bd_cells -quiet $c]
    if {$cell ne ""} {
      delete_bd_objs $cell
      puts "Removed automation cell $c"
    }
  }

  rivet_export $phy phy_refclk   I {phy_refclk} 1
  rivet_export $phy phy_gtrefclk I {phy_gtrefclk} 1

  set free [get_bd_pins -quiet gtwiz_versal_0/gtwiz_freerun_clk]
  if {$free ne "" && [get_bd_nets -quiet -of_objects $free] eq ""} {
    connect_bd_net [get_bd_ports phy_refclk] $free
    puts "gtwiz_freerun_clk tied to phy_refclk"
  }
}

file mkdir $build_dir
create_project rivet_vmk180 $build_dir -part $part -force
set_property target_language Verilog [current_project]
set board_ok 0
foreach board $boards {
  if {![catch {set_property board_part $board [current_project]} err]} {
    puts "Board part: $board"
    set board_ok 1
    break
  }
  puts "WARN: board part $board not installed ($err)"
}
if {!$board_ok} {
  puts "WARN: no VMK180 board part installed. Continuing with $part."
}

set regs_svh [file normalize [file join $script_dir include common_cells registers.svh]]
rivet_add_filelist $repo_root [file join $repo_root rtl filelist_core.f] $build_dir $regs_svh
add_files -norecurse [file normalize [file join $script_dir rtl rivet_vmk180_ep.sv]]
add_files -norecurse [file normalize [file join $repo_root rtl phy rivet_pipe_pg239_pad.sv]]
add_files -norecurse [file normalize [file join $repo_root rtl phy rivet_pcie_phy_wrap.sv]]

foreach f [get_files -of_objects [current_fileset]] {
  set name [get_property NAME $f]
  if {[string match *.sv $name]} {
    set_property file_type SystemVerilog $f
  }
}
set_property include_dirs [list \
  [file normalize [file join $build_dir src]] \
  [file normalize [file join $script_dir include]] \
  [file normalize [file join $repo_root rtl pcie_ctrl]] \
] [current_fileset]

set xdc [file join $script_dir constraints vmk180_pcie.xdc]
add_files -fileset constrs_1 -norecurse $xdc

set vlnv [get_ipdefs -filter {NAME == pcie_phy_versal}]
if {$vlnv eq ""} {
  error "pcie_phy_versal is not in this Vivado catalog. PG345 needs a Versal device install."
}
puts "PG345 VLNV: [lindex $vlnv 0]"

create_bd_design pcie_phy_bd
set phy [create_bd_cell -type ip -vlnv [lindex $vlnv 0] pcie_phy_0]

# Names are the PG345 user parameters (component.xml), not the US+ aliases.
# XCVM1802 is GTY. Width X4 and Gen2 must stick before the PIPE ports are exported.
rivet_set_first $phy {gt_type} {GTY}
set need_width [rivet_set_first $phy {PL_LINK_CAP_MAX_LINK_WIDTH} {X4}]
set need_speed [rivet_set_first $phy {PL_LINK_CAP_MAX_LINK_SPEED} {5.0_GT/s}]
set need_ref   [rivet_set_first $phy {phy_refclk_freq} {100_MHz}]
set need_usr   [rivet_set_first $phy {phy_userclk_freq} {250_MHz}]
rivet_set_first $phy {phy_userclk2_freq} {250_MHz}
set need_mac   [rivet_set_first $phy {phy_use_xilinx_mac} {false}]
if {!$need_width || !$need_speed || !$need_ref || !$need_usr || !$need_mac} {
  rivet_pin_dump $phy
  error "PG345 basic config was rejected. See CONFIG warnings above."
}
rivet_set_first $phy {pll_type} {LCPLL}
rivet_set_first $phy {ins_loss_profile} {Add-in_Card}
rivet_set_first $phy {aspm} {No_ASPM}
rivet_set_first $phy {tx_preset} {4}
rivet_set_first $phy {phy_async_en} {false}
rivet_set_first $phy {enable_gtwizard} {true}

# Leave phy_refclk, phy_gtrefclk, phy_rst_n, and the pcie_mgt serial pins
# for block automation. It inserts the GT wizard and names reset sys_reset.
# MAC pins are exported first so the wrapper keeps the PIPE contract.
rivet_export $phy phy_pclk                 O {phy_pclk} 1
rivet_export $phy phy_userclk              O {phy_userclk} 1
rivet_export $phy phy_ready                O {phy_ready} 1
rivet_export $phy phy_txdata               I {phy_txdata} 256
rivet_export $phy phy_txdatak              I {phy_txdatak} 8
rivet_export $phy phy_txdata_valid         I {phy_txdata_valid} 4
rivet_export $phy phy_txstart_block        I {phy_txstart_block} 4
rivet_export $phy phy_txsync_header        I {phy_txsync_header} 8
rivet_export $phy phy_rxdata               O {phy_rxdata} 256
rivet_export $phy phy_rxdatak              O {phy_rxdatak} 8
rivet_export $phy phy_rxdata_valid         O {phy_rxdata_valid} 4
rivet_export $phy phy_rxstart_block        O {phy_rxstart_block} 8
rivet_export $phy phy_rxsync_header        O {phy_rxsync_header} 8
rivet_export $phy phy_txdetectrx_loopback  I {phy_txdetectrx_loopback} 4
rivet_export $phy phy_txelecidle           I {phy_txelecidle} 4
rivet_export $phy phy_txcompliance         I {phy_txcompliance} 4
rivet_export $phy phy_rxpolarity           I {phy_rxpolarity} 4
rivet_export $phy phy_powerdown            I {phy_powerdown} 8
rivet_export $phy phy_rate                 I {phy_rate} 3
rivet_export $phy phy_rx_termination       I {phy_rx_termination phy_rxtermination} 4
rivet_export $phy phy_rxvalid              O {phy_rxvalid} 4
rivet_export $phy phy_phystatus            O {phy_phystatus} 4
rivet_export $phy phy_phystatus_rst        O {phy_phystatus_rst} 1
rivet_export $phy phy_rxelecidle           O {phy_rxelecidle} 4
rivet_export $phy phy_rxstatus             O {phy_rxstatus} 12
rivet_export $phy phy_txmargin             I {phy_txmargin} 12
rivet_export $phy phy_txswing              I {phy_txswing} 4
rivet_export $phy phy_txdeemph             I {phy_txdeemph} 4
rivet_export $phy phy_txeq_ctrl            I {phy_txeq_ctrl} 8
rivet_export $phy phy_txeq_preset          I {phy_txeq_preset} 16
rivet_export $phy phy_txeq_coeff           I {phy_txeq_coeff} 24
rivet_export $phy phy_txeq_fs              O {phy_txeq_fs} 6
rivet_export $phy phy_txeq_lf              O {phy_txeq_lf} 6
rivet_export $phy phy_txeq_new_coeff       O {phy_txeq_new_coeff phy_txeq_newcoeff} 72
rivet_export $phy phy_txeq_done            O {phy_txeq_done} 4
rivet_export $phy phy_rxeq_ctrl            I {phy_rxeq_ctrl} 8
rivet_export $phy phy_rxeq_txpreset        I {phy_rxeq_txpreset} 16
rivet_export $phy phy_rxeq_preset_sel      O {phy_rxeq_preset_sel} 4
rivet_export $phy phy_rxeq_new_txcoeff     O {phy_rxeq_new_txcoeff phy_rx_new_txcoeff} 72
rivet_export $phy phy_rxeq_adapt_done      O {phy_rxeq_adapt_done} 4
rivet_export $phy phy_rxeq_done            O {phy_rxeq_done} 4
rivet_export $phy pcie_ltssm_state         I {pcie_ltssm_state} 6
rivet_export $phy pcie_link_reach_target   I {pcie_link_reach_target} 1

if {![rivet_automate $phy]} {
  rivet_pin_dump $phy
  puts "Intf pins:"
  foreach p [lsort [get_bd_intf_pins -quiet $phy/*]] {
    puts "  $p"
  }
  error "PG345 block automation did not connect the GT quad"
}
puts "BD cells after automation:"
foreach c [get_bd_cells -quiet] {
  puts "  $c"
}
rivet_shell_owns_refclk $phy
rivet_tie_open_inputs $phy
puts "BD ports:"
foreach p [lsort [get_bd_ports -quiet]] {
  puts "  [get_property DIR $p] [rivet_width $p] [get_property NAME $p]"
}
puts "BD interface ports:"
foreach p [lsort [get_bd_intf_ports -quiet]] {
  puts "  [get_property NAME $p]"
}

validate_bd_design
save_bd_design
set bd [get_files pcie_phy_bd.bd]
generate_target {synthesis instantiation_template} $bd
set wrapper [make_wrapper -files $bd -top -force]
add_files -norecurse $wrapper

set_property top rivet_vmk180_ep [current_fileset]
update_compile_order -fileset sources_1

set do_synth 0
if {[info exists argv] && [llength $argv] > 0 && [lindex $argv 0] eq "synth"} {
  set do_synth 1
}
if {$do_synth} {
  launch_runs synth_1 -jobs 4
  wait_on_run synth_1
  if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 failed — see $build_dir"
  }
  puts "PASS: synth_1 complete"
}

puts "Project: [file join $build_dir rivet_vmk180.xpr]"
puts "Open it in Vivado, run synth, then impl. LEDs: \[0\]=link_up \[1\]=phy_ready \[2\]=heartbeat \[3\]=L0."
close_project
