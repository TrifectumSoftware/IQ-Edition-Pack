# ensure-options.ps1
# Writes the correct resourcePacks line to options.txt before Minecraft starts.
# PrismLauncher may rewrite options.txt from instance.cfg on each launch, which
# can blank out the resource pack list. This PreLaunchCommand runs first.
param()
$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$opts = Join-Path $dir "minecraft\options.txt"
$packs = '["ChromaticStarter","IQQuestTablet","IQWin95Loading","IQBQTheme","Highresfont","IQ NEI Icons","IQ Menu + Pipboy","Maybe Menu Music","IQ ServerUtilities"]'
if (Test-Path $opts) {
    $c = Get-Content $opts -Raw -ErrorAction SilentlyContinue
    if ($c -match 'resourcePacks:') {
        $c = $c -replace 'resourcePacks:\[.*?\]', ("resourcePacks:{0}" -f $packs)
        [System.IO.File]::WriteAllText($opts, $c, [System.Text.UTF8Encoding]::new($false))
    }
}
