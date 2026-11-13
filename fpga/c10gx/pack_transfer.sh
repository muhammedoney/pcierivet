#!/usr/bin/env bash
# Copyright 2026 Rivet contributors
# Pack the Rivet tree for copy onto a machine that has a Quartus Prime Pro license.
# Does not create a project and does not run synthesis.
#
# Usage (from anywhere):
#   fpga/c10gx/pack_transfer.sh
#   fpga/c10gx/pack_transfer.sh --out-dir ~/bags
#   fpga/c10gx/pack_transfer.sh --include-git
#   fpga/c10gx/pack_transfer.sh --what-if
#
# Windows equivalent: fpga/c10gx/pack_transfer.cmd
#
# Default zip (next to the repo):
#   ../rivet_transfer_c10gx_YYYYMMDD_HHMM.zip
#
# On the licensed machine, after unzip:
#   fpga/c10gx/create_project.cmd
#   fpga/c10gx/synth.cmd

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pack_transfer.sh [options]

Pack Rivet sources into a zip for a machine with a Quartus Prime Pro license.
Does not create a project and does not run synthesis.

Options:
  --out-dir DIR       Directory for the zip (default: parent of the repo)
  --zip-name NAME     Zip file name (default: rivet_transfer_c10gx_YYYYMMDD_HHMM.zip)
  --include-git       Keep .git history
  --include-build     Skip the extra build/work cleanup (those dirs are still excluded)
  --keep-stage        Leave the staging directory in place
  --what-if           Print the exclude rules and exit
  -h, --help          Show this help

PowerShell-style aliases are accepted: -OutDir, -ZipName, -IncludeGit,
-IncludeBuild, -KeepStage, -WhatIf.
EOF
}

out_dir=""
zip_name=""
include_git=0
include_build=0
keep_stage=0
what_if=0

need_value() {
  local opt="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == -* ]]; then
    echo "ERROR: $opt needs a value" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --out-dir|--OutDir|-OutDir)
      need_value "$1" "${2:-}"
      out_dir="$2"
      shift 2
      ;;
    --zip-name|--ZipName|-ZipName)
      need_value "$1" "${2:-}"
      zip_name="$2"
      shift 2
      ;;
    --out-dir=*|--OutDir=*|-OutDir=*)
      out_dir="${1#*=}"
      shift
      ;;
    --zip-name=*|--ZipName=*|-ZipName=*)
      zip_name="${1#*=}"
      shift
      ;;
    --include-git|--IncludeGit|-IncludeGit)
      include_git=1
      shift
      ;;
    --include-build|--IncludeBuild|-IncludeBuild)
      include_build=1
      shift
      ;;
    --keep-stage|--KeepStage|-KeepStage)
      keep_stage=1
      shift
      ;;
    --what-if|--WhatIf|-WhatIf)
      what_if=1
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
marker="$repo_root/rtl/pcie_ctrl/rivet_pcie_ctrl.sv"
if [[ ! -f "$marker" ]]; then
  echo "ERROR: Expected Rivet sources at $marker" >&2
  exit 1
fi

stamp="$(date +%Y%m%d_%H%M)"
if [[ -z "$out_dir" ]]; then
  out_dir="$(cd "$repo_root/.." && pwd)"
else
  mkdir -p "$out_dir"
  out_dir="$(cd "$out_dir" && pwd)"
fi
if [[ -z "$zip_name" ]]; then
  zip_name="rivet_transfer_c10gx_${stamp}.zip"
fi
zip_path="$out_dir/$zip_name"

stage_root=""
cleanup() {
  if [[ "$keep_stage" -eq 0 && -n "$stage_root" && -d "$stage_root" ]]; then
    rm -rf "$stage_root"
  fi
}
trap cleanup EXIT

token="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
stage_root="${TMPDIR:-/tmp}/rivet_pack_${stamp}_${token}"
stage="$stage_root/rivet"

mode_git=false
mode_build=false
if [[ "$include_git" -eq 1 ]]; then mode_git=true; fi
if [[ "$include_build" -eq 1 ]]; then mode_build=true; fi

echo "Repo:  $repo_root"
echo "Stage: $stage"
echo "Zip:   $zip_path"
echo "Mode:  IncludeGit=$mode_git IncludeBuild=$mode_build"

exclude_dir_names=(
  .Xil
  build
  work
  obj_dir
  sim_build
  out
  questa_lib
  waves
  xsim.dir
  __pycache__
  .vscode
  .cursor
  node_modules
  specs
)
if [[ "$include_git" -eq 0 ]]; then
  exclude_dir_names+=(".git")
fi

exclude_rel_dirs=(
  third_party/bfm
  third_party/xilinx_ip
  third_party/ref/pcievhost
  third_party/ref/PCI_Express_Gen7.0
)

