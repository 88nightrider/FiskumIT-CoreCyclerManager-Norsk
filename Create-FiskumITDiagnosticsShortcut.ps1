# Create-FiskumITDiagnosticsShortcut.ps1
# Lager en snarvei på skrivebordet for diagnostikkarkivet.

Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot 'Collect-FiskumITDiagnostics.bat'
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Generer diagnostikk for innsending.lnk'

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $scriptPath
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 1
$shortcut.Description = 'Generer diagnostikkarkiv for CoreCycler Manager-feilrapporter'
$shortcut.Save()

Write-Host "Snarvei opprettet: $shortcutPath"