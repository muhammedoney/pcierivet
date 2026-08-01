# Stock / Rivet PG213 board: run until $finish (PIO or timeout in board.v).
onbreak {quit -f}
onerror {quit -f}

vsim -c -lib xil_defaultlib board_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

run -all
quit -force
