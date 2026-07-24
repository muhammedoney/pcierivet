# Copyright 2026 Rivet contributors
# Verilator elaborate / smoke (no UVM)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${ROOT}/build/verilator_smoke"
mkdir -p "$OUT"

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: verilator not found in PATH"
  exit 1
fi

verilator --cc --exe --build -Wall -Wno-DECLFILENAME -Wno-UNUSED \
  -f rtl/filelist_core.f \
  --top-module rivet_pcie_ctrl \
  -Mdir "$OUT" \
  tb/smoke/verilator_smoke_main.cpp

echo "PASS: Verilator smoke build"
