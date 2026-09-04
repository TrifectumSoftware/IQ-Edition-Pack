#Requires -Version 5.1
<#
.SYNOPSIS
    Assembles the repository into a PrismLauncher instance folder and builds the
    distributable .zip (including .git). Used by CI (build-pack.yml).

.DESCRIPTION
    On CI the repo root IS the minecraft game dir (config/, mods/, resourcepacks/
    at the top). The instance-level metadata lives in pack-tools/instance-files/
    (instance.cfg, mmc-pack.json, patches/, .packignore). This script:
      1. copies instance-files/* to a staging instance root
      2. copies the whole repo (incl. .git) into staging/minecraft
      3. invokes pack-tools/build-pack.ps1 to produce the zip

.PARAMETER RepoRoot
    Path to the repository root (the minecraft folder on CI). Defaults to the
    parent of pack-tools.

.PARAMETER Output
    Destination .zip. Defaults to <RepoRoot>.zip in the parent of RepoRoot.
#>
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$instanceFiles = Join-Path $repoRoot "pack-tools\instance-files"

if (-not (Test-Path (Join-Path $instanceFiles "mmc-pack.json"))) {
    throw "Missing instance-files: $instanceFiles"
}
if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
    throw "Expected a git repo at $repoRoot\.git"
}

if (-not $Output) {
    $Output = "$repoRoot.zip"
}
$Output = [System.IO.Path]::GetFullPath($Output)

# ---- Stage the instance ----
$staging = Join-Path $env:TEMP ("iq-instance-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
try {
    $mc = Join-Path $staging "minecraft"
    New-Item -ItemType Directory -Path $mc -Force | Out-Null

    # Instance root metadata
    Copy-Item (Join-Path $instanceFiles "*") $staging -Recurse -Force
    Copy-Item (Join-Path $instanceFiles "patches") $staging -Recurse -Force

    # Repo content -> minecraft/ (include .git so devs can commit after unpack)
    robocopy $repoRoot $mc /E /XD .codegraph .omo /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }

    # ---- Build zip from staging ----
    # build-pack.ps1 throws on error; it is a script so it does not set $LASTEXITCODE.
    & (Join-Path $PSScriptRoot "build-pack.ps1") -InstanceDir $staging -Output $Output
} finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}

# robocopy may leave $LASTEXITCODE at 1 (success); force a clean exit so CI
# does not treat the run as failed.
Write-Host "Built: $Output" -ForegroundColor Green
exit 0
