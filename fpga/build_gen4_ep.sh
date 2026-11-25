#!/usr/bin/env bash
# Copyright 2026 Rivet contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
export RIVET_NO_PAUSE=1
steps=(
  "fpga/vcu118/create_project.cmd 4 ep"
  "fpga/vcu118/impl.cmd 4 ep"
  "fpga/vmk180/create_project.cmd 4 ep"
  "fpga/vmk180/impl.cmd 4 ep"
)
dry=0
if [[ "${1:-}" == "--dry-run" ]]; then dry=1; fi
if [[ "${1:-}" != "" && "${1:-}" != "--dry-run" ]]; then
  echo "Usage: fpga/build_gen4_ep.sh [--dry-run]" >&2
  exit 1
fi
for step in "${steps[@]}"; do
  printf '%s\n' "$step"
  if [[ "$dry" -eq 0 ]]; then
    if command -v cmd.exe >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      cmd.exe /c $step
    elif command -v vivado >/dev/null 2>&1; then
      board="${step#fpga/}"
      board="${board%%/*}"
      src="create_project.tcl"
      case "$step" in
        *impl.cmd*) src="impl.tcl" ;;
      esac
      vivado -mode batch -source "fpga/${board}/${src}" -tclargs 4 ep
    else
      echo "vivado.bat not found"
      echo "Set VIVADO_PATH or XILINX_VIVADO to the Vivado install root"
      echo "(the folder that contains bin/vivado.bat), or add vivado.bat to PATH."
      echo "Also checked C:\\Xilinx\\Vivado and Program Files\\Xilinx\\Vivado."
      exit 1
    fi
  fi
done
