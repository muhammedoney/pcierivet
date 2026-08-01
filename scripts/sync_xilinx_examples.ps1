#Requires -Version 5.1
<#
.SYNOPSIS
  Copy Vivado PG239 / PG213 example trees into third_party/xilinx_ip (gitignored).

.DESCRIPTION
  Does not copy .cache / .runs / .hw. Overwrites the in-repo copies.
  Sources default to C:\Users\tosba\vivado\... or RIVET_*_EX_SRC if set.
#>
param(
  [string]$Pg239Src = $(if ($env:RIVET_PG239_EX_SRC) { $env:RIVET_PG239_EX_SRC } else { "C:\Users\tosba\vivado\pcie_phy_0_ex" }),
  [string]$Pg213Src = $(if ($env:RIVET_PG213_EX_SRC) { $env:RIVET_PG213_EX_SRC } else { "C:\Users\tosba\vivado\pcie4_uscale_plus_0_ex" })
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DstRoot = Join-Path $RepoRoot "third_party\xilinx_ip"

function Sync-Example([string]$Src, [string]$Name, [string[]]$ExtraExcludeDirs) {
  if (-not (Test-Path $Src)) {
    Write-Warning "Skip $Name — source missing: $Src"
    return
  }
  $Dst = Join-Path $DstRoot $Name
  if (Test-Path $Dst) {
    $item = Get-Item $Dst
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      Write-Host "Removing junction $Dst"
      cmd /c "rmdir `"$Dst`""
    }
  }
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  $xd = @(".Xil", "$Name.cache", "$Name.runs", "$Name.hw", "$Name.sim") + $ExtraExcludeDirs
  Write-Host "Robocopy $Src -> $Dst"
  $args = @($Src, $Dst, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np", "/XF", "*.jou", "*.log")
  foreach ($d in $xd) { $args += @("/XD", $d) }
  & robocopy @args | Out-Null
  $code = $LASTEXITCODE
  if ($code -ge 8) { throw "robocopy failed for $Name (code $code)" }
  Write-Host "OK $Name (robocopy code $code)"
}

Sync-Example $Pg239Src "pcie_phy_0_ex" @()
Sync-Example $Pg213Src "pcie4_uscale_plus_0_ex" @()
Write-Host "Done. Trees are gitignored under third_party/xilinx_ip/."
Write-Host "Point local_paths: RIVET_PG239_EX / RIVET_PG213_EX -> these folders."
