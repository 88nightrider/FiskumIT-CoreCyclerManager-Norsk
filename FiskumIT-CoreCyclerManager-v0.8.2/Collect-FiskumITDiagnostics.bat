@echo off
REM Starter Collect-FiskumITDiagnostics.ps1 med administratorrettigheter
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-FiskumITDiagnostics.ps1"' -Verb RunAs"
