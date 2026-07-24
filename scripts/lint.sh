# Copyright 2026 Rivet contributors
# Verilator lint of rivet_pcie_ctrl

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: verilator not found in PATH"
  exit 1
fi

verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSED \
  -f rtl/filelist_core.f \
  --top-module rivet_pcie_ctrl

echo "PASS: Verilator lint (controller)"
