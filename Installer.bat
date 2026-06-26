@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Fiskum IT CoreCycler Manager - Installer

REM ============================================================
REM Fiskum IT - Installer CoreCycler Manager
REM   - Dobbeltklikk for aa installere.
REM   - Skriptet ber AUTOMATISK om administratorrettigheter via UAC.
REM     Du skal IKKE maatte hoyreklikke og velge "Kjor som administrator".
REM ============================================================

set "LOG_FILE=%TEMP%\FiskumIT-CoreCyclerManager-Installer.log"

echo ============================================================ > "%LOG_FILE%"
echo Fiskum IT CoreCycler Manager - Installer >> "%LOG_FILE%"
echo Startet: %date% %time% >> "%LOG_FILE%"
echo BAT: %~f0 >> "%LOG_FILE%"
echo Args: %* >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

echo.
echo Fiskum IT CoreCycler Manager - Installer
echo Logg: "%LOG_FILE%"
echo.

REM ------------------------------------------------------------
REM Auto-elevering: hvis vi ikke er admin -> start oss selv paa nytt
REM forhoyet via PowerShell Start-Process -Verb RunAs (utloser UAC).
REM ------------------------------------------------------------
net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" goto NEEDS_ELEVATION
goto HAS_ELEVATION

:NEEDS_ELEVATION
if /I "%~1"=="ELEVATED" (
    echo FEIL: Elevering feilet. Du maa godkjenne UAC-prompten.
    echo FEIL: Elevering feilet etter ELEVATED-flagg. >> "%LOG_FILE%"
    pause
    exit /b 1
)
echo Ber om administratorrettigheter (UAC)...
echo Ber om administratorrettigheter (UAC)... >> "%LOG_FILE%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList 'ELEVATED' -WorkingDirectory '%~dp0' -Verb RunAs"
if not "%ERRORLEVEL%"=="0" (
    echo.
    echo Kunne ikke starte UAC-prompten. Hoyreklikk filen og velg
    echo "Kjor som administrator" som fallback.
    pause
    exit /b 1
)
exit /b 0

:HAS_ELEVATION
pushd "%~dp0"
echo Kjorer med administratorrettigheter. >> "%LOG_FILE%"
echo Arbeidsmappe: %CD% >> "%LOG_FILE%"

REM ------------------------------------------------------------
REM Stier
REM ------------------------------------------------------------
set "SOURCE_ROOT=%CD%"
set "SOURCE_MANAGER=%SOURCE_ROOT%\Manager"
set "SOURCE_CORECYCLER=%SOURCE_ROOT%\CoreCycler"

set "TARGET_ROOT=C:\FiskumIT\CoreCyclerManager"
set "TARGET_MANAGER=%TARGET_ROOT%\Manager"
set "TARGET_CORECYCLER=%TARGET_ROOT%\CoreCycler"

set "MANAGER_PS1_NAME=FiskumIT-CoreCyclerManager.ps1"
set "START_BAT_NAME=Start-FiskumIT-CoreCyclerManager.bat"
set "DIAG_PS1_NAME=Collect-FiskumITDiagnostics.ps1"
set "DIAG_BAT_NAME=Collect-FiskumITDiagnostics.bat"
set "UPDATE_PS1_NAME=Update-FiskumITCoreCyclerManager.ps1"
set "ICON_NAME=FiskumIT-Logo.ico"

set "TARGET_PS1=%TARGET_MANAGER%\%MANAGER_PS1_NAME%"
set "START_BAT=%TARGET_MANAGER%\%START_BAT_NAME%"
set "TARGET_DIAG_PS1=%TARGET_ROOT%\%DIAG_PS1_NAME%"
set "TARGET_DIAG_BAT=%TARGET_ROOT%\%DIAG_BAT_NAME%"
set "TARGET_UPDATE_PS1=%TARGET_ROOT%\%UPDATE_PS1_NAME%"
set "TARGET_ICON=%TARGET_MANAGER%\%ICON_NAME%"

set "SHORTCUT_NAME=Fiskum IT CoreCycler Manager.lnk"
set "SHORTCUT_PS1=%TEMP%\FiskumIT-CoreCyclerManager-Shortcut.ps1"
set "DIAG_SHORTCUT_NAME=Generer diagnostikk for innsending.lnk"
set "DIAG_SHORTCUT_PS1=%TEMP%\FiskumIT-CoreCyclerManager-DiagnosticsShortcut.ps1"

REM ------------------------------------------------------------
REM Valider kilde
REM ------------------------------------------------------------
if not exist "%SOURCE_MANAGER%\%MANAGER_PS1_NAME%" (
    echo FEIL: Fant ikke "%SOURCE_MANAGER%\%MANAGER_PS1_NAME%"
    echo FEIL: Fant ikke manager-PS1 >> "%LOG_FILE%"
    pause & exit /b 1
)
if not exist "%SOURCE_CORECYCLER%\script-corecycler.ps1" (
    echo FEIL: Fant ikke "%SOURCE_CORECYCLER%\script-corecycler.ps1"
    echo CoreCycler-filene maa ligge i mappen "CoreCycler" ved siden av Installer.bat
    echo FEIL: Fant ikke CoreCycler-scriptet >> "%LOG_FILE%"
    pause & exit /b 1
)
REM --- Robust diagnostics source lookup ---
set "DIAG_SOURCE_PS1=%SOURCE_ROOT%\%DIAG_PS1_NAME%"
set "DIAG_SOURCE_BAT=%SOURCE_ROOT%\%DIAG_BAT_NAME%"

