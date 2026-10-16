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

$script:MeterOn = $true
try { if ([Console]::IsOutputRedirected) { $script:MeterOn = $false } } catch { $script:MeterOn = $false }
$script:MeterLast = [datetime]::MinValue
$script:MeterPct = -1
$script:MeterPrinted = -1
$script:SpinChars = @('|', '/', '-', [char]92)

function Format-Span([double]$Seconds) {
  $s = [int][math]::Round($Seconds)
  if ($s -lt 0) { $s = 0 }
  return ('{0:00}:{1:00}' -f [int]($s / 60), ($s % 60))
}

function Reset-Meter {
  $script:MeterLast = [datetime]::MinValue
  $script:MeterPct = -1
  $script:MeterPrinted = -1
}

function Complete-Meter {
  if ($script:MeterOn) {
    try { [Console]::WriteLine() } catch { Write-Host '' }
  }
}

function Write-Meter([int]$Done, [int]$Total, [string]$Phase, [string]$Item, [datetime]$Started) {
  if ($Total -lt 1) { $Total = 1 }
  $pct = [int][math]::Floor(100.0 * $Done / $Total)
  if ($Done -ge $Total) { $pct = 100 }
  $now = [datetime]::UtcNow
  $force = ($Done -eq 0 -or $Done -ge $Total -or $pct -ne $script:MeterPct)
  if ($script:MeterOn) {
    if (-not $force -and ($now - $script:MeterLast).TotalMilliseconds -lt 100) { return }
  } elseif (-not ($force -and ($Done -ge $Total -or ($pct % 10) -eq 0) -and $pct -ne $script:MeterPrinted)) {
    $script:MeterPct = $pct
    return
  }
  $script:MeterLast = $now
  $script:MeterPct = $pct
  $script:MeterPrinted = $pct

  $width = 100
  try {
    if ($script:MeterOn -and [Console]::WindowWidth -gt 40) { $width = [Console]::WindowWidth - 1 }
  } catch {}
  $spin = $script:SpinChars[$Done % 4]
  $cols = 24
  $filled = [int][math]::Floor($cols * $pct / 100.0)
  $bar = ('#' * $filled).PadRight($cols, '-')
  $left = $Total - $Done
  if ($left -lt 0) { $left = 0 }
  $elapsed = ($now - $Started).TotalSeconds
  $eta = ''
  if ($Done -gt 0 -and $Done -lt $Total -and $elapsed -ge 1) {
    $eta = '~' + (Format-Span ($elapsed * ($Total - $Done) / $Done))
  }
  $head = ('{0} {1} [{2}] {3,3}%  {4}/{5} done  {6} left  {7} {8}  ' -f `
      $spin, $Phase, $bar, $pct, $Done, $Total, $left, (Format-Span $elapsed), $eta)
  $room = $width - $head.Length
  $name = ($Item -replace '\\', '/')
  if ($room -lt 8) {
    $name = ''
  } elseif ($name.Length -gt $room) {
    $name = '...' + $name.Substring($name.Length - ($room - 3))
  }
  $line = $head + $name
  if ($line.Length -lt $width) { $line = $line.PadRight($width) }
  elseif ($line.Length -gt $width) { $line = $line.Substring(0, $width) }

  if ($script:MeterOn) {
    [Console]::Write("`r" + $line)
  } else {
    Write-Host $line.TrimEnd()
  }
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

Write-Host "Collecting files..."
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
Write-Host ("Collected {0} files" -f $paths.Count)
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
$packStarted = [datetime]::UtcNow
Reset-Meter
try {
  $done = 0
  $total = $paths.Count
  foreach ($rel in $paths) {
    Write-Meter $done $total 'Pack' $rel $packStarted
    $full = Join-Path $Root ($rel -replace '/', '\')
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip, $full, ($rel -replace '\\', '/'), [System.IO.Compression.CompressionLevel]::Optimal)
    $done++
  }
  Write-Meter $done $total 'Pack' 'done' $packStarted
} finally {
  Complete-Meter
  $zip.Dispose()
}
$zip = [System.IO.Compression.ZipFile]::Open($OutFull, [System.IO.Compression.ZipArchiveMode]::Read)
$checkStarted = [datetime]::UtcNow
Reset-Meter
$listing = New-Object System.Collections.Generic.List[string]
try {
  $entries = @($zip.Entries)
  $done = 0
  $total = $entries.Count
  if ($total -lt 1) { $total = 1 }
  foreach ($entry in $entries) {
    $listing.Add(($entry.FullName -replace '\\', '/'))
    $done++
    Write-Meter $done $entries.Count 'Check' $entry.FullName $checkStarted
  }
  if ($entries.Count -eq 0) { Write-Meter 0 1 'Check' 'empty' $checkStarted }
} finally {
  Complete-Meter
  $zip.Dispose()
}
$listing = @($listing)

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
