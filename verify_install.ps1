$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path -Path $desktop -ChildPath 'Generer diagnostikk for innsending.lnk'
if (Test-Path -LiteralPath $lnk) {
    $w = New-Object -ComObject WScript.Shell
    $s = $w.CreateShortcut($lnk)
    Write-Host "Shortcut: Generer diagnostikk for innsending.lnk"
    Write-Host "TARGET: $($s.TargetPath)"
    Write-Host "WD: $($s.WorkingDirectory)"
    Write-Host "ARGS: $($s.Arguments)"
}
else {
    Write-Host "Shortcut not found"
}

Write-Host ""
Write-Host "Installed diagnostics files:"
Get-ChildItem -LiteralPath 'C:\FiskumIT\CoreCyclerManager' -Filter 'Collect-FiskumITDiagnostics.*' | ForEach-Object { Write-Host $_.Name }