if not exist "%DIAG_SOURCE_PS1%" (
    if exist "%~dp0%DIAG_PS1_NAME%" (
        set "DIAG_SOURCE_PS1=%~dp0%DIAG_PS1_NAME%"
    ) else if exist "%~dp0..\%DIAG_PS1_NAME%" (
        set "DIAG_SOURCE_PS1=%~dp0..\%DIAG_PS1_NAME%"
    )
)

if not exist "%DIAG_SOURCE_BAT%" (
    if exist "%~dp0%DIAG_BAT_NAME%" (
        set "DIAG_SOURCE_BAT=%~dp0%DIAG_BAT_NAME%"
    ) else if exist "%~dp0..\%DIAG_BAT_NAME%" (
        set "DIAG_SOURCE_BAT=%~dp0..\%DIAG_BAT_NAME%"
    )
)

if not exist "%DIAG_SOURCE_PS1%" (
    echo FEIL: Fant ikke diagnostikk-PS1 i forventede lokasjoner: "%SOURCE_ROOT%" eller installasjonsmappe.
    echo FEIL: Manglende diagnostikk-PS1 >> "%LOG_FILE%"
    pause & exit /b 1
)
if not exist "%DIAG_SOURCE_BAT%" (
    echo FEIL: Fant ikke diagnostikk-BAT i forventede lokasjoner: "%SOURCE_ROOT%" eller installasjonsmappe.
    echo FEIL: Manglende diagnostikk-BAT >> "%LOG_FILE%"
    pause & exit /b 1
)

REM --- Robust oppdateringsscript source lookup (valgfritt - eldre nedlastinger har den
REM     ikke ennaa, og en manglende oppdaterer skal ikke stoppe selve installasjonen) ---
set "UPDATE_SOURCE_PS1=%SOURCE_ROOT%\%UPDATE_PS1_NAME%"

if not exist "%UPDATE_SOURCE_PS1%" (
    if exist "%~dp0%UPDATE_PS1_NAME%" (
        set "UPDATE_SOURCE_PS1=%~dp0%UPDATE_PS1_NAME%"
    ) else if exist "%~dp0..\%UPDATE_PS1_NAME%" (
        set "UPDATE_SOURCE_PS1=%~dp0..\%UPDATE_PS1_NAME%"
    )
)

REM ------------------------------------------------------------
REM Kopier
REM ------------------------------------------------------------
if not exist "%TARGET_ROOT%" mkdir "%TARGET_ROOT%"
if not exist "%TARGET_MANAGER%" mkdir "%TARGET_MANAGER%"
if not exist "%TARGET_CORECYCLER%" mkdir "%TARGET_CORECYCLER%"

echo Kopierer Manager...
REM Fiskum IT: state.json/avansert-valg.json er BRUKERDATA (lopende testfremdrift/valg pa
REM DENNE maskinen), ikke kildefiler - skal IKKE overskrives av en (re)installasjon, ellers
REM forsvinner ekte testfremdrift hvis denne kjores pa nytt for a oppdatere en eksisterende
REM installasjon. Manageren lager selv en frisk state.json ved forste oppstart hvis den
REM mangler (se Get-State/New-DefaultState), sa det er trygt a utelate den helt her.
REM
REM "logs"-mappene utelates ogsa helt (/XD): disse inneholder loggfiler fra DENNE
REM kildemaskinen (f.eks. en utviklers egne testkjoringer) - hvis disse kopieres med over
REM blandes de sammen med malmaskinens egne logger i samme fil (samme dato = samme filnavn),
REM noe som gjorde en reell feilsokingssak forvirrende (Manager_2026-06-21.log inneholdt
REM bade utviklingsmaskinens OG WANJA-GAMER sine oppforinger i samme fil). Begge mappene
REM lages automatisk av Manageren/motoren selv ved forste skriving uansett.
robocopy "%SOURCE_MANAGER%" "%TARGET_MANAGER%" /E /R:2 /W:1 /XF state.json avansert-valg.json /XD logs >> "%LOG_FILE%" 2>&1
if %ERRORLEVEL% GEQ 8 ( echo FEIL: Manager-kopiering feilet. & pause & exit /b 1 )

echo Kopierer CoreCycler...
robocopy "%SOURCE_CORECYCLER%" "%TARGET_CORECYCLER%" /E /R:2 /W:1 /XD logs >> "%LOG_FILE%" 2>&1
if %ERRORLEVEL% GEQ 8 ( echo FEIL: CoreCycler-kopiering feilet. & pause & exit /b 1 )

