@echo off
setlocal EnableExtensions

REM ------------------------------------------------------------
REM Fiskum IT - Start CoreCycler Manager
REM ------------------------------------------------------------

set "SCRIPT_DIR=%~dp0"
set "MANAGER_PS1=%SCRIPT_DIR%FiskumIT-CoreCyclerManager.ps1"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "START_LOG=%LOG_DIR%\StartManager.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo ------------------------------------------------------------ >> "%START_LOG%"
echo Startet: %date% %time% >> "%START_LOG%"
echo MANAGER_PS1=%MANAGER_PS1% >> "%START_LOG%"

if not exist "%MANAGER_PS1%" (
    echo FEIL: Fant ikke manager-scriptet. >> "%START_LOG%"
    echo Fant ikke manager-scriptet:
    echo "%MANAGER_PS1%"
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MANAGER_PS1%" >> "%START_LOG%" 2>&1

set "ERR=%ERRORLEVEL%"
echo PowerShell avsluttet med kode: %ERR% >> "%START_LOG%"

if not "%ERR%"=="0" (
    echo.
    echo Fiskum IT CoreCycler Manager avsluttet med feil.
    echo Feilkode: %ERR%
    echo.
    echo Se logg:
    echo "%START_LOG%"
    echo.
    pause
)

exit /b %ERR%