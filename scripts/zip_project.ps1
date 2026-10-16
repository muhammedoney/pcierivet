# Copyright 2026 Rivet contributors
# Zip the working tree and .git. Gitignored and other regenerable files stay out.
#
#   .\scripts\zip_project.ps1
#   .\scripts\zip_project.ps1 D:\rivet-src.zip
#   .\scripts\zip_project.cmd
#
# Default archive: <parent of repo>\rivet-src-<timestamp>.zip

param(
  [Parameter(Position = 0)]
  [string]$Output
)

$ErrorActionPreference = "Stop"
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Set-Location $Root

if (-not (Test-Path -LiteralPath (Join-Path $Root ".git") -PathType Container)) {
  Write-Error "No .git directory at $Root"
}

if (-not $Output) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmm"
  $Output = Join-Path (Split-Path -Parent $Root) "rivet-src-$stamp.zip"
}
$OutFull = [IO.Path]::GetFullPath($Output)
$rootPrefix = $Root.TrimEnd('\') + '\'
if ($OutFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  Write-Error "Write the zip outside the repo ($OutFull is inside $Root)."
}

function Test-Regenerable([string]$Rel) {
  $p = ($Rel -replace '\\', '/').TrimStart('/')
  if ($p -eq '.git' -or $p.StartsWith('.git/')) {
    return $false
  }
  $leaf = [IO.Path]::GetFileName($p)
  $ext = [IO.Path]::GetExtension($leaf).ToLowerInvariant()
  $skipExt = @(
    '.log', '.jou', '.pb', '.wlf', '.vcd', '.fst', '.fsdb', '.ucdb', '.cov',
    '.o', '.a', '.so', '.dll', '.exe', '.pyc', '.mti', '.mpf', '.xpr', '.str',
    '.ltx', '.zip', '.tgz', '.tar'
  )
  if ($skipExt -contains $ext) { return $true }
  if ($leaf -match '^(transcript|vsim\.wlf|modelsim\.ini|Thumbs\.db|\.DS_Store)$') { return $true }
  if ($p -match '(^|/)(work|questa_lib|obj_dir|build|out|sim_build|__pycache__|\.Xil)(/|$)') { return $true }
  if ($p -match '(^|/)\.(cache|hw|ip_user_files|runs|sim|srcs|gen)(/|$)') { return $true }
  if ($p -match '(^|/)(tx|rx|error)\.dat$') { return $true }
  if ($p -match '(^|/)specs(/|$)') { return $true }
  if ($p -match '^third_party/bfm/' -and $leaf -ne 'README.md') { return $true }
  return $false
}

function Add-GitPaths([string]$Prefix, [System.Collections.Generic.HashSet[string]]$Set) {
  $dir = if ($Prefix) { Join-Path $Root ($Prefix -replace '/', '\') } else { $Root }
  Push-Location $dir
  try {
    $lines = & git -c core.quotepath=false ls-files -co --exclude-standard
    if ($LASTEXITCODE -ne 0) { Write-Error "git ls-files failed in $dir" }
  } finally {
    Pop-Location
  }
  foreach ($line in @($lines)) {
    if (-not $line) { continue }
    $rel = if ($Prefix) { "$Prefix/$($line -replace '\\', '/')" } else { ($line -replace '\\', '/') }
    $rel = $rel -replace '^\./', ''
    if (Test-Regenerable $rel) { continue }
    $full = Join-Path $Root ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    [void]$Set.Add($rel)
  }
}

$set = New-Object 'System.Collections.Generic.HashSet[string]'
Add-GitPaths "" $set

$subs = @(& git submodule foreach --recursive --quiet "echo `$sm_path")
foreach ($sm in @($subs | Where-Object { $_ -and $_.Trim() })) {
  $smRel = ($sm.Trim() -replace '\\', '/').TrimEnd('/')
  Add-GitPaths $smRel $set
  $gitFile = Join-Path (Join-Path $Root ($smRel -replace '/', '\')) ".git"
  if (Test-Path -LiteralPath $gitFile -PathType Leaf) {
    [void]$set.Add("$smRel/.git")
  }
}

Get-ChildItem -LiteralPath (Join-Path $Root ".git") -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  $rel = $_.FullName.Substring($rootPrefix.Length) -replace '\\', '/'
  $leaf = $_.Name
  if ($leaf -like '*.lock' -or $leaf -like '*.tmp' -or $leaf -eq 'gc.log') { return }
  [void]$set.Add($rel)
}

$paths = @($set | Sort-Object)
if ($paths.Count -eq 0) { Write-Error "Nothing to archive." }
foreach ($need in @('.git/HEAD', 'rtl/pcie_ctrl/rivet_pcie_ctrl.sv', '.gitignore')) {
  if (-not $set.Contains($need)) { Write-Error "Archive list is missing $need" }
}

$bad = @($paths | Where-Object { -not ($_ -eq '.git' -or $_.StartsWith('.git/')) -and (Test-Regenerable $_) })
if ($bad.Count -gt 0) {
  Write-Error ("Refusing to pack regenerable paths:`n" + ($bad -join "`n"))
}

if (Test-Path -LiteralPath $OutFull) { Remove-Item -LiteralPath $OutFull -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($OutFull, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($rel in $paths) {
    $full = Join-Path $Root ($rel -replace '/', '\')
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip, $full, ($rel -replace '\\', '/'), [System.IO.Compression.CompressionLevel]::Optimal)
  }
} finally {
  $zip.Dispose()
}
$zip = [System.IO.Compression.ZipFile]::Open($OutFull, [System.IO.Compression.ZipArchiveMode]::Read)
try {
  $listing = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
} finally {
  $zip.Dispose()
}

$packed = @($listing | Where-Object {
  $_ -match '(^|/)(work|questa_lib|obj_dir)/' -or
  $_ -match '\.(log|jou|wlf|vcd|fst|fsdb)$' -or
  $_ -match '(^|/)specs/' -or
  $_ -match 'fpga/vcu118/build/' -or
  $_ -match 'third_party/ref/(pcievhost|PCI_Express_Gen7)' -or
  ($_ -match '^third_party/bfm/' -and $_ -notmatch 'README\.md$')
})
if ($packed.Count -gt 0) {
  Remove-Item -LiteralPath $OutFull -Force
  Write-Error ("Zip contained regenerable paths:`n" + ($packed -join "`n"))
}
foreach ($need in @('.git/HEAD', 'rtl/pcie_ctrl/rivet_pcie_ctrl.sv')) {
  if (-not ($listing -contains $need)) {
    Remove-Item -LiteralPath $OutFull -Force
    Write-Error "Zip is missing $need"
  }
}

$mb = (Get-Item -LiteralPath $OutFull).Length / 1MB
Write-Host ("Wrote {0} ({1} files, {2:N1} MB)" -f $OutFull, $paths.Count, $mb)
