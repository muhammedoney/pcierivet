# Stock PG213 board: run until $finish (PIO or timeout).
onbreak {quit -f}
onerror {quit -f}

vsim -c -lib xil_defaultlib board_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

run -all
quit -force
