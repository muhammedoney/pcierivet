# Elaborates PG213 RP model + Rivet EP+PG239 board (module board + glbl).
vmap xil_defaultlib questa_lib/msim/xil_defaultlib
vmap gtwizard_ultrascale_v1_7_19 questa_lib/msim/gtwizard_ultrascale_v1_7_19
vopt -l vopt.log +acc=npr -suppress 10016 \
  -L xil_defaultlib -L gtwizard_ultrascale_v1_7_19 \
  -L unisims_ver -L unimacro_ver -L secureip \
  -work xil_defaultlib \
  xil_defaultlib.board xil_defaultlib.glbl \
  -o board_opt
