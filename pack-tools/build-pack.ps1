#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a distributable .zip of the IQ Edition PrismLauncher instance.

.DESCRIPTION
    Packages the instance root (instance.cfg, mmc-pack.json, patches/) plus the
    minecraft/ game dir, INCLUDING the .git repo so a developer can unpack the
    zip, import it into PrismLauncher, launch, then commit changes and push.

    Pure-runtime / local-only content is excluded: libraries/, natives/, saves,
    backups, screenshots, logs, crash-reports, cachedImages, journeymap data,
    Xaero waypoints, mod runtime caches (falsepattern/, alexiil/).

.PARAMETER InstanceDir
    PrismLauncher instance root. Defaults to the instance that contains this
    repo (..\.. relative to the repo, i.e. instances\1.7.10).

.PARAMETER Output
    Destination .zip path. Defaults to <InstanceDir>.zip in the PrismLauncher
    instances parent directory.

.PARAMETER NoGit
    Exclude the .git directory (plain instance export).

.NOTES
    Uses .NET ZipArchive (no external tools). Requires game/PrismLauncher closed.
#>
param(
    [string]$InstanceDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$Output = "",
    [switch]$NoGit
)

$ErrorActionPreference = "Stop"

# ---- Validate ----
if (-not (Test-Path (Join-Path $InstanceDir "instance.cfg"))) {
    throw "Not an instance dir (no instance.cfg): $InstanceDir"
}
# Resolve to the long form: Get-ChildItem returns long paths, so substring
# math below must use the same form (CI temp dirs may use 8.3 short names).
$InstanceDir = (Get-Item $InstanceDir).FullName.TrimEnd('\')
$minecraft = Join-Path $InstanceDir "minecraft"
if (-not (Test-Path (Join-Path $minecraft ".git"))) {
    throw "Expected a git repo at $minecraft\.git"
}

if (-not $Output) {
    $parent = Split-Path -Parent $InstanceDir
    $name = Split-Path -Leaf $InstanceDir
    $Output = Join-Path $parent "$name.zip"
}
$Output = [System.IO.Path]::GetFullPath($Output)

# Directories that never ship (relative to instance root or minecraft root)
# NOTE: libraries/ must ship - it holds the "local" lwjgl3ify forgePatches jar
# that Prism cannot re-download (see patches/me.eigenraven.lwjgl3ify.forgepatches.json).
$instanceSkipDirs = @("natives")
$mcSkipDirs = @(
    "backups", "cachedImages", "crash-reports", "journeymap",
    "logs", "saves", "screenshots", "shaderpacks", "texturepacks",
    ".codegraph", ".omo", "falsepattern", "alexiil"
)
if ($NoGit) { $mcSkipDirs += ".git" }

$fileSkipPatterns = @("*.lock", "*.tmp", "hs_err_pid*.log")

function Test-ShouldSkip {
    param([string]$fullPath, [string]$relPath)
    foreach ($d in $instanceSkipDirs) {
        if ($relPath -eq $d -or $relPath.StartsWith("$d/")) { return $true }
    }
    foreach ($d in $mcSkipDirs) {
        if ($relPath -eq "minecraft/$d" -or $relPath.StartsWith("minecraft/$d/")) { return $true }
    }
    foreach ($p in $fileSkipPatterns) {
        if ([System.IO.Path]::GetFileName($relPath) -like $p) { return $true }
    }
    return $false
}

Write-Host "Source : $InstanceDir" -ForegroundColor Cyan
Write-Host "Output : $Output" -ForegroundColor Cyan

# ---- Collect entries ----
$entries = New-Object System.Collections.Generic.List[object]

# instance root files (not dirs we skip)
Get-ChildItem $InstanceDir -Force | ForEach-Object {
    $rel = $_.Name
    if ($_.PSIsContainer) { return }
    if (-not (Test-ShouldSkip $_.FullName $rel)) {
        $entries.Add([pscustomobject]@{ Source = $_.FullName; Target = $rel })
    }
}

# instance root dirs: patches + libraries (rel = path under InstanceDir)
foreach ($d in @("patches", "libraries")) {
    $p = Join-Path $InstanceDir $d
    if (Test-Path $p) {
        $base = (Get-Item $p).FullName.TrimEnd('\')
        Get-ChildItem -LiteralPath $base -Recurse -File -Force | ForEach-Object {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\').Replace('\', '/')
            $target = "$d/$rel"
            if (-not (Test-ShouldSkip $_.FullName $target)) {
                $entries.Add([pscustomobject]@{ Source = $_.FullName; Target = $target })
            }
        }
    }
}

# minecraft dir: everything not skipped  (target = path under instance root)
$base = (Get-Item $minecraft).FullName.TrimEnd('\')
Get-ChildItem -LiteralPath $base -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($base.Length).TrimStart('\').Replace('\', '/')
    $target = "minecraft/$rel"
    if (-not (Test-ShouldSkip $_.FullName $target)) {
        $entries.Add([pscustomobject]@{ Source = $_.FullName; Target = $target })
    }
}

Write-Host ("Collected {0} files" -f $entries.Count)

# ---- Write zip ----
if (Test-Path $Output) { Remove-Item $Output -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($Output, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $i = 0
    foreach ($e in $entries) {
        $i++
        if ($i % 2000 -eq 0) { Write-Host ("  {0}/{1}" -f $i, $entries.Count) }
        $entry = $zip.CreateEntry($e.Target, [System.IO.Compression.CompressionLevel]::Optimal)
        $in = [System.IO.File]::OpenRead($e.Source)
        $out = $entry.Open()
        try {
            $in.CopyTo($out)
        } finally {
            $out.Dispose(); $in.Dispose()
        }
    }
} finally {
    $zip.Dispose()
}

$final = Get-Item $Output
Write-Host ("Built {0} ({1:N1} MB, {2} files)" -f $Output, ($final.Length/1MB), $entries.Count) -ForegroundColor Green
