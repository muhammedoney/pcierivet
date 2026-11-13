# Copyright 2026 Rivet contributors
# Pack the Rivet tree for copy onto a machine that has a Quartus Prime Pro license.
# Does not create a project and does not run synthesis.
#
# Usage (from anywhere):
#   powershell -File fpga\c10gx\pack_transfer.ps1
#   powershell -File fpga\c10gx\pack_transfer.ps1 -OutDir D:\bags
#   powershell -File fpga\c10gx\pack_transfer.ps1 -IncludeGit
#   fpga\c10gx\pack_transfer.cmd
#   fpga/c10gx/pack_transfer.sh
#   fpga/c10gx/pack_transfer.sh --out-dir ~/bags
#
# Default zip (next to the repo):
#   ..\rivet_transfer_c10gx_YYYYMMDD_HHMM.zip
#
# On the licensed machine, after unzip:
#   fpga\c10gx\create_project.cmd
#   fpga\c10gx\synth.cmd

param(
  [string]$OutDir = "",
  [string]$ZipName = "",
  [switch]$IncludeGit,
  [switch]$IncludeBuild,
  [switch]$KeepStage,
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$marker = Join-Path $RepoRoot "rtl\pcie_ctrl\rivet_pcie_ctrl.sv"
if (-not (Test-Path -LiteralPath $marker)) {
  throw "Expected Rivet sources at $marker"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmm"
if (-not $OutDir) { $OutDir = Split-Path $RepoRoot -Parent }
if (-not $ZipName) { $ZipName = "rivet_transfer_c10gx_$stamp.zip" }
$zipPath = Join-Path $OutDir $ZipName
$stageRoot = Join-Path $env:TEMP ("rivet_pack_" + $stamp + "_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$stage = Join-Path $stageRoot "rivet"

Write-Host "Repo:  $RepoRoot"
Write-Host "Stage: $stage"
Write-Host "Zip:   $zipPath"
Write-Host "Mode:  IncludeGit=$IncludeGit IncludeBuild=$IncludeBuild"

$excludeDirs = @(
  ".Xil",
  "build",
  "work",
  "obj_dir",
  "sim_build",
  "out",
  "questa_lib",
  "waves",
  "xsim.dir",
  "__pycache__",
  ".vscode",
  ".cursor",
  "node_modules",
  "specs",
  (Join-Path $RepoRoot "third_party\bfm"),
  (Join-Path $RepoRoot "third_party\xilinx_ip"),
  (Join-Path $RepoRoot "third_party\ref\pcievhost"),
  (Join-Path $RepoRoot "third_party\ref\PCI_Express_Gen7.0")
)

if (-not $IncludeGit) { $excludeDirs += ".git" }

$excludeFiles = @(
  "*.jou",
  "*.str",
  "*.log",
  "*.vcd",
  "*.fst",
  "*.fsdb",
  "*.wdb",
  "*.vpd",
  "*.wlf",
  "*.pb",
  "*.ucdb",
  "*.zip",
  "local_paths.ps1",
  "local_paths.sh",
  ".env"
)

if ($WhatIf) {
  Write-Host ""
  Write-Host "Would exclude dirs: $($excludeDirs -join ', ')"
  Write-Host "Would exclude files: $($excludeFiles -join ', ')"
  Write-Host "Would write: $zipPath"
  exit 0
}

New-Item -ItemType Directory -Path $stage -Force | Out-Null

$xd = @("/XD") + $excludeDirs
$xf = @("/XF") + $excludeFiles
$roboArgs = @(
  $RepoRoot, $stage, "/E", "/COPY:DAT", "/R:1", "/W:1",
  "/NFL", "/NDL", "/NJH", "/NJS", "/NP"
) + $xd + $xf

Write-Host ""
Write-Host "Robocopy staging..."
& robocopy @roboArgs | Out-Null
$rc = $LASTEXITCODE
if ($rc -ge 8) {
  throw "robocopy failed with exit $rc"
}

if (-not $IncludeBuild) {
  $buildish = @(
    (Join-Path $stage "fpga\c10gx\build"),
    (Join-Path $stage "tb\bfm\pg239_phy\work"),
    (Join-Path $stage "tb\bfm\pg213_ep\work")
  )
  foreach ($d in $buildish) {
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  }
}

$need = @(
  "rtl\pcie_ctrl\rivet_pcie_ctrl.sv",
  "rtl\filelist_core.f",
  "rtl\phy\rivet_pipe_pg239_pad.sv",
  "rtl\phy\rivet_pcie_phy_c10gx.sv",
  "fpga\c10gx\rtl\rivet_c10gx_ep.sv",
  "fpga\c10gx\create_project.tcl",
  "fpga\c10gx\create_project.cmd",
  "fpga\c10gx\synth.tcl",
  "fpga\c10gx\synth.cmd",
  "fpga\c10gx\ip\gen_xcvr.tcl",
  "fpga\c10gx\constraints\c10gx_pcie.sdc",
  "fpga\c10gx\constraints\c10gx_pins.tcl",
  "fpga\c10gx\include\common_cells\registers.svh",
  "third_party\ref\common_cells\src\cc_cdc_2phase.sv",
  "third_party\ref\tech_cells_generic\src\rtl\tc_clk.sv",
  "third_party\ref\verilog-axis\rtl\axis_async_fifo.v"
)
foreach ($rel in $need) {
  $full = Join-Path $stage $rel
  if (-not (Test-Path -LiteralPath $full)) {
    throw "Transfer pack is missing $rel"
  }
}

$banned = @(
  (Join-Path $stage "specs"),
  (Join-Path $stage "fpga\c10gx\build"),
  (Join-Path $stage "scripts\local_paths.ps1"),
  (Join-Path $stage "scripts\local_paths.sh")
)
foreach ($p in $banned) {
  if (Test-Path -LiteralPath $p) {
    throw "Refusing to pack $p"
  }
}

$manifest = @"
rivet Cyclone 10 GX transfer pack
created: $(Get-Date -Format o)
host: $env:COMPUTERNAME
mode: IncludeGit=$IncludeGit IncludeBuild=$IncludeBuild
source: $RepoRoot

NOT included (regenerate on the destination, or omitted on purpose):
  - fpga/c10gx/build (Quartus project, Native PHY IP, synth runs)
  - sim work/, obj_dir/, logs, waveforms
  - specs/
  - scripts/local_paths.ps1 and local_paths.sh
  - third_party/bfm, third_party/xilinx_ip
  - .git unless this pack was made with -IncludeGit

On the machine with Quartus Prime Pro that covers Cyclone 10 GX:
  1. Unzip so the rivet\ folder is the repo root.
  2. Create the Quartus project only (no synthesis):
       fpga\c10gx\create_project.cmd
  3. Synthesize that project (separate script):
       fpga\c10gx\synth.cmd

Project file after step 2: fpga\c10gx\build\rivet_c10gx.qpf
Part: 10CX220YF780E5G
Docs: fpga\c10gx\README.md
"@
Set-Content -Path (Join-Path $stage "TRANSFER_README.txt") -Value $manifest -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

Write-Host "Compressing..."
Push-Location $stageRoot
try {
  Compress-Archive -Path "rivet" -DestinationPath $zipPath -CompressionLevel Optimal
} finally {
  Pop-Location
}

$zipSize = (Get-Item -LiteralPath $zipPath).Length
Write-Host ("OK  {0:N1} MB  {1}" -f ($zipSize / 1MB), $zipPath)

if (-not $KeepStage) {
  Remove-Item -LiteralPath $stageRoot -Recurse -Force
} else {
  Write-Host "Stage kept: $stageRoot"
}
