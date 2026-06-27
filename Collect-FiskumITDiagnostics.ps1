<#
.SYNOPSIS
  Samler relevante CoreCycler/Manager-feillogger i et arkiv og sletter originale logger.

.DESCRIPTION
  Skriptet pakker loggfiler fra nåværende workspace og "Loggfiler for utvikling"-mappen til en arkivfil på skrivebordet.
  Det legger også ved en systeminformasjonsfil med operativsystem, CPU, RAM og annen diagnostisk informasjon.
  Arkivfilen bruker filtypen .diag for å gjøre det mindre umiddelbart å redigere innholdet.

.PARAMETER DestinationFolder
  Mappen der arkivet skal lagres. Standard er brukerens skrivebord.

.PARAMETER SourceFolders
  Ekstra mapper som skal inkluderes i arkivet.

.EXAMPLE
  .\Collect-FiskumITDiagnostics.ps1

.EXAMPLE
  .\Collect-FiskumITDiagnostics.ps1 -DestinationFolder "C:\Users\Tester\Desktop"
#>

param(
    [string]$DestinationFolder = [Environment]::GetFolderPath('Desktop'),
    [string[]]$SourceFolders = @()
)

function Ensure-Administrator {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$PSCommandPath")
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs
        Exit 0
    }
}

Ensure-Administrator
Set-StrictMode -Version Latest

function Find-LoggfilerForUtviklingFolder {
    # Fiskum IT (v0.8.7.12): omdopt fra "Feil" - "Loggfiler for utvikling" er en valgfri,
    # ekstra kilde - kun relevant i utviklingstreet, hvor kryss-maskin-logger legges manuelt
    # for videre analyse. Den er IKKE en del av en vanlig installasjon (der ligger scriptet
    # rett ved siden av Manager\/CoreCycler\, uten noen "Loggfiler for utvikling"-mappe i
    # nærheten) - sjekk derfor noen nivaer oppover, men det er helt greit om den ikke finnes
    # noe sted
    param(
        [string]$StartPath
    )

    $current = $StartPath

    for ($i = 0; $i -lt 4; $i++) {
        if (-not $current) {
            break
        }

        $candidate = Join-Path $current 'Loggfiler for utvikling'

        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }

        $current = Split-Path -Parent $current
    }

    return $null
}

function ConvertTo-ReadableDate {
    # Fiskum IT: Get-CimInstance (i motsetning til den gamle Get-WmiObject) konverterer som
    # regel WMI-datoer til ekte [DateTime] automatisk - kaller man da ogsaa den gamle
    # ManagementDateTimeConverter::ToDateTime() (som forventer en raa DMTF-tekststreng) paa
    # et allerede-konvertert [DateTime]-objekt, feiler det med "argument utenfor gyldig omrade".
    # Bekreftet pa ekte maskin: InstallDate/ReleaseDate kom som [DateTime], ikke streng.
    # Denne haandterer begge varianter uten aa krasje
    param(
        $Value
    )

    if ($null -eq $Value -or $Value -eq '') {
        return 'Ukjent'
    }

    if ($Value -is [DateTime]) {
        return $Value.ToString('yyyy-MM-dd HH:mm:ss')
    }

    try {
        return [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value).ToString('yyyy-MM-dd HH:mm:ss')
    }
    catch {
        return [string]$Value
    }
}

