# Copyright 2026 Rivet contributors
# QuestaSim UVM smoke — requires local install. See docs/verification.md

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f scripts/local_paths.sh ]]; then
  # shellcheck disable=SC1091
  source scripts/local_paths.sh
fi

if ! command -v vsim >/dev/null 2>&1; then
  echo "ERROR: vsim not found. Install QuestaSim and set PATH / scripts/local_paths.sh"
  exit 1
fi

TESTNAME="${1:-smoke_gen2_x1}"
LANES="${RIVET_TB_LANES:-1}"

vlog -sv -work work \
  +incdir+tb/uvm \
  -f tb/uvm/filelist_uvm.f

vsim -c work.rivet_tb_top \
  +UVM_TESTNAME="${TESTNAME}" \
  -do "run -all; quit -f"
