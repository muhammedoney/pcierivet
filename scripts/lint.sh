# Copyright 2026 Rivet contributors
# Verilator lint of rivet_pcie_ctrl

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: verilator not found in PATH"
  exit 1
fi

# 4 KB TLP slots are 33024 bits. The default replication limit is 8192.
verilator --lint-only --replication-limit 65536 -Wall -Wno-DECLFILENAME -Wno-UNUSED \
  +incdir+rtl/pcie_ctrl \
  +incdir+third_party/ref/common_cells/include \
  -f rtl/filelist_core.f \
  --top-module rivet_pcie_ctrl

echo "PASS: Verilator lint (controller)"
