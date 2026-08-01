# Elaborates Rivet+PG239 board (rivet_pg239_board + glbl).
vopt -l vopt.log +acc=npr -suppress 10016 \
  -L xil_defaultlib -L gtwizard_ultrascale_v1_7_19 \
  -L unisims_ver -L unimacro_ver -L secureip \
  -work xil_defaultlib \
  xil_defaultlib.rivet_pg239_board xil_defaultlib.glbl \
  -o board_opt
