# Rivet RC + PG213 Endpoint model.
vmap xil_defaultlib questa_lib/msim/xil_defaultlib
vmap gtwizard_ultrascale_v1_7_19 questa_lib/msim/gtwizard_ultrascale_v1_7_19
vopt -l vopt.log +acc=npr -suppress 10016 -suppress 7061 \
  -L xil_defaultlib -L gtwizard_ultrascale_v1_7_19 \
  -L xpm -L unisims_ver -L unimacro_ver -L secureip \
  -work xil_defaultlib \
  xil_defaultlib.board xil_defaultlib.glbl \
  -o board_opt
