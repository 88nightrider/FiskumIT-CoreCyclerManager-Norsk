<#
Fiskum IT - Update-FiskumITCoreCyclerManager.ps1 (v0.8.7.3)

Henter siste versjon av Fiskum IT CoreCycler Manager fra GitHub og installerer den ved a
kjore Installer.bat fra den nedlastede versjonen - SAMME installasjonslogikk som en
manuell (re)installasjon (bevarer state.json/avansert-valg.json, hopper over logs,
fjerner Windows-blokkering pa de nye filene).

Kjores som en EGEN prosess (normalt startet av Manageren sin "Oppdater na"-knapp, som
lukker seg selv rett etter), slik at de kjorende Manager-filene kan oppdateres uten at
det krever a erstatte det scriptet som faktisk kjorer i det. Kan ogsa kjores helt
uavhengig/manuelt.
#>

param(
    [string]$GitHubRepo = '88nightrider/FiskumIT-CoreCyclerManager-Norsk'
)

$ErrorActionPreference = 'Stop'

# Fiskum IT: selv-elevering - Installer.bat (kjort under) krever ogsa admin, men hvis VI
# ikke allerede er elevert na, ville Installer.bat sin EGEN UAC-relansering startet en
# NY, uavhengig prosess som vi ikke kan vente pa - vi ville da rapportert "fullfort" og
# ryddet opp i nedlastingsmappen LENGE for den faktiske installasjonen var ferdig
$erAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $erAdmin) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-GitHubRepo', "`"$GitHubRepo`""
    ) -Verb RunAs
    exit 0
}

$tempZip     = $null
$tempExtract = $null

try {
    Write-Host 'Henter informasjon om siste versjon...'
    $respons = Invoke-RestMethod -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest" -Headers @{ 'User-Agent' = 'FiskumIT-CoreCyclerManager-Updater' } -TimeoutSec 15

    $zipUrl      = $respons.zipball_url
    $tempZip     = Join-Path $env:TEMP ("FiskumIT-CoreCyclerManager-Update-{0}.zip" -f ([Guid]::NewGuid()))
    $tempExtract = Join-Path $env:TEMP ("FiskumIT-CoreCyclerManager-Update-{0}" -f ([Guid]::NewGuid()))

    Write-Host ("Laster ned {0}..." -f $respons.tag_name)
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -Headers @{ 'User-Agent' = 'FiskumIT-CoreCyclerManager-Updater' } -TimeoutSec 120

    Write-Host 'Fjerner Windows-blokkering fra nedlastet fil...'
    Unblock-File -LiteralPath $tempZip -ErrorAction SilentlyContinue

    Write-Host 'Pakker ut...'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)

    # Fiskum IT: GitHub sin zipball-url legger alt under EN undermappe (f.eks.
    # "88nightrider-FiskumIT-CoreCyclerManager-Norsk-<sha>") - finn den faktiske roten
    $rotMappe = Get-ChildItem -LiteralPath $tempExtract -Directory | Select-Object -First 1

    if (-not $rotMappe) {
        throw 'Fant ikke utpakket innhold etter nedlasting.'
    }

    $installerSti = Join-Path $rotMappe.FullName 'Installer.bat'

    if (-not (Test-Path -LiteralPath $installerSti)) {
        throw "Fant ikke Installer.bat i den nedlastede versjonen ($installerSti)."
    }

    Write-Host 'Starter installasjon av den nye versjonen...'
    $installerProsess = Start-Process -FilePath $installerSti -WorkingDirectory $rotMappe.FullName -Wait -PassThru -WindowStyle Normal

    if ($installerProsess.ExitCode -ne 0) {
        throw "Installer.bat avsluttet med feilkode $($installerProsess.ExitCode)."
    }

    Write-Host 'Oppdatering fullfort. Starter Manageren pa nytt...'

    $startBatSti = 'C:\FiskumIT\CoreCyclerManager\Manager\Start-FiskumIT-CoreCyclerManager.bat'

    if (Test-Path -LiteralPath $startBatSti) {
        Start-Process -FilePath $startBatSti -WorkingDirectory (Split-Path -Parent $startBatSti)
    }
}
catch {
    Write-Host ''
    Write-Host "FEIL under oppdatering: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Du kan laste ned og installere siste versjon manuelt fra GitHub i stedet.'
    Read-Host 'Trykk Enter for a avslutte'
    exit 1
}
finally {
    if ($tempZip -and (Test-Path -LiteralPath $tempZip)) {
        Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    }

    if ($tempExtract -and (Test-Path -LiteralPath $tempExtract)) {
        Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}
