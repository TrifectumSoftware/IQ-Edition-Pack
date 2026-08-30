#Requires -Version 5.1
<#
.SYNOPSIS
    Updates mods.bundle.json entries to the latest GitHub release of each mod.
    Mirrors GTNH DreamAssemblerXXL's rolling-release update, scaled down.

.PARAMETER BundlePath
    Path to mods.bundle.json. Defaults to ..\config\mod-director\mods.bundle.json relative to this script.

.PARAMETER DryRun
    Report what would change without writing the bundle.

.PARAMETER Exclude
    Array of fileName values to keep pinned (no update check).

.NOTES
    Set GITHUB_TOKEN env var to avoid API rate limits (57 mods = 57 calls; unauthenticated cap is 60/h).
#>
param(
    [string]$BundlePath = (Join-Path $PSScriptRoot "..\config\mod-director\mods.bundle.json"),
    [switch]$DryRun,
    [string[]]$Exclude = @()
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$headers = @{ "User-Agent" = "IQ-Edition-Bundle-Updater" }
if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

function Get-LatestGithubJar {
    param([string]$Owner, [string]$Repo)

    $api = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    try {
        $rel = Invoke-RestMethod -Uri $api -Headers $headers -UseBasicParsing -TimeoutSec 30
    } catch {
        return @{ status = "error"; detail = $_.Exception.Message }
    }

    # Main jar = .jar that is not dev/sources/api/javadoc/forgePatches/multimc
    $skipSuffixes = @("-dev.jar", "-sources.jar", "-api.jar", "-api2.jar", "-javadoc.jar", "-forgePatches.jar")
    $asset = $null
    foreach ($a in $rel.assets) {
        if (-not $a.name.EndsWith(".jar")) { continue }
        if ($a.name -match "multimc\.zip$") { continue }
        $isSkip = $false
        foreach ($suffix in $skipSuffixes) {
            if ($a.name.EndsWith($suffix)) { $isSkip = $true; break }
        }
        if ($isSkip) { continue }
        $asset = $a
        break
    }

    if (-not $asset) { return @{ status = "nojar"; tag = $rel.tag_name } }
    return @{
        status   = "ok"
        tag      = $rel.tag_name
        name     = $asset.name
        url      = $asset.browser_download_url
        prerelease = $rel.prerelease
    }
}

# ---- Main ----
if (-not (Test-Path $BundlePath)) { throw "Bundle not found: $BundlePath" }
$bundle = Get-Content $BundlePath -Raw | ConvertFrom-Json

$changes = @()
$errors = @()
$skipped = @()
$i = 0

foreach ($mod in $bundle.url) {
    $i++
    $name = $mod.fileName.Trim()

    if ($Exclude -contains $name) { $skipped += "$name (pinned)"; continue }
    if ($mod.url -notmatch "^https://github\.com/([^/]+)/([^/]+)/releases/") {
        $skipped += "$name (non-GitHub source)"; continue
    }

    $owner = $Matches[1]; $repo = $Matches[2]
    Write-Host "[$i/$($bundle.url.Count)] $name <- $owner/$repo"

    $result = Get-LatestGithubJar -Owner $owner -Repo $repo

    switch ($result.status) {
        "ok" {
            if ($result.url -ne $mod.url) {
                $changes += [pscustomobject]@{
                    fileName = $name
                    oldUrl   = $mod.url
                    newUrl   = $result.url
                    newName  = $result.name
                    newTag   = $result.tag
                }
                $mod.fileName = $result.name
                $mod.url      = $result.url
            }
        }
        default { $errors += "$name ($owner/$repo): $($result.detail)" }
    }

    Start-Sleep -Milliseconds 250   # be polite to the API
}

# ---- Report ----
Write-Host ""
Write-Host "================ UPDATE REPORT ================" -ForegroundColor Cyan
Write-Host "Checked : $($bundle.url.Count)"
Write-Host "Updated : $($changes.Count)"
Write-Host "Skipped : $($skipped.Count)"
Write-Host "Errors  : $($errors.Count)"

if ($changes.Count -gt 0) {
    Write-Host "`n--- Changes ---" -ForegroundColor Yellow
    foreach ($c in $changes) {
        Write-Host "  $($c.fileName)"
        Write-Host "    -> $($c.newName)  [$($c.newTag)]"
    }
}
if ($errors.Count -gt 0) {
    Write-Host "`n--- Errors ---" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" }
}

# ---- Changelog (markdown) ----
if ($changes.Count -gt 0) {
    $md = @()
    $md += "### Mod updates"
    $md += ""
    foreach ($c in $changes) {
        $oldRepo = if ($c.oldUrl -match "github\.com/([^/]+/[^/]+)/releases") { $Matches[1] } else { "?" }
        $md += "- **$($c.fileName)** -> **$($c.newName)** ($($c.newTag))"
    }
    $md | Set-Content (Join-Path $PSScriptRoot "CHANGES.md") -Encoding UTF8
    Write-Host "`nChangelog written to CHANGES.md"
}

# ---- Write bundle ----
if (-not $DryRun -and $changes.Count -gt 0) {
    $bundle | ConvertTo-Json -Depth 6 | Set-Content $BundlePath -Encoding UTF8
    Write-Host "Bundle written: $BundlePath" -ForegroundColor Green
} elseif ($DryRun) {
    Write-Host "Dry run - bundle NOT modified." -ForegroundColor Yellow
} else {
    Write-Host "No changes - bundle untouched."
}
