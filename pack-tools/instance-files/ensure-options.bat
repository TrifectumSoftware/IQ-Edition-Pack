@echo off
REM ensure-options.bat - PreLaunchCommand for PrismLauncher
REM Writes correct resourcePacks line to options.txt before Minecraft starts.
set "DIR=%~dp0"
set "OPTS=%DIR%minecraft\options.txt"
if not exist "%OPTS%" exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$o='%OPTS%';$p='[\"ChromaticStarter\",\"IQQuestTablet\",\"IQWin95Loading\",\"IQBQTheme\",\"Highresfont\",\"IQ NEI Icons\",\"IQ Menu + Pipboy\",\"Maybe Menu Music\",\"IQ ServerUtilities\"]';$c=Get-Content $o -Raw;if($c -match 'resourcePacks:'){$c=$c -replace 'resourcePacks:\[.*?\]',('resourcePacks:{0}' -f $p);[System.IO.File]::WriteAllText($o,$c,(New-Object System.Text.UTF8Encoding($false)))}"
