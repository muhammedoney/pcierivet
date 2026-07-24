# Copyright 2026 Rivet contributors
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p synth/yosys
if ! command -v yosys >/dev/null 2>&1; then
  echo "ERROR: yosys not found in PATH"
  exit 1
fi
yosys -s synth/yosys/rivet_pcie_ctrl.ys
echo "PASS: Yosys synth stub"
