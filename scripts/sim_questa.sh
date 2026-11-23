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
LANES="${2:-${RIVET_TB_LANES:-1}}"
MODE="${3:-0}"

UVM_INC=()
if [[ -n "${UVM_HOME:-}" && -d "${UVM_HOME}/src" ]]; then
  UVM_INC+=("+incdir+${UVM_HOME}/src")
fi

echo "Compiling Rivet UVM (test=${TESTNAME} lanes=${LANES} mode=${MODE})..."
vlog -sv -work work \
  "+define+RIVET_TB_LANES=${LANES}" \
  "+define+RIVET_TB_MODE=${MODE}" \
  +incdir+tb/uvm \
  +incdir+rtl/interfaces \
  +incdir+rtl/pcie_ctrl \
  +incdir+third_party/ref/common_cells/include \
  "${UVM_INC[@]}" \
  -f tb/uvm/filelist_uvm.f

echo "Running vsim ${TESTNAME}..."
vsim -c work.rivet_tb_top \
  -L mtiUvm \
  -suppress 7061 \
  "+UVM_TESTNAME=${TESTNAME}" \
  -do "run -all; quit -f"
