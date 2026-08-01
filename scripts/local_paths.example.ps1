# Example local tool paths for Windows PowerShell
# Copy to local_paths.ps1 (gitignored) and edit.
# Prefer uvm-1.1d to match Questa built-in mtiUvm (avoids compiling UVM DPI).

# $env:QUESTA_HOME = "C:\questasim64_2024.1"
# $env:PATH = "$(Join-Path $env:QUESTA_HOME 'win64');$env:PATH"
# $env:UVM_HOME = Join-Path $env:QUESTA_HOME "verilog_src\uvm-1.1d"

# Vivado + PG239 PHY example BFM
# $env:XILINX_VIVADO = "C:\Xilinx\Vivado\2024.2"
# $env:RIVET_PG239_EX = "C:\Users\tosba\vivado\pcie_phy_0_ex"
# $env:RIVET_QUESTA_SIMLIB = Join-Path $env:RIVET_PG239_EX "pcie_phy_0_ex.cache\compile_simlib\questa"

# PG213 EP example BFM (Questa export under %RIVET_PG213_EX%\questa)
# $env:RIVET_PG213_EX = "C:\Users\tosba\vivado\pcie4_uscale_plus_0_ex"