exclude_files=(
  '*.jou'
  '*.str'
  '*.log'
  '*.vcd'
  '*.fst'
  '*.fsdb'
  '*.wdb'
  '*.vpd'
  '*.wlf'
  '*.pb'
  '*.ucdb'
  '*.zip'
  local_paths.ps1
  local_paths.sh
  .env
)

if [[ "$what_if" -eq 1 ]]; then
  echo
  echo "Would exclude dirs: ${exclude_dir_names[*]}, ${exclude_rel_dirs[*]}"
  echo "Would exclude files: ${exclude_files[*]}"
  echo "Would write: $zip_path"
  stage_root=""
  exit 0
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync not found in PATH" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "ERROR: zip not found in PATH" >&2
  exit 1
fi

mkdir -p "$stage"

rsync_args=(-a)
for name in "${exclude_dir_names[@]}"; do
  rsync_args+=(--exclude "$name/")
  if [[ "$name" == ".git" ]]; then
    # A submodule checkout is a .git file, not a directory.
    rsync_args+=(--exclude ".git")
  fi
done
for rel in "${exclude_rel_dirs[@]}"; do
  rsync_args+=(--exclude "$rel/")
done
for pat in "${exclude_files[@]}"; do
  rsync_args+=(--exclude "$pat")
done

echo
echo "Staging..."
rsync "${rsync_args[@]}" "$repo_root/" "$stage/"

if [[ "$include_build" -eq 0 ]]; then
  rm -rf \
    "$stage/fpga/c10gx/build" \
    "$stage/tb/bfm/pg239_phy/work" \
    "$stage/tb/bfm/pg213_ep/work"
fi

need=(
  rtl/pcie_ctrl/rivet_pcie_ctrl.sv
  rtl/filelist_core.f
  rtl/phy/rivet_pipe_pg239_pad.sv
  rtl/phy/rivet_pcie_phy_c10gx.sv
  fpga/c10gx/rtl/rivet_c10gx_ep.sv
  fpga/c10gx/create_project.tcl
  fpga/c10gx/create_project.cmd
  fpga/c10gx/synth.tcl
  fpga/c10gx/synth.cmd
  fpga/c10gx/ip/gen_xcvr.tcl
  fpga/c10gx/constraints/c10gx_pcie.sdc
  fpga/c10gx/constraints/c10gx_pins.tcl
  fpga/c10gx/include/common_cells/registers.svh
  third_party/ref/common_cells/src/cc_cdc_2phase.sv
  third_party/ref/tech_cells_generic/src/rtl/tc_clk.sv
  third_party/ref/verilog-axis/rtl/axis_async_fifo.v
)
for rel in "${need[@]}"; do
  if [[ ! -e "$stage/$rel" ]]; then
    echo "ERROR: Transfer pack is missing $rel" >&2
    exit 1
  fi
done

banned=(
  specs
  fpga/c10gx/build
  scripts/local_paths.ps1
  scripts/local_paths.sh
)
for rel in "${banned[@]}"; do
  if [[ -e "$stage/$rel" ]]; then
    echo "ERROR: Refusing to pack $rel" >&2
    exit 1
  fi
done

host="$(hostname)"
created="$(date --iso-8601=seconds)"
cat > "$stage/TRANSFER_README.txt" <<EOF
rivet Cyclone 10 GX transfer pack
created: $created
host: $host
mode: IncludeGit=$mode_git IncludeBuild=$mode_build
source: $repo_root

NOT included (regenerate on the destination, or omitted on purpose):
  - fpga/c10gx/build (Quartus project, Native PHY IP, synth runs)
  - sim work/, obj_dir/, logs, waveforms
  - specs/
  - scripts/local_paths.ps1 and local_paths.sh
  - third_party/bfm, third_party/xilinx_ip
  - .git unless this pack was made with --include-git

On the machine with Quartus Prime Pro that covers Cyclone 10 GX:
  1. Unzip so the rivet/ folder is the repo root.
  2. Create the Quartus project only (no synthesis):
       fpga\\c10gx\\create_project.cmd
  3. Synthesize that project (separate script):
       fpga\\c10gx\\synth.cmd

Project file after step 2: fpga\\c10gx\\build\\rivet_c10gx.qpf
Part: 10CX220YF780E5G
Docs: fpga\\c10gx\\README.md
EOF

if [[ -e "$zip_path" ]]; then
  rm -f "$zip_path"
fi

echo "Compressing..."
if ! (cd "$stage_root" && zip -r -q -9 "$zip_path" rivet); then
  rm -f "$zip_path"
  echo "ERROR: zip failed" >&2
  exit 1
fi

bytes="$(stat -c %s "$zip_path")"
mb="$(LC_ALL=C awk -v b="$bytes" 'BEGIN { printf "%.1f", b/1048576 }')"
echo "OK  ${mb} MB  $zip_path"

if [[ "$keep_stage" -eq 1 ]]; then
  echo "Stage kept: $stage_root"
fi
