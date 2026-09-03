# Rivet PG213 RP + Rivet EP board: run until $finish (PASS or Detect/Polling timeout).
onbreak {quit -f}
onerror {quit -f}

vmap xil_defaultlib questa_lib/msim/xil_defaultlib
vmap gtwizard_ultrascale_v1_7_19 questa_lib/msim/gtwizard_ultrascale_v1_7_19

vsim -c -lib xil_defaultlib board_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

run -all
quit -force
