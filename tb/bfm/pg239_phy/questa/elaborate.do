# Elaborates board + glbl with Xilinx compiled simlibs (unisims_ver, secureip, ...).
# Invoked from tb/bfm/pg239_phy/work after modelsim.ini is copied from compile_simlib.
# Log file name must not collide with the outer runner Tee-Object target.
vopt -l vopt.log +acc=npr -suppress 10016 \
  -L xil_defaultlib -L gtwizard_ultrascale_v1_7_19 \
  -L unisims_ver -L unimacro_ver -L secureip \
  -work xil_defaultlib \
  xil_defaultlib.board xil_defaultlib.glbl \
  -o board_opt
