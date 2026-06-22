@echo off
setlocal

set "CORECYCLER_DIR=C:\FiskumIT\CoreCyclerManager\CoreCycler"

echo Stopper prosesser som kjorer fra:
echo "%CORECYCLER_DIR%"
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=(Resolve-Path '%CORECYCLER_DIR%').Path.TrimEnd('\');" ^
  "$procs=Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) };" ^
  "foreach($p in $procs){ Write-Host ('Stopper PID ' + $p.ProcessId + ' - ' + $p.Name); Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }"

echo.
echo Ferdig. Prov aa starte manageren igjen.
echo.
pause