function Get-SystemSpecification {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
    $memoryModules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue | Sort-Object BankLabel
    $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('FiskumIT CoreCycler Manager Diagnostics')
    $lines.Add('======================================')
    $lines.Add("CollectionDate: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("ComputerName: $env:COMPUTERNAME")
    # Fiskum IT: ALDRI ta med brukernavn (eller passord) i denne rapporten - se ogsa
    # tilsvarende fjerning i Manager-scriptets Ensure-AutoLogonConfigured
    $lines.Add("PowerShellVersion: $($PSVersionTable.PSVersion)")
    $lines.Add('')

    if ($os) {
        $lines.Add('Operating System:')
        $lines.Add("  Caption: $($os.Caption)")
        $lines.Add("  Version: $($os.Version)")
        $lines.Add("  BuildNumber: $($os.BuildNumber)")
        $lines.Add("  Architecture: $($os.OSArchitecture)")
        $lines.Add("  InstallDate: $(ConvertTo-ReadableDate -Value $os.InstallDate)")
        $lines.Add('')
    }

    if ($cpu) {
        $lines.Add('Processor:')
        $lines.Add("  Name: $($cpu.Name)")
        $lines.Add("  Manufacturer: $($cpu.Manufacturer)")
        $lines.Add("  MaxClockSpeedMHz: $($cpu.MaxClockSpeed)")
        $lines.Add("  NumberOfCores: $($cpu.NumberOfCores)")
        $lines.Add("  NumberOfLogicalProcessors: $($cpu.NumberOfLogicalProcessors)")
        $lines.Add("  ProcessorId: $($cpu.ProcessorId)")
        $lines.Add('')
    }

    if ($bios) {
        $lines.Add('BIOS/UEFI:')
        $lines.Add("  Manufacturer: $($bios.Manufacturer)")
        $lines.Add("  Version: $($bios.SMBIOSBIOSVersion)")
        $lines.Add("  ReleaseDate: $(ConvertTo-ReadableDate -Value $bios.ReleaseDate)")
        $lines.Add('')
    }

    if ($memoryModules) {
        $lines.Add('Memory Modules:')
        foreach ($mod in $memoryModules) {
            $capacityGB = [math]::Round(($mod.Capacity / 1GB), 2)
            $lines.Add("  BankLabel: $($mod.BankLabel)  CapacityGB: $capacityGB  SpeedMHz: $($mod.Speed)  Manufacturer: $($mod.Manufacturer)")
        }
        $lines.Add('')
        $totalRam = ($memoryModules | Measure-Object -Property Capacity -Sum).Sum
        if ($totalRam) {
            $lines.Add("Total Physical RAM (GB): $([math]::Round($totalRam / 1GB, 2))")
            $lines.Add('')
        }
    }

    if ($gpus) {
        $lines.Add('GPU(s):')
        foreach ($gpu in $gpus) {
            $adapterRamGB = if ($gpu.AdapterRAM) { [math]::Round($gpu.AdapterRAM / 1GB, 2) } else { 'Unknown' }
            $lines.Add("  Name: $($gpu.Name)  RAM(GB): $adapterRamGB  DriverVersion: $($gpu.DriverVersion)")
        }
        $lines.Add('')
    }

    if ($disks) {
        $lines.Add('Disk Drives:')
        foreach ($disk in $disks) {
            $freeGB = if ($disk.FreeSpace) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { 'Unknown' }
            $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { 'Unknown' }
            $lines.Add("  DeviceID: $($disk.DeviceID)  VolumeName: $($disk.VolumeName)  FreeGB: $freeGB  SizeGB: $sizeGB")
        }
        $lines.Add('')
    }

    # Fiskum IT (v0.8.2): KUN status (finnes/aktivert) - ALDRI passord eller andre detaljer.
    # Gjor en fremtidig "hvorfor gjenopptok ikke testen automatisk"-sak undersokbar uten
    # a sporre brukeren om a sjekke dette manuelt - se Ensure-AutoLogonConfigured/
    # Add-ManagerAutoStartTask i Manager-scriptet
    $lines.Add('Automatisk gjenoppretting (v0.8.2+):')

    try {
        $task = Get-ScheduledTask -TaskName 'FiskumIT CoreCycler Manager AutoStart' -ErrorAction SilentlyContinue
        $lines.Add("  AutoStart-Scheduled-Task finnes: $($null -ne $task)")
    }
    catch {
        $lines.Add('  AutoStart-Scheduled-Task finnes: Ukjent (kunne ikke sjekke)')
    }

    try {
        $autoLogon = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
        $autoLogonPaa = $false

        if ($autoLogon -and (Get-Member -InputObject $autoLogon -Name 'AutoAdminLogon' -ErrorAction SilentlyContinue)) {
            $autoLogonPaa = ($autoLogon.AutoAdminLogon -eq '1')
        }

        $lines.Add("  Windows-autologon aktivert: $autoLogonPaa")
    }
    catch {
        $lines.Add('  Windows-autologon aktivert: Ukjent (kunne ikke sjekke)')
    }

    $lines.Add('')

    return $lines
}

function Get-ArchiveVersion {
    # Fiskum IT: leser versjonsnummeret direkte fra $ManagerVersion-variabelen inni selve
    # Manager .ps1-filens kildetekst (regex, IKKE ved a dot-source/kjore filen). Mappe-/
    # filnavn er na bevisst versjonsuavhengige (se README - versjonering skjer via git-tags/
    # GitHub Releases) - det gamle "les fra FiskumIT-CoreCyclerManager-vX.X.ps1-filnavnet
    # eller -mappenavnet"-oppsettet er derfor ikke lenger en gyldig kilde
    param(
        [string]$ScriptRoot
    )

    $managerScript = Join-Path $ScriptRoot 'Manager\FiskumIT-CoreCyclerManager.ps1'

    if (Test-Path -LiteralPath $managerScript) {
        $innhold = Get-Content -LiteralPath $managerScript -Raw -ErrorAction SilentlyContinue

        if ($innhold -match "\`$ManagerVersion\s*=\s*'([\d.]+)'") {
            return "v$($Matches[1])"
        }
    }

    return 'unknown-version'
}

function Get-LogFilesFromFolders {
    param(
        [string[]]$Folders
    )

    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    foreach ($folder in $Folders) {
        if (-not $folder) {
            continue
        }

        if (-not (Test-Path -LiteralPath $folder)) {
            continue
        }

        $items = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.log', '.txt' }

        foreach ($item in $items) {
            $files.Add($item)
        }
    }

    return $files
}

function New-RelativePath {
    param(
        [string]$FullPath,
        [string]$BasePath
    )

    $full = [System.IO.Path]::GetFullPath($FullPath)
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $full.Substring($base.Length).TrimStart('\', '/')
        return $relative
    }

    return [System.IO.Path]::GetFileName($FullPath)
}

# Fiskum IT: Manager\logs og CoreCycler\logs ligger ALLTID som sibling-mapper til dette
# scriptet selv - bade i kildetreet og i en faktisk installasjon (se Installer.bat, som
# kopierer dette scriptet til roten av installasjonen, ved siden av Manager\/CoreCycler\).
# Det er derfor ingen grunn til aa lete etter dem via en mappe-navn-mal som bare finnes i
# kildetreet - det var roten til at INGEN logger ble funnet pa en faktisk installasjon
$workspaceRoot = $PSScriptRoot
$defaultSources = [System.Collections.Generic.List[string]]::new()
$defaultSources.Add((Join-Path $workspaceRoot 'Manager\logs'))
$defaultSources.Add((Join-Path $workspaceRoot 'CoreCycler\logs'))

$loggfilerForUtviklingFolder = Find-LoggfilerForUtviklingFolder -StartPath $workspaceRoot
if ($loggfilerForUtviklingFolder) {
    $defaultSources.Add($loggfilerForUtviklingFolder)
}

$sourceFolders = @()
$sourceFolders += $defaultSources | Where-Object { $_ }
$sourceFolders += $SourceFolders | Where-Object { $_ }
$sourceFolders = $sourceFolders | Sort-Object -Unique

if (-not $sourceFolders -or $sourceFolders.Count -eq 0) {
    Write-Error 'Ingen kilde-mapper er definert. Kontroller at scriptet ligger i riktig workspace eller bruk -SourceFolders.'
    exit 1
}

# Fiskum IT: PowerShell "ruller ut" en returnert [List[T]] til en vanlig fast-storrelse
# array nar den fanges opp slik - $logFiles.Add() under ville da feile med "samlingen
# hadde en fast storrelse" (sett i praksis, se Feil-mappen). Tvinger den derfor tilbake
# til en resizable liste her
$logFiles = [System.Collections.Generic.List[object]]@(Get-LogFilesFromFolders -Folders $sourceFolders)

# Fiskum IT: state.json (Manager\state.json) og skrivebordsrapporten ligger UTENFOR
# Manager\logs/CoreCycler\logs, men er ofte akkurat det som trengs for aa diagnostisere en
# feilmelding som "kunne ikke skrive snapshot til skrivebordslogg" - uten state.json er det
# umulig aa se hvilken faktisk form/verdi et felt hadde da feilen skjedde. Lagt til etter at
# dette manglet under feilsoking av en reell sak (se Feil-mappen, 2026-06-21)
$ekstraFiler = [System.Collections.Generic.List[string]]::new()
$ekstraFiler.Add((Join-Path $workspaceRoot 'Manager\state.json'))
$ekstraFiler.Add((Join-Path $workspaceRoot 'Manager\config\avansert-valg.json'))
$ekstraFiler.Add((Join-Path ([Environment]::GetFolderPath('Desktop')) 'FiskumIT-CoreCycler-Logg.txt'))

foreach ($ekstraFil in $ekstraFiler) {
    if (Test-Path -LiteralPath $ekstraFil -PathType Leaf) {
        $logFiles.Add([System.IO.FileInfo]$ekstraFil)
    }
}

if ($logFiles.Count -eq 0) {
    Write-Host 'Ingen loggfiler funnet i de angitte mappene. Ingen arkiv opprettes.'
    exit 0
}

$version = Get-ArchiveVersion -ScriptRoot $workspaceRoot
$computerName = $env:COMPUTERNAME
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$archiveFileName = "FiskumIT-CoreCyclerManager-$version-$computerName-$timestamp.diag"
# Fiskum IT: IKKE bruk navnet "$destinationFolder" her - det er samme variabel (PowerShell
# skiller ikke stort/smaa bokstaver) som den typede parameteren [string]$DestinationFolder,
# og en tildeling tvinger da resultatet tilbake til [string] via ToString() FOR vi faar
# tak i .ProviderPath. Det gjorde at denne grenen alltid krasjet naar maalmappen
# allerede fantes (f.eks. Skrivebordet, som jo alltid finnes) - bekreftet ved direkte testing
$resolvedDestination = Resolve-Path -LiteralPath $DestinationFolder -ErrorAction SilentlyContinue
if (-not $resolvedDestination) {
    Write-Host "Mappen $DestinationFolder finnes ikke. Prøver å opprette den..."
    $destinationFolder = New-Item -ItemType Directory -Path $DestinationFolder -Force | Select-Object -ExpandProperty FullName
}
else {
    $destinationFolder = $resolvedDestination.ProviderPath
}

$archivePath = Join-Path $destinationFolder $archiveFileName
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "FiskumITDiagnostics_$timestamp"

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    foreach ($file in $logFiles) {
        $relativePath = New-RelativePath -FullPath $file.FullName -BasePath $workspaceRoot
        $targetPath = Join-Path $tempRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
    }

    $systemInfoPath = Join-Path $tempRoot 'system-info.txt'
    Get-SystemSpecification | Set-Content -LiteralPath $systemInfoPath -Encoding UTF8

    $manifestPath = Join-Path $tempRoot 'archive-manifest.txt'
    $manifestLines = [System.Collections.Generic.List[string]]::new()
    $manifestLines.Add('FiskumIT CoreCycler Manager Diagnostics Archive')
    $manifestLines.Add("ArchiveCreated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $manifestLines.Add("ArchiveVersion: $version")
    $manifestLines.Add("ComputerName: $computerName")
    $manifestLines.Add('')
    $manifestLines.Add('Included files:')
    foreach ($file in $logFiles | Sort-Object FullName) {
        $manifestLines.Add("  $($file.FullName)")
    }
    $manifestLines.Add('')
    $manifestLines.Add('Source folders:')
    foreach ($folder in $sourceFolders) {
        $manifestLines.Add("  $folder")
    }
    $manifestLines.Add('')
    $manifestLines.Add('Note: Filtypen .diag er en ZIP-fil med diagnoseinnhold.')
    $manifestLines | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    # Fiskum IT: Compress-Archive godtar KUN ".zip" som filendelse - den feiler haardt paa
    # ".diag" selv om innholdet er en gyldig ZIP-fil. Komprimer derfor til en ekte .zip
    # forst, og gi den det tiltenkte ".diag"-navnet etterpaa med en omdoping
    $tempZipPath = [System.IO.Path]::ChangeExtension($archivePath, '.zip')

    Push-Location -LiteralPath $tempRoot
    Compress-Archive -Path * -DestinationPath $tempZipPath -Force
    Pop-Location

    Move-Item -LiteralPath $tempZipPath -Destination $archivePath -Force

    Write-Host "Diagnostikkarkiv opprettet: $archivePath"

    foreach ($file in $logFiles) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Kunne ikke slette fil: $($file.FullName) - $($_.Exception.Message)"
        }
    }

    Write-Host 'Opprydding fullført. Originale loggfiler er slettet.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