echo Kopierer diagnostikkverktoy...
copy /Y "%DIAG_SOURCE_PS1%" "%TARGET_ROOT%\" >> "%LOG_FILE%" 2>&1
if not exist "%TARGET_DIAG_PS1%" ( echo FEIL: Kopiering av diagnostikk-PS1 feilet. & pause & exit /b 1 )
copy /Y "%DIAG_SOURCE_BAT%" "%TARGET_ROOT%\" >> "%LOG_FILE%" 2>&1
if not exist "%TARGET_DIAG_BAT%" ( echo FEIL: Kopiering av diagnostikk-BAT feilet. & pause & exit /b 1 )

if exist "%UPDATE_SOURCE_PS1%" (
    echo Kopierer oppdateringsverktoy...
    copy /Y "%UPDATE_SOURCE_PS1%" "%TARGET_ROOT%\" >> "%LOG_FILE%" 2>&1
)

REM ------------------------------------------------------------
REM Fjern Windows-blokkering (Mark of the Web / Zone.Identifier)
REM Fiskum IT (v0.8.7.2): filer som er lastet ned fra GitHub (zip) far et
REM "denne filen kom fra internett"-merke (samme merke som fjernes ved a
REM huke av "Fjern blokkering" under Egenskaper). Dette kan utlose ekstra
REM SmartScreen-/sikkerhetsbegrensninger pa .ps1/.bat/.exe/.dll-filer -
REM fjerner det derfor automatisk fra HELE installasjonsmappen her
REM ------------------------------------------------------------
echo Fjerner Windows-blokkering (Mark of the Web) fra installerte filer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%TARGET_ROOT%' -Recurse -File | Unblock-File" >> "%LOG_FILE%" 2>&1
if %ERRORLEVEL%==0 (
    echo Blokkering fjernet.
) else (
    echo ADVARSEL: Kunne ikke fjerne blokkering automatisk - se loggen for detaljer.
)

REM ------------------------------------------------------------
REM Skrivebordssnarvei
REM ------------------------------------------------------------
> "%SHORTCUT_PS1%" echo $Desktop = [Environment]::GetFolderPath('Desktop')
>> "%SHORTCUT_PS1%" echo $ShortcutPath = Join-Path $Desktop '%SHORTCUT_NAME%'
>> "%SHORTCUT_PS1%" echo $WScript = New-Object -ComObject WScript.Shell
>> "%SHORTCUT_PS1%" echo $Shortcut = $WScript.CreateShortcut($ShortcutPath)
>> "%SHORTCUT_PS1%" echo $Shortcut.TargetPath = '%START_BAT%'
>> "%SHORTCUT_PS1%" echo $Shortcut.WorkingDirectory = '%TARGET_MANAGER%'
>> "%SHORTCUT_PS1%" echo if (Test-Path -LiteralPath '%TARGET_ICON%') { $Shortcut.IconLocation = '%TARGET_ICON%,0' } else { $Shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0" }
>> "%SHORTCUT_PS1%" echo $Shortcut.Description = 'Start Fiskum IT CoreCycler Manager'
>> "%SHORTCUT_PS1%" echo $Shortcut.Save()
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SHORTCUT_PS1%" >> "%LOG_FILE%" 2>&1

REM ------------------------------------------------------------
REM Skrivebordssnarvei for diagnostikk
REM ------------------------------------------------------------
> "%DIAG_SHORTCUT_PS1%" echo $Desktop = [Environment]::GetFolderPath('Desktop')
>> "%DIAG_SHORTCUT_PS1%" echo $ShortcutPath = Join-Path $Desktop '%DIAG_SHORTCUT_NAME%'
>> "%DIAG_SHORTCUT_PS1%" echo $WScript = New-Object -ComObject WScript.Shell
>> "%DIAG_SHORTCUT_PS1%" echo $Shortcut = $WScript.CreateShortcut($ShortcutPath)
>> "%DIAG_SHORTCUT_PS1%" echo $Shortcut.TargetPath = '%TARGET_DIAG_BAT%'
>> "%DIAG_SHORTCUT_PS1%" echo $Shortcut.WorkingDirectory = '%TARGET_ROOT%'
>> "%DIAG_SHORTCUT_PS1%" echo if (Test-Path -LiteralPath '%TARGET_ICON%') { $Shortcut.IconLocation = '%TARGET_ICON%,0' } else { $Shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0" }
>> "%DIAG_SHORTCUT_PS1%" echo $Shortcut.Description = 'Generer diagnostikk for innsending'
>> "%DIAG_SHORTCUT_PS1%" echo $Shortcut.Save()
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DIAG_SHORTCUT_PS1%" >> "%LOG_FILE%" 2>&1

echo.
echo Ferdig.
echo Manager:    "%TARGET_MANAGER%"
echo CoreCycler: "%TARGET_CORECYCLER%"
echo Snarvei:    Skrivebord -^> %SHORTCUT_NAME%
echo Diagnostikk: Skrivebord -^> %DIAG_SHORTCUT_NAME%
echo Logg:       "%LOG_FILE%"
echo.
pause
exit /b 0
