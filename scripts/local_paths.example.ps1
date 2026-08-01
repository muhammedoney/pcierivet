# Example local tool paths for Windows PowerShell
# Copy to local_paths.ps1 (gitignored) and edit.
# Prefer uvm-1.1d to match Questa built-in mtiUvm (avoids compiling UVM DPI).

# $env:QUESTA_HOME = "C:\questasim64_2024.1"
# $env:PATH = "$(Join-Path $env:QUESTA_HOME 'win64');$env:PATH"
# $env:UVM_HOME = Join-Path $env:QUESTA_HOME "verilog_src\uvm-1.1d"

# Vivado + BFM examples (prefer in-repo gitignored copies under third_party/xilinx_ip)
# $env:XILINX_VIVADO = "C:\Xilinx\Vivado\2024.2"
# $RepoRoot = Split-Path $PSScriptRoot -Parent   # if sourcing from scripts/
# $env:RIVET_PG239_EX = Join-Path (Split-Path $PSScriptRoot -Parent) "third_party\xilinx_ip\pcie_phy_0_ex"
# $env:RIVET_PG213_EX = Join-Path (Split-Path $PSScriptRoot -Parent) "third_party\xilinx_ip\pcie4_uscale_plus_0_ex"
# $env:RIVET_QUESTA_SIMLIB = "C:\Users\tosba\vivado\pcie_phy_0_ex\pcie_phy_0_ex.cache\compile_simlib\questa"
# Optional: sources for .\scripts\sync_xilinx_examples.ps1
# $env:RIVET_PG239_EX_SRC = "C:\Users\tosba\vivado\pcie_phy_0_ex"
# $env:RIVET_PG213_EX_SRC = "C:\Users\tosba\vivado\pcie4_uscale_plus_0_ex"
