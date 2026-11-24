# Generate local PG239 PHYs for Gen3 (8.0 GT/s) and Gen4 (16.0 GT/s).
# Vivado 2024.2, part xcvu9p-flga2104-2L-e. Output stays under
# C:/Users/tosba/vivado and is not committed.
#
#   vivado -mode batch -source scripts/gen_pg239_speed.tcl

set part      xcvu9p-flga2104-2L-e
set out_root  C:/Users/tosba/vivado
set log_path  $out_root/rivet_phy_speed/result.txt

proc rivet_try {obj name value} {
  if {[catch {set_property CONFIG.$name $value $obj} err]} {
    puts "WARN: CONFIG.$name=$value rejected: $err"
    if {![catch {set legal [list_property_value CONFIG.$name $obj]}]} {
      puts "      legal ${name}: $legal"
    }
    return 0
  }
  return 1
}

proc rivet_note {text} {
  global log_path
  puts $text
  set fh [open $log_path a]
  puts $fh $text
  close $fh
}

file mkdir [file dirname $log_path]
set fh [open $log_path w]
puts $fh "start [clock format [clock seconds]]"
close $fh

proc rivet_make_phy {tag speed} {
  global part out_root
  set proj_dir [file join $out_root "rivet_phy_${tag}"]
  set ex_dir   [file join $out_root "rivet_phy_${tag}_ex"]
  file mkdir $proj_dir
  file delete -force $ex_dir

  create_project "rivet_phy_${tag}" $proj_dir -part $part -force
  set_property target_language Verilog [current_project]

  create_ip -name pcie_phy -vendor xilinx.com -library ip -module_name pcie_phy_0
  set ip [get_ips pcie_phy_0]
  if {[catch {set legal [list_property_value CONFIG.phy_max_speed $ip]} err]} {
    rivet_note "FAIL ${tag}: cannot list phy_max_speed ($err)"
    close_project
    return 0
  }
  rivet_note "LEGAL phy_max_speed: $legal"

  if {![rivet_try $ip gt_type GTY]} {
    rivet_note "FAIL ${tag}: gt_type"
    close_project
    return 0
  }
  rivet_try $ip phy_lane         X4
  if {![rivet_try $ip phy_max_speed $speed]} {
    rivet_note "FAIL ${tag}: phy_max_speed $speed not accepted"
    close_project
    return 0
  }
  rivet_try $ip phy_refclk_freq  100_MHz
  rivet_try $ip phy_userclk_freq 250_MHz
  rivet_try $ip phy_async_en     true
  rivet_try $ip pll_type         QPLL1
  rivet_try $ip tx_preset        4
  rivet_try $ip ins_loss_profile Add-in_Card
  rivet_try $ip aspm             No_ASPM
  rivet_try $ip lane0_gt_bank     GTY_Quad_227
  rivet_try $ip lane0_gt_location GTYE4_CHANNEL_X1Y35
  rivet_try $ip refclk1_location  Bank_227_MGTREFCLK0

  if {[catch {generate_target {instantiation_template synthesis simulation} $ip} err]} {
    rivet_note "FAIL ${tag}: generate_target: $err"
    close_project
    return 0
  }

  set got [get_property CONFIG.phy_max_speed $ip]
  rivet_note "PASS ip ${tag} phy_max_speed=$got dir=$proj_dir"

  if {[catch {open_example_project -force -dir $ex_dir $ip} err]} {
    rivet_note "FAIL ${tag}: example project: $err"
    catch {close_project}
    return 0
  }
  rivet_note "PASS example ${tag} dir=$ex_dir"
  catch {close_project}
  catch {close_project}
  return 1
}

set gen3_ok [rivet_make_phy gen3 8.0_GT/s]
set gen4_ok [rivet_make_phy gen4 16.0_GT/s]
rivet_note "done gen3=$gen3_ok gen4=$gen4_ok"
if {!$gen3_ok || !$gen4_ok} {
  exit 1
}
exit 0
