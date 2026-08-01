# Run until board.v $finish (Gen1 then Gen2 PHY traffic complete).
# Default Vivado export used only "run 1000ns", which ends before the stimulus.
onbreak {quit -f}
onerror {quit -f}

vsim -c -lib xil_defaultlib board_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

run -all
quit -force
