<#
    Fiskum IT CoreCycler Manager
    Norsk GUI og automatisering rundt sp00n sin CoreCycler (https://github.com/sp00n/corecycler)
    for Curve Optimizer-/spenningsundervolting (AMD/Intel) og CPU-stabilitetstesting.

    Repo:    https://github.com/88nightrider/FiskumIT-CoreCyclerManager-Norsk
    Lisens:  CC BY-NC-SA 4.0 (se LICENSE i repo-roten)
#>
#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Fiskum IT: for Get-CpuInstruksjonssett - lar Manageren sjekke hvilke SIMD-instruksjonssett
# (AVX/AVX2/AVX512) DENNE CPU-en faktisk stotter, slik at testvalg kan tilpasses alle
# x86-64-CPU'er (AMD og Intel, gamle og nye) i stedet for a anta AMD Ryzen 3000/5000
Add-Type -Namespace FiskumIT -Name CpuFeature -MemberDefinition '
    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    public static extern bool IsProcessorFeaturePresent(uint feature);
'

# Fiskum IT: for Set-LiveLogView - WM_SETREDRAW er den etablerte WinForms-teknikken for a
# undertrykke selve MALINGEN (ikke layout - det er SuspendLayout/ResumeLayout, en annen
# ting) av en kontroll midt i en Clear()+ombygging, slik at brukeren bare ser SLUTTRESULTATET
# i stedet for et synlig "tomt -> fylles opp igjen"-blink hver gang innholdet endres
Add-Type -Namespace FiskumIT -Name NoFlicker -MemberDefinition '
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int msg, bool wParam, int lParam);
'

# Fiskum IT (v0.8.2): for Set-LsaPrivateData/Ensure-AutoLogonConfigured - lagrer Windows
# autologon-passordet som et LSA "secret" (samme teknikk som Microsofts eget Sysinternals
# "Autologon"-verktoy bruker), IKKE som klartekst i HKLM\...\Winlogon\DefaultPassword.
# Et LSA-secret krever SYSTEM-niva tilgang a lese ut igjen, ikke bare lokal admin som
# leser en registerverdi direkte - vesentlig sikrere for samme funksjonalitet
Add-Type -Namespace FiskumIT -Name LsaSecrets -MemberDefinition '
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct LSA_UNICODE_STRING {
        public ushort Length;
        public ushort MaximumLength;
        public System.IntPtr Buffer;
    }

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct LSA_OBJECT_ATTRIBUTES {
        public int Length;
        public System.IntPtr RootDirectory;
        public System.IntPtr ObjectName;
        public uint Attributes;
        public System.IntPtr SecurityDescriptor;
        public System.IntPtr SecurityQualityOfService;
    }

    [System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
    public static extern uint LsaOpenPolicy(
        ref LSA_UNICODE_STRING SystemName,
        ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
        uint DesiredAccess,
        out System.IntPtr PolicyHandle);

    [System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
    public static extern uint LsaStorePrivateData(
        System.IntPtr PolicyHandle,
        ref LSA_UNICODE_STRING KeyName,
        System.IntPtr PrivateData);

    [System.Runtime.InteropServices.DllImport("advapi32.dll")]
    public static extern uint LsaClose(System.IntPtr ObjectHandle);

    [System.Runtime.InteropServices.DllImport("advapi32.dll")]
    public static extern int LsaNtStatusToWinError(uint Status);
'

# Fiskum IT: ma initialiseres her, IKKE bare lazily inni Get-CpuInstruksjonssett - under
# Set-StrictMode -Version Latest (over) kaster selve LESINGEN av en aldri-satt
# Script-scope-variabel ("cannot be retrieved because it has not been set"), ikke bare
# det a bruke en ikke-eksisterende egenskap (se ogsa kommentaren i Get-StabilitetsPlan
# om samme StrictMode-fallgruve for JSON-objekt-egenskaper)
$Script:CpuInstruksjonssettCache = $null
$Script:UndervoltStotteCache = $null
# Fiskum IT: forrige innhold i "Siste CoreCycler-logg" - se Set-LiveLogView. Lar oss hoppe
# over en hel Clear()+ombygging (og dermed flimringen den forarsaker) pa tick-er der
# INGENTING nytt faktisk har skjedd i loggen, som er de fleste - CoreCycler logger ikke
# nodvendigvis en ny konsoll-hendelse hver gang UI-timeren (hvert 1,5 sekund) tikker
$Script:SisteLiveLogInnhold = $null
# Fiskum IT (v0.8.2): se Write-SystemResourceLogIfDue - tidsstempel for forrige
# ressursbruk-loggoppforing, slik at vi ikke logger dette hvert tick
$Script:SisteRessursLoggTid = $null
# Fiskum IT (v0.8.2): se Check-PendingAutoResume/Invoke-AutoRestartIfEnabled - satt
# nar Manageren oppdager at den nettopp er startet etter en auto-utlost restart, men
# ventetiden ($State.restartWaitMinutes) ikke er over ennaa. Sjekkes pa nytt i timeren
$Script:PendingAutoResumeAfterStartup = $false
$Script:PendingAutoResumeNotBefore = $null
# Fiskum IT (v0.8.2): se Show-AutoRestartCountdown - mutert av dens egen Timer.Add_Tick
$Script:AutoRestartCountdownSekunder = $null

trap {
    try {
        $fallbackLogDir = Join-Path (Split-Path -Parent $PSCommandPath) 'logs'

        if (-not (Test-Path -LiteralPath $fallbackLogDir)) {
            New-Item -ItemType Directory -Path $fallbackLogDir -Force | Out-Null
        }

        $fallbackLog = Join-Path $fallbackLogDir 'Manager_CRASH.log'

        Add-Content -LiteralPath $fallbackLog -Encoding UTF8 -Value '============================================================'
        Add-Content -LiteralPath $fallbackLog -Encoding UTF8 -Value ("Tidspunkt: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        Add-Content -LiteralPath $fallbackLog -Encoding UTF8 -Value ("Feil: {0}" -f $_.Exception.Message)
        Add-Content -LiteralPath $fallbackLog -Encoding UTF8 -Value ("ScriptStackTrace: {0}" -f $_.ScriptStackTrace)
        Add-Content -LiteralPath $fallbackLog -Encoding UTF8 -Value '============================================================'

        [System.Windows.Forms.MessageBox]::Show(
            "Manageren krasjet:`n`n$($_.Exception.Message)`n`nSe logg:`n$fallbackLog",
            'Fiskum IT CoreCycler Manager - Feil',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
    }

    break
}

function Test-ErAdministrator {
    $identitet = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identitet)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-PaaNyttSomAdministrator {
    if (-not (Test-ErAdministrator)) {
        $psArgs = @(
            '-NoProfile',
            '-WindowStyle',
            'Hidden',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            ('"{0}"' -f $PSCommandPath)
        )

        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($psArgs -join ' ')
        exit
    }
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $badFile = "$Path.bad_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

        try {
            Copy-Item -LiteralPath $Path -Destination $badFile -Force
        }
        catch {
        }

        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $Object
    )

    $tmp = "$Path.tmp"

    $Object |
        ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath $tmp -Encoding UTF8

    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-NowIso {
    return (Get-Date).ToString('o')
}

function Get-TimeStamp {
    return (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
}

$ScriptDir        = Split-Path -Parent $PSCommandPath
$RootDir          = Split-Path -Parent $ScriptDir
$CoreCyclerDir    = Join-Path $RootDir 'CoreCycler'
$ManagerDir       = $ScriptDir
$ManagerLogDir    = Join-Path $ManagerDir 'logs'
$ReportDir        = Join-Path $ManagerDir 'reports'
$ConfigDir        = Join-Path $ManagerDir 'config'
$BackupDir        = Join-Path $ManagerDir 'backup'
$StateFile        = Join-Path $ManagerDir 'state.json'
$PlanFile         = Join-Path $ManagerDir 'testplan.json'
$DesktopLog       = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FiskumIT-CoreCycler-Logg.txt'
$CoreCyclerScript = Join-Path $CoreCyclerDir 'script-corecycler.ps1'
$CoreCyclerConfig = Join-Path $CoreCyclerDir 'config.ini'
$CoreCyclerLogDir = Join-Path $CoreCyclerDir 'logs'
$StartBatPath     = Join-Path $ManagerDir 'Start-FiskumIT-CoreCyclerManager.bat'

# Fiskum IT (v0.8.2): eneste sted versjonsnummeret defineres - brukes i tittellinjen,
# oppstartsloggen, og av Collect-FiskumITDiagnostics sin Get-ArchiveVersion (regex mot
# DENNE linjen). Bump denne ved hver nye release, og tagg samme commit i git (se README)
$ManagerVersion = '0.8.3'
# Fiskum IT (v0.8.2): "ejer/repo"-form (uten https://github.com/-prefiks) - brukt direkte
# i GitHub REST API-URL-en av Test-NyVersjonTilgjengelig
$GitHubRepo = '88nightrider/FiskumIT-CoreCyclerManager-Norsk'

function Test-NyVersjonTilgjengelig {
    # Fiskum IT (v0.8.2): sjekker GitHub Releases-API'et for DETTE repoet direkte (ingen
    # autentisering - offentlig, skrivebeskyttet GET). Kaster ALDRI videre - en feilende
    # nettverkssjekk skal aldri kunne stoppe noe annet i Manageren. Kort timeout (5s) av
    # samme grunn - verre med en hengende oppstart enn en sjelden mislykket sjekk.
    # Brukes bade av den automatiske, cachede oppstartssjekken (Invoke-
    # OppdateringssjekkVedOppstart) og av "Sjekk etter oppdatering"-knappen (som alltid
    # kaller denne direkte, uten cache - et eksplisitt klikk skal alltid gi et live svar)
    $resultat = [pscustomobject]@{
        Forsokt               = $false
        NyVersjonTilgjengelig = $null
        SisteVersjon          = $null
        Url                   = $null
        Feilmelding           = $null
    }

    try {
        $respons = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest" `
            -Headers @{ 'User-Agent' = 'FiskumIT-CoreCyclerManager' } `
            -TimeoutSec 5 `
            -ErrorAction Stop

        $resultat.Forsokt = $true
        $sisteVersjonStreng = [string]$respons.tag_name -replace '^v', ''
        $resultat.SisteVersjon = $sisteVersjonStreng
        $resultat.Url = [string]$respons.html_url
        $resultat.NyVersjonTilgjengelig = ([version]$sisteVersjonStreng) -gt ([version]$ManagerVersion)
    }
    catch {
        $resultat.Feilmelding = $_.Exception.Message
        Write-ManagerLog -Text "Kunne ikke sjekke etter oppdatering: $($resultat.Feilmelding)"
    }

    return $resultat
}

function Invoke-OppdateringssjekkVedOppstart {
    # Fiskum IT (v0.8.2): automatisk, men cachet til maks en gang hver 2. time - sjekker
    # IKKE pa hver oppstart for a unnga a belaste GitHub sitt API unodvendig. Oppdaterer
    # knappeteksten i UI'et (hvis bygget) hvis en nyere versjon faktisk blir funnet
    param(
        [Parameter(Mandatory)]
        $State
    )

    $skalSjekke = $true

    if (-not [string]::IsNullOrWhiteSpace($State.sisteOppdateringssjekk)) {
        try {
            $sisteSjekk = [DateTime]::Parse($State.sisteOppdateringssjekk, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $skalSjekke = ((Get-Date) - $sisteSjekk).TotalHours -ge 2
        }
        catch {
            $skalSjekke = $true
        }
    }

    if (-not $skalSjekke) {
        return
    }

    $resultat = Test-NyVersjonTilgjengelig

    if ($resultat.Forsokt) {
        $State.sisteOppdateringssjekk = Get-NowIso
        Save-State -State $State

        if ($resultat.NyVersjonTilgjengelig -and $App.Ui.btnSjekkOppdatering) {
            $App.Ui.btnSjekkOppdatering.Text = "Ny versjon tilgjengelig: v$($resultat.SisteVersjon)"
            $App.Ui.btnSjekkOppdatering.BackColor = [System.Drawing.Color]::FromArgb(255,193,7)
        }
    }
}

# Fiskum IT: satt av Resolve-CrashedRun hvis en krasj ble oppdaget og korrigert ved oppstart -
# brukes til a gjenoppta testen automatisk etter at UI-et er bygget, se bunnen av scriptet
$PendingCrashResume = $false

foreach ($d in @(
    $ManagerDir,
    $ManagerLogDir,
    $ReportDir,
    $ConfigDir,
    $BackupDir,
    $CoreCyclerLogDir
)) {
    Ensure-Directory -Path $d
}

function New-DefaultState {
    return [pscustomobject]@{
        aktivTestId             = 1
        status                  = 'Klar'
        sisteFullforteTestId    = 0
        sisteLoggfil            = ''
        sisteHendelse           = 'Initialisert'
        coreStatus              = ''
        coreOffsets             = [pscustomobject]@{}
        offsetRekke             = 'Ingen Curve Optimizer-verdier registrert enda'
        sisteRapporterteOffset  = 'Ikke funnet i logg ennå'
        aktivProsessId          = $null
        aktivTestStart          = ''
        oppdatert               = (Get-NowIso)
        historie                = @()

        # Fiskum IT: modusvalg - 'Stabilitet' (Vanlig stabilitetstest, testplan.json) eller
        # 'AssistertUndervolting' (sok-modus mot AssistedUndervolting_Ryzen.ini)
        modus                   = 'Stabilitet'
        autoSwitchToStability   = $true

        # Fiskum IT: sann etter forste gangs start av en Assistert undervolting-sesjon,
        # brukes til aa avgjore om neste start er et gjenopptak (CurrentValues) eller en
        # helt ny sok-sesjon (0). Nullstilles av Switch-Modus.
        assistertSokStartet     = $false

        # Fiskum IT (v0.8.2): tidspunkt (ISO) for forste gangs start av sesjonen, satt pa
        # SAMME sted/betingelse som assistertSokStartet over. Brukes av Write-SluttRapport
        # til aa anslå hvor grundig soket var (total forlopt tid / antall testede kjerner) -
        # se Get-AnbefaltMargin. En grov Manager-side proxy, IKKE en presis iterasjonstelling
        # (motoren sporer ikke det) - en krasj+lang nedetid+gjenopptak vil telle dodtid som
        # "brukt tid", noe som gjor heuristikken FOR optimistisk om grundighet i et slikt
        # tilfelle, men aldri farlig under-kritisk
        assistertSokStartTid    = ''

        # Fiskum IT: speiler den siste offset-snapshoten fra motoren (se Get-CoreOffsetSnapshot)
        sokRetning              = 'Increasing'
        laasteKjerner           = [pscustomobject]@{}
        sisteOffsetSnapshotTid  = ''

        # Fiskum IT (v0.8.2): autostart/auto-restart - se Add-/Remove-ManagerAutoStartTask,
        # Ensure-AutoLogonConfigured og GroupBox-en "Automatisk gjenoppretting" i Build-Ui.
        # Default $false/$false for BEGGE - ingen oppforingsendring for noen som ikke
        # selv huker av disse valgene
        autostartTask           = $false
        autoRestartOnFeil       = $false
        restartWaitMinutes      = 5

        # Fiskum IT (v0.8.2): oyeblikksbilde av Windows autologon-tilstanden FOR vi
        # eventuelt endret den, slik at Remove-AutoLogonIfConfiguredByUs kan gjenopprette
        # noyaktig - se Ensure-AutoLogonConfigured. Skal ALDRI inneholde noe passord
        # (lagres separat som et LSA-secret, ikke i state.json)
        autoLogonConfiguredByUs = $false
        autoLogonPriorState     = $null

        # Fiskum IT (v0.8.2): satt rett for Restart-Computer kalles av Invoke-AutoRestartIfEnabled
        # - lest opp igjen ved neste Manager-oppstart (Check-PendingAutoResume) for aa avgjore
        # om/naar testen skal gjenopptas automatisk
        pendingAutoResume          = $false
        pendingAutoResumeNotBefore = ''

        # Fiskum IT (v0.8.2): teller konsekutive auto-restarts UTEN at en test faktisk har
        # fullfort i mellom - nullstilles kun ved en vellykket fullfort test, ikke av et
        # bevisst brukerstopp. Brukes til aa stoppe en potensiell uendelig reboot-lopp,
        # se Invoke-AutoRestartIfEnabled
        consecutiveAutoRestartCount = 0

        # Fiskum IT (v0.8.2): "bekreftelsesrunde" - en Vanlig stabilitetstest-kjoring som
        # bruker FASTE, margin-justerte verdier (enableAutomaticAdjustment=0) i stedet for
        # a soke, for a bekrefte at Write-SluttRapport sin "Anbefalt"-verdi faktisk er
        # stabil. Se Activate-TestConfig og completion-handling. Nullstilles ALLTID (suksess
        # ELLER feil) ved fullforing av denne spesifikke kjoringen - skal aldri kunne lekke
        # inn i en senere, urelatert vanlig stabilitetstest
        bekreftelseAktiv   = $false
        bekreftelseOffsets = ''

        # Fiskum IT (v0.8.2): lagret vindusstorrelse/-posisjon (se Build-Ui sin
        # Add_FormClosing) - 0 betyr "ikke lagret ennaa, bruk standardverdiene"
        vindueBredde = 0
        vindueHoyde  = 0
        vindueX      = 0
        vindueY      = 0

        # Fiskum IT (v0.8.2): tidspunkt (ISO) for siste GitHub-oppdateringssjekk - se
        # Invoke-OppdateringssjekkVedOppstart. Tom streng = aldri sjekket, sjekk na
        sisteOppdateringssjekk = ''
    }
}

function Get-PropertyNames {
    # Fiskum IT: ".PSObject.Properties.Name" (medlems-enumerering/"member enumeration") kaster
    # "The property 'Name' cannot be found on this object" under Set-StrictMode -Version Latest
    # NAR samlingen har 0 elementer - selv om SAMME uttrykk fungerer helt fint sa snart det er
    # 1 eller flere properties der. Dette er en reell, reprodusert StrictMode-felle (sett i
    # praksis pa WANJA-GAMER 2026-06-21 via laasteKjerner som var tom ved test-start) - denne
    # hjelpefunksjonen unngar problemet helt ved aldri a gjore medlems-enumerering pa en
    # eventuelt tom samling. Bruk denne i stedet for ".PSObject.Properties.Name" overalt.
    param(
        $Object
    )

    if ($null -eq $Object) {
        return @()
    }

    $properties = @($Object.PSObject.Properties)

    if ($properties.Count -eq 0) {
        return @()
    }

    return @($properties | ForEach-Object { $_.Name })
}

function Repair-State {
    param(
        [Parameter(Mandatory)]
        $State
    )

    $default = New-DefaultState

    foreach ($prop in (Get-PropertyNames -Object $default)) {
        if ((Get-PropertyNames -Object $State) -notcontains $prop) {
            $State | Add-Member -MemberType NoteProperty -Name $prop -Value $default.$prop
        }
    }

    if ($null -eq $State.aktivTestId -or [int]$State.aktivTestId -lt 1) {
        $State.aktivTestId = 1
    }

    if ([string]::IsNullOrWhiteSpace($State.status)) {
        $State.status = 'Klar'
    }

    if ([string]::IsNullOrWhiteSpace($State.sisteHendelse)) {
        $State.sisteHendelse = 'State reparert ved oppstart'
    }

    if ([string]::IsNullOrWhiteSpace($State.sisteRapporterteOffset)) {
        $State.sisteRapporterteOffset = 'Ikke funnet i logg ennå'
    }

    if ((Get-PropertyNames -Object $State) -notcontains 'coreOffsets' -or $null -eq $State.coreOffsets) {
        $State | Add-Member -MemberType NoteProperty -Name 'coreOffsets' -Value ([pscustomobject]@{}) -Force
    }

    if ((Get-PropertyNames -Object $State) -notcontains 'offsetRekke' -or [string]::IsNullOrWhiteSpace([string]$State.offsetRekke)) {
        if ((Get-PropertyNames -Object $State) -contains 'offsetRekke') {
            $State.offsetRekke = 'Ingen Curve Optimizer-verdier registrert enda'
        }
        else {
            $State | Add-Member -MemberType NoteProperty -Name 'offsetRekke' -Value 'Ingen Curve Optimizer-verdier registrert enda' -Force
        }
    }

    if ($null -eq $State.historie) {
        $State.historie = @()
    }

    return $State
}

function Get-State {
    $state = Read-JsonFile -Path $StateFile

    if (-not $state) {
        $state = New-DefaultState
        Save-State -State $state
        return $state
    }

    $state = Repair-State -State $state
    Save-State -State $state

    return $state
}

function Save-State {
    param(
        [Parameter(Mandatory)]
        $State
    )

    $State.oppdatert = Get-NowIso
    Write-JsonFile -Path $StateFile -Object $State
}

function Add-History {
    # Fiskum IT: skriver na ogsa til Manager-loggfilen (Manager\logs\Manager_*.log) - ikke
    # bare til state.json sin "historie"-liste. "State og historikk"-panelet i UI'et er
    # fjernet (for teknisk/uinteressant for vanlige brukere), men hendelsene ma fortsatt
    # kunne spores etterpa, og Collect-FiskumITDiagnostics samler kun inn .log/.txt-filer
    # fra Manager\logs - ikke state.json
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $entry = [pscustomobject]@{
        tid     = Get-NowIso
        melding = $Message
    }

    $all = @()

    if ($State.historie) {
        $all = @($State.historie)
    }

    $State.historie = @($all + $entry | Select-Object -Last 100)

    Write-ManagerLog -Text $Message
}

function Write-ManagerLog {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $line = '{0} - {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
    $file = Join-Path $ManagerLogDir ('Manager_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))

    Add-Content -LiteralPath $file -Value $line -Encoding UTF8
}

function Get-ManagerAutoStartTaskName {
    return 'FiskumIT CoreCycler Manager AutoStart'
}

function Add-ManagerAutoStartTask {
    # Fiskum IT: registrerer en Scheduled Task som starter Manageren ved neste innlogging.
    # Forutsetning for helautomatisk gjenopptak etter en hard krasj/reboot: dette krever at
    # Windows auto-logon er konfigurert pa maskinen (samme forutsetning som CoreCyclers egen
    # dokumentasjon for enableResumeAfterUnexpectedExit). FRA v0.8.2: dette kan na konfigureres
    # AV Manageren selv ved behov - se Ensure-AutoLogonConfigured, kalt fra
    # Invoke-AutoRestartIfEnabled - i stedet for a kreve at brukeren satte det opp manuelt.
    $taskName = Get-ManagerAutoStartTaskName

    try {
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if ($existing) {
            return
        }

        $action    = New-ScheduledTaskAction -Execute $StartBatPath -WorkingDirectory $ManagerDir
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-ManagerLog -Text "Scheduled Task '$taskName' registrert for automatisk oppstart av Manageren ved innlogging."
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke registrere oppstart-Scheduled Task: $($_.Exception.Message)"
    }
}

function Remove-ManagerAutoStartTask {
    $taskName = Get-ManagerAutoStartTaskName

    try {
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if ($existing) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-ManagerLog -Text "Scheduled Task '$taskName' fjernet."
        }
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke fjerne oppstart-Scheduled Task: $($_.Exception.Message)"
    }
}

function Set-LsaPrivateData {
    # Fiskum IT (v0.8.2): lav-niva LSA-secret-skriving/-sletting - se Add-Type-blokken
    # "FiskumIT.LsaSecrets" i toppen av filen for bakgrunnen. $Value = $null/tom streng
    # SLETTER secret-en (LsaStorePrivateData sin dokumenterte oppforing nar PrivateData-
    # pekeren er NULL - IKKE det samme som a sette den til en tom streng)
    param(
        [Parameter(Mandatory)]
        [string]$KeyName,

        [string]$Value
    )

    $POLICY_CREATE_SECRET = 0x00000020
    $policyHandle   = [IntPtr]::Zero
    $keyNamePtr     = [IntPtr]::Zero
    $valueStringPtr = [IntPtr]::Zero
    $valueStructPtr = [IntPtr]::Zero

    try {
        $systemName       = New-Object FiskumIT.LsaSecrets+LSA_UNICODE_STRING
        $objectAttributes = New-Object FiskumIT.LsaSecrets+LSA_OBJECT_ATTRIBUTES
        $objectAttributes.Length = [System.Runtime.InteropServices.Marshal]::SizeOf($objectAttributes)

        $openStatus = [FiskumIT.LsaSecrets]::LsaOpenPolicy([ref]$systemName, [ref]$objectAttributes, $POLICY_CREATE_SECRET, [ref]$policyHandle)

        if ($openStatus -ne 0) {
            $win32Err = [FiskumIT.LsaSecrets]::LsaNtStatusToWinError($openStatus)
            Write-ManagerLog -Text "LsaOpenPolicy feilet (Win32-feilkode $win32Err) - kan ikke konfigurere autologon."
            return $false
        }

        $keyNamePtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($KeyName)
        $keyNameStruct = New-Object FiskumIT.LsaSecrets+LSA_UNICODE_STRING
        $keyNameStruct.Buffer        = $keyNamePtr
        $keyNameStruct.Length        = [uint16]($KeyName.Length * 2)
        $keyNameStruct.MaximumLength = [uint16](($KeyName.Length * 2) + 2)

        $dataPtr = [IntPtr]::Zero

        if (-not [string]::IsNullOrEmpty($Value)) {
            $valueStringPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($Value)
            $valueStruct = New-Object FiskumIT.LsaSecrets+LSA_UNICODE_STRING
            $valueStruct.Buffer        = $valueStringPtr
            $valueStruct.Length        = [uint16]($Value.Length * 2)
            $valueStruct.MaximumLength = [uint16](($Value.Length * 2) + 2)

            $valueStructPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([System.Runtime.InteropServices.Marshal]::SizeOf($valueStruct))
            [System.Runtime.InteropServices.Marshal]::StructureToPtr($valueStruct, $valueStructPtr, $false)
            $dataPtr = $valueStructPtr
        }

        $storeStatus = [FiskumIT.LsaSecrets]::LsaStorePrivateData($policyHandle, [ref]$keyNameStruct, $dataPtr)

        if ($storeStatus -ne 0) {
            $win32Err = [FiskumIT.LsaSecrets]::LsaNtStatusToWinError($storeStatus)
            Write-ManagerLog -Text "LsaStorePrivateData feilet for '$KeyName' (Win32-feilkode $win32Err)."
            return $false
        }

        return $true
    }
    catch {
        Write-ManagerLog -Text "Uventet feil i Set-LsaPrivateData: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($policyHandle -ne [IntPtr]::Zero) {
            [void][FiskumIT.LsaSecrets]::LsaClose($policyHandle)
        }
        if ($keyNamePtr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($keyNamePtr)
        }
        if ($valueStringPtr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($valueStringPtr)
        }
        if ($valueStructPtr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($valueStructPtr)
        }
    }
}

function Get-AutoLogonRegistryState {
    # Fiskum IT (v0.8.2): leser ALDRI DefaultPassword (brukes ikke i denne losningen -
    # se Set-LsaPrivateData/Add-Type-blokken "FiskumIT.LsaSecrets")
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    $autoAdminLogon              = $null
    $defaultUserName             = $null
    $defaultDomainName           = $null
    $autoAdminLogonWasPresent    = $false
    $defaultUserNameWasPresent   = $false
    $defaultDomainNameWasPresent = $false

    $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue

    if ($props) {
        $propNames = Get-PropertyNames -Object $props

        if ($propNames -contains 'AutoAdminLogon') {
            $autoAdminLogon = $props.AutoAdminLogon
            $autoAdminLogonWasPresent = $true
        }
        if ($propNames -contains 'DefaultUserName') {
            $defaultUserName = $props.DefaultUserName
            $defaultUserNameWasPresent = $true
        }
        if ($propNames -contains 'DefaultDomainName') {
            $defaultDomainName = $props.DefaultDomainName
            $defaultDomainNameWasPresent = $true
        }
    }

    return [pscustomobject]@{
        IsEnabled                   = ($autoAdminLogon -eq '1')
        AutoAdminLogon              = $autoAdminLogon
        AutoAdminLogonWasPresent    = $autoAdminLogonWasPresent
        DefaultUserName             = $defaultUserName
        DefaultUserNameWasPresent   = $defaultUserNameWasPresent
        DefaultDomainName           = $defaultDomainName
        DefaultDomainNameWasPresent = $defaultDomainNameWasPresent
    }
}

function Test-CurrentUserHasPassword {
    # Fiskum IT (v0.8.2): returnerer $true/$false, eller strengen 'Unknown' for kontotyper
    # Get-LocalUser ikke kan svare for (Microsoft-konto/domenekonto) - IKKE behandlet som
    # "hopp over" av kalleren, se Ensure-AutoLogonConfigured
    try {
        $localUser = Get-LocalUser -Name $env:USERNAME -ErrorAction Stop
        return [bool]$localUser.PasswordRequired
    }
    catch {
        return 'Unknown'
    }
}

function Set-AutoLogonRegistryValues {
    param(
        [Parameter(Mandatory)]
        [string]$UserName,

        [Parameter(Mandatory)]
        [string]$DomainName
    )

    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    try {
        New-ItemProperty -Path $regPath -Name 'AutoAdminLogon' -PropertyType String -Value '1' -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'DefaultUserName' -PropertyType String -Value $UserName -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'DefaultDomainName' -PropertyType String -Value $DomainName -Force | Out-Null
        return $true
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke sette autologon-registerverdier: $($_.Exception.Message)"
        return $false
    }
}

function Ensure-AutoLogonConfigured {
    # Fiskum IT (v0.8.2): konfigurerer Windows-autologon KUN hvis den ikke allerede er
    # pa (uansett hvem/hva som satte den opp) - rorer ALDRI en eksisterende konfigurasjon.
    # Se Restore-AutoLogonPriorState/Remove-AutoLogonIfConfiguredByUs for opprydding.
    # Passordet holdes KUN transient i en lokal variabel her - aldri i $State/logg/state.json
    param(
        [Parameter(Mandatory)]
        $State
    )

    $current = Get-AutoLogonRegistryState

    if ($current.IsEnabled) {
        Write-ManagerLog -Text "Autologon er allerede konfigurert (uavhengig av oss) - endrer ingenting."
        return $true
    }

    $State.autoLogonPriorState = [pscustomobject]@{
        AutoAdminLogonWasPresent    = $current.AutoAdminLogonWasPresent
        AutoAdminLogon              = $current.AutoAdminLogon
        DefaultUserNameWasPresent   = $current.DefaultUserNameWasPresent
        DefaultUserName             = $current.DefaultUserName
        DefaultDomainNameWasPresent = $current.DefaultDomainNameWasPresent
        DefaultDomainName           = $current.DefaultDomainName
    }

    $harPassord = Test-CurrentUserHasPassword

    if ($harPassord -eq $false) {
        # Fiskum IT: ALDRI logg $env:USERNAME her - brukernavn/passord skal ikke kunne leses ut av loggen
        Write-ManagerLog -Text "Brukerkontoen ser ikke ut til a ha passord satt - sporr likevel, siden autologon krever et lagret passord for a fungere palitelig."
    }
    elseif ($harPassord -eq 'Unknown') {
        Write-ManagerLog -Text "Kunne ikke avgjore om brukerkontoen har passord (mulig Microsoft-/domenekonto) - sporr likevel."
    }

    $cred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Windows-autologon må konfigureres for at Manageren skal kunne gjenoppta automatisk etter en automatisk restart.`r`n`r`nSkriv inn PASSORDET for denne brukeren (IKKE PIN-koden/Windows Hello).`r`n`r`nHar kontoen ingen passord? Trykk OK uten å skrive noe."

    if (-not $cred) {
        Write-ManagerLog -Text "Bruker avbrøt autologon-oppsett. Auto-restart kan ikke fullføres trygt denne gangen."
        return $false
    }

    $brukernavn = $env:USERNAME
    $domene     = $env:USERDOMAIN

    if ($cred.UserName -match '^(?<domene>[^\\]+)\\(?<bruker>.+)$') {
        $domene     = $Matches['domene']
        $brukernavn = $Matches['bruker']
    }
    elseif ($cred.UserName) {
        $brukernavn = $cred.UserName
    }

    if ($brukernavn -match '@') {
        Write-ManagerLog -Text "Denne brukeren ser ut til å være en Microsoft-konto. Autologon kan være mindre pålitelig, og fungerer ikke i det hele tatt med PIN-/Windows Hello-kun-pålogging."
    }

    $plainPassword = $cred.GetNetworkCredential().Password
    $secretOk = Set-LsaPrivateData -KeyName 'DefaultPassword' -Value $plainPassword
    $plainPassword = $null

    if (-not $secretOk) {
        Write-ManagerLog -Text "Kunne ikke lagre passordet sikkert (LSA secret). Avbryter autologon-oppsett."
        $State.autoLogonConfiguredByUs = $false
        return $false
    }

    $registryOk = Set-AutoLogonRegistryValues -UserName $brukernavn -DomainName $domene

    if (-not $registryOk) {
        Write-ManagerLog -Text "LSA-secret ble lagret, men registerverdiene for autologon kunne ikke settes. Markerer for opprydding ved neste anledning."
        $State.autoLogonConfiguredByUs = $true
        Save-State -State $State
        return $false
    }

    $State.autoLogonConfiguredByUs = $true
    Save-State -State $State
    # Fiskum IT: ALDRI logg $domene/$brukernavn her - brukernavn/passord skal ikke kunne leses ut av loggen
    Write-ManagerLog -Text "Windows-autologon konfigurert."
    return $true
}

function Invoke-ProaktivAutologonOppsett {
    # Fiskum IT (v0.8.3): kalt fra et eksplisitt, BRUKERINITIERT "Start"-klikk (F5/knapp) -
    # IKKE fra automatiske gjenopptak etter krasj/restart, der brukeren typisk IKKE sitter
    # ved maskinen. Passordsporsmalet kom tidligere KUN reaktivt, inni selve
    # krasj/restart-handteringen (Invoke-AutoRestartIfEnabled) - upraktisk, siden de fleste
    # ikke sitter ved PC-en gjennom hele testen og dermed aldri far svart pa prompten.
    # Sporres derfor proaktivt her i stedet, mens brukeren uansett er ved maskinen.
    # Ensure-AutoLogonConfigured er selv idempotent (gjor ingenting hvis allerede
    # konfigurert), sa det er trygt at Invoke-AutoRestartIfEnabled fortsatt ogsa kaller den
    # senere som et sikkerhetsnett (f.eks. hvis brukeren skrur PA bryteren etter Start)
    if (-not [bool]$App.State.autoRestartOnFeil) {
        return
    }

    [void](Ensure-AutoLogonConfigured -State $App.State)
}

function Restore-AutoLogonPriorState {
    # Fiskum IT (v0.8.2): gjenoppretter BYTE-FOR-BYTE tilstanden fra FOR Ensure-AutoLogonConfigured
    # endret noe - fjerner verdier som ikke fantes, gjenoppretter spesifikke verdier som fantes
    param(
        [Parameter(Mandatory)]
        $PriorState
    )

    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    try {
        if ($PriorState.AutoAdminLogonWasPresent) {
            New-ItemProperty -Path $regPath -Name 'AutoAdminLogon' -PropertyType String -Value $PriorState.AutoAdminLogon -Force | Out-Null
        }
        else {
            Remove-ItemProperty -Path $regPath -Name 'AutoAdminLogon' -ErrorAction SilentlyContinue
        }

        if ($PriorState.DefaultUserNameWasPresent) {
            New-ItemProperty -Path $regPath -Name 'DefaultUserName' -PropertyType String -Value $PriorState.DefaultUserName -Force | Out-Null
        }
        else {
            Remove-ItemProperty -Path $regPath -Name 'DefaultUserName' -ErrorAction SilentlyContinue
        }

        if ($PriorState.DefaultDomainNameWasPresent) {
            New-ItemProperty -Path $regPath -Name 'DefaultDomainName' -PropertyType String -Value $PriorState.DefaultDomainName -Force | Out-Null
        }
        else {
            Remove-ItemProperty -Path $regPath -Name 'DefaultDomainName' -ErrorAction SilentlyContinue
        }

        Set-LsaPrivateData -KeyName 'DefaultPassword' -Value $null | Out-Null

        Write-ManagerLog -Text "Autologon-konfigurasjon tilbakestilt til tilstanden fra før Manageren endret den."
    }
    catch {
        Write-ManagerLog -Text "Feil under tilbakestilling av autologon: $($_.Exception.Message)"
    }
}

function Remove-AutoLogonIfConfiguredByUs {
    # Fiskum IT (v0.8.2): no-op hvis autologon var konfigurert av noe ANNET enn oss FOR
    # vi ruerte den - rorer den da ALDRI, verken na eller senere
    param(
        [Parameter(Mandatory)]
        $State
    )

    if (-not [bool]$State.autoLogonConfiguredByUs) {
        return
    }

    if ($State.autoLogonPriorState) {
        Restore-AutoLogonPriorState -PriorState $State.autoLogonPriorState
    }

    $State.autoLogonConfiguredByUs = $false
    $State.autoLogonPriorState = $null
    Save-State -State $State
}

function Remove-AutoRecoveryInfrastructure {
    # Fiskum IT (v0.8.2): samlefunksjon kalt ved bevisst stopp/fullfort plan/full reset -
    # rydder bade autostart-task OG autologon (kun det VI faktisk satte opp) i samme slag
    param(
        [Parameter(Mandatory)]
        $State
    )

    if ($State.autostartTask) {
        Remove-ManagerAutoStartTask
    }

    Remove-AutoLogonIfConfiguredByUs -State $State
}

function Update-CoreOffsetSnapshotFile {
    # Fiskum IT: skriver korrigerte verdier (etter krasj-tilbakestilling) tilbake til SELVE
    # snapshot-filen, ikke bare til CPU-en. Uten dette ville motoren - som na foretrekker
    # denne filen over "CurrentValues" ved oppstart, se Get-FiskumOffsetSnapshotValues i
    # script-corecycler.ps1 - lese den GAMLE, ukorrigerte verdien igjen ved gjenopptak
    param(
        [Parameter(Mandatory)] [Array] $Offsets,
        [Parameter(Mandatory)] [int] $ActiveCore
    )

    try {
        $path = Join-Path $CoreCyclerLogDir 'fiskumit-offset-snapshot.json'
        $existing = Get-CoreOffsetSnapshot

        $snapshotObject = [Ordered] @{
            'timestamp'       = [UInt64] [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            'activeCore'      = $ActiveCore
            'searchDirection' = $(if ($existing -and $existing.searchDirection) { [string] $existing.searchDirection } else { 'Increasing' })
            'incrementBy'     = $(if ($existing -and $existing.incrementBy) { [int] $existing.incrementBy } else { 1 })
            'maxValue'        = $(if ($existing -and $null -ne $existing.maxValue) { [int] $existing.maxValue } else { 0 })
            'offsets'         = @($Offsets)
            'lockedCores'     = $(if ($existing -and $existing.lockedCores) { $existing.lockedCores } else { [Ordered] @{} })
        }

        ($snapshotObject | ConvertTo-Json) | Set-Content -LiteralPath $path -Encoding UTF8
        return $true
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke oppdatere offset-snapshotfilen etter krasjkorrigering: $($_.Exception.Message)"
        return $false
    }
}

function Resolve-CrashedRun {
    # Fiskum IT: kalles fra Clear-StaleRunningState nar en krasj/hard avbrytelse er oppdaget
    # (status var "Kjører" men CoreCycler-prosessen er ikke aktiv ved oppstart av Manageren).
    # Leser den alltid-pa offset-snapshoten fra motoren, stiller den aktive kjernen ETT hakk
    # tilbake (samme formel som motorens egen Test-AutomaticTestModeIncrease), skriver den
    # korrigerte verdien direkte til CPU-en OG til snapshot-filen (se
    # Update-CoreOffsetSnapshotFile), og gjenopptar testen automatisk - for BADE
    # Assistert undervolting og Vanlig stabilitetstest.
    param(
        [Parameter(Mandatory)]
        $State
    )

    Write-ManagerLog -Text 'Krasj oppdaget: forrige kjøring ble ikke avsluttet rent. Forsøker automatisk gjenoppretting.'

    $snapshot = Get-CoreOffsetSnapshot

    if (-not $snapshot -or $null -eq $snapshot.offsets) {
        $State.sisteHendelse = 'Krasj oppdaget, men fant ingen offset-snapshot å gjenopprette fra. Du må starte testen på nytt manuelt.'
        Add-History -State $State -Message $State.sisteHendelse
        Save-State -State $State
        return
    }

    $offsets     = @($snapshot.offsets | ForEach-Object { [int] $_ })
    $activeCore  = $snapshot.activeCore
    $incrementBy = $(if ($snapshot.incrementBy) { [int] $snapshot.incrementBy } else { 1 })
    $maxValue    = $(if ($null -ne $snapshot.maxValue) { [int] $snapshot.maxValue } else { 0 })

    if ($null -ne $activeCore -and [int]$activeCore -ge 0 -and [int]$activeCore -lt $offsets.Count) {
        $activeCore = [int]$activeCore
        $oldValue   = $offsets[$activeCore]
        $newValue   = [Math]::Max($oldValue, [Math]::Min($oldValue + $incrementBy, $maxValue))
        $offsets[$activeCore] = $newValue

        if ($newValue -ne $oldValue) {
            Write-ManagerLog -Text "Krasj under test av Core $activeCore (offset $oldValue). Stiller tilbake ett hakk til $newValue og gjenopptar."
        }
        else {
            Write-ManagerLog -Text "Krasj under test av Core $activeCore (offset $oldValue, allerede ved grensen). Gjenopptar uendret."
        }

        # Fiskum IT: Intel har bare EN reell verdi (alle kjerner settes alltid likt, se
        # Get-UndervoltStotteInfo) - $offsets[$activeCore] er like riktig som noe annet
        # indeks der, siden snapshotens "offsets"-array allerede er fylt med samme verdi
        $stotteVedKrasj = Get-UndervoltStotteInfo
        $applied = $(if ($stotteVedKrasj.Vendor -eq 'Intel') {
            Set-OffsetViaIntelVoltageControl -Verdi $newValue
        } else {
            Set-OffsetsViaRyzenSmuCli -Offsets $offsets
        })

        if (-not $applied) {
            $State.status = 'Feil'
            $State.sisteHendelse = "Krasj oppdaget (Core $activeCore), men automatisk korrigering av spenningsverdien feilet. Kontroller verdiene manuelt før du fortsetter."
            Add-History -State $State -Message $State.sisteHendelse
            Save-State -State $State
            Invoke-AutoRestartIfEnabled -State $State -Reason 'Krasj oppdaget ved oppstart, automatisk korrigering feilet'
            return
        }

        # Fiskum IT: oppdater ogsa snapshot-FILEN, ikke bare CPU-en - se Update-CoreOffsetSnapshotFile
        [void](Update-CoreOffsetSnapshotFile -Offsets $offsets -ActiveCore $activeCore)

        $State.sisteHendelse = "Krasj oppdaget under test av Core $activeCore. Stilte tilbake fra $oldValue til $newValue og gjenopptar automatisk."
    }
    else {
        $State.sisteHendelse = 'Krasj oppdaget, men fant ingen aktiv kjerne i offset-snapshoten. Gjenopptar uendret.'
    }

    Add-History -State $State -Message $State.sisteHendelse
    Save-State -State $State

    # Fiskum IT: dette kjorer for UI-et (Build-Ui/Refresh-UiState) finnes, sa vi kan ikke
    # kalle Start-CurrentOrResume direkte her (den refererer $App.Ui-kontroller). Sett et
    # flagg som ses opp etter at vinduet er bygget, se bunnen av scriptet.
    $Script:PendingCrashResume = $true
}

function Invoke-AutoRestartIfEnabled {
    # Fiskum IT (v0.8.2): kalt rett etter de 4 stedene som setter status='Feil' (se
    # Resolve-CrashedRun, Start-CurrentOrResume, Handle-ProcessFinished x2). Helt opt-in -
    # gjor INGENTING hvis brukeren ikke har huket av "Auto-restart ved krasj/feil" i UI-et,
    # sa oppforingen er byte-for-byte uendret for alle som ikke selv skrur dette pa
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    if (-not [bool]$State.autoRestartOnFeil) {
        return
    }

    # Fiskum IT: forsoksgrense - unngar en uendelig reboot-lopp hvis det underliggende
    # problemet (f.eks. et reelt minneproblem, som pa NR-GAMER 2026-06-21) ikke lar seg
    # lose av en restart alene. Nullstilles KUN ved en faktisk fullfort test (se
    # Handle-ProcessFinished), ikke av at en restart i seg selv lykkes
    if ([int]$State.consecutiveAutoRestartCount -ge 3) {
        Write-ManagerLog -Text "Auto-restart-grense nådd (3 påfølgende restarts uten en fullført test). Avbryter automatisk gjenoppretting - krever manuell inspeksjon."
        $State.sisteHendelse = 'Auto-restart-grense nådd. Manuell inspeksjon kreves.'
        Add-History -State $State -Message $State.sisteHendelse
        Save-State -State $State
        return
    }

    if (-not $State.autostartTask) {
        Write-ManagerLog -Text 'Autostart var ikke aktivert da auto-restart ble utløst - aktiverer den nå automatisk.'
        $State.autostartTask = $true
    }

    Add-ManagerAutoStartTask

    $autoLogonOk = Ensure-AutoLogonConfigured -State $State

    if (-not $autoLogonOk) {
        # Fiskum IT: aldri restart inn i en blindgate der ingen kan logge inn igjen -
        # se Ensure-AutoLogonConfigured for hvorfor dette kan returnere $false
        Write-ManagerLog -Text 'Autologon kunne ikke konfigureres (bruker avbrøt, eller en feil oppstod) - kan ikke garantere automatisk gjenopptak etter restart. Restarter IKKE automatisk denne gangen.'
        $State.sisteHendelse = 'Auto-restart avbrutt: autologon kunne ikke konfigureres.'
        Add-History -State $State -Message $State.sisteHendelse
        Save-State -State $State
        return
    }

    $ventTil = (Get-Date).AddMinutes([int]$State.restartWaitMinutes)

    $State.pendingAutoResume = $true
    $State.pendingAutoResumeNotBefore = $ventTil.ToString('o')
    $State.consecutiveAutoRestartCount = [int]$State.consecutiveAutoRestartCount + 1

    Add-History -State $State -Message "Auto-restart utløst: $Reason"
    Save-State -State $State

    Write-DesktopSnapshot -Reason "Auto-restart utløst: $Reason - datamaskinen restarter automatisk for å gjenopprette" -CoreStatus $State.coreStatus

    $fortsett = Show-AutoRestartCountdown

    if (-not $fortsett) {
        Write-ManagerLog -Text 'Auto-restart avbrutt av bruker under nedtelling.'
        $State.pendingAutoResume = $false
        $State.pendingAutoResumeNotBefore = ''
        Save-State -State $State
        return
    }

    try {
        Write-ManagerLog -Text 'Restarter datamaskinen nå (auto-restart ved krasj/feil).'
        Restart-Computer -Force
    }
    catch {
        # Fiskum IT: restarten skjedde IKKE - en fremtidig, urelatert restart (f.eks. av
        # IT-personell uker senere) skal da ikke feilaktig trigge et gjenopptak av en na
        # foreldet test, se Check-PendingAutoResume
        Write-ManagerLog -Text "Restart-Computer feilet: $($_.Exception.Message)"
        $State.pendingAutoResume = $false
        $State.pendingAutoResumeNotBefore = ''
        Save-State -State $State
    }
}

function Check-PendingAutoResume {
    # Fiskum IT (v0.8.2): kalt rett etter Clear-StaleRunningState ved oppstart - sjekker om
    # Manageren nettopp kom opp igjen etter en auto-utlost restart (se
    # Invoke-AutoRestartIfEnabled). Speiler $Script:PendingCrashResume sitt monster: kan
    # ikke kalle Start-CurrentOrResume direkte her siden $App.Ui ikke finnes ennaa
    param(
        [Parameter(Mandatory)]
        $State
    )

    if (-not [bool]$State.pendingAutoResume) {
        return
    }

    $ventTil = $null

    try {
        $ventTil = [DateTime]::Parse($State.pendingAutoResumeNotBefore)
    }
    catch {
        $ventTil = Get-Date
    }

    if ((Get-Date) -lt $ventTil) {
        Write-ManagerLog -Text "Auto-restart-gjenopptak venter til $($ventTil.ToString('yyyy-MM-dd HH:mm:ss')) (restartWaitMinutes=$($State.restartWaitMinutes))."
        # Fiskum IT: sjekkes pa nytt i timeren (se Add_Tick) for tilfellet der Manageren
        # allerede star og kjorer nar ventetiden gar ut - unngar en blokkerende Start-Sleep
        $Script:PendingAutoResumeNotBefore = $ventTil
        return
    }

    Write-ManagerLog -Text 'Ventetid etter auto-restart er over. Gjenopptar testen automatisk.'
    $State.pendingAutoResume = $false
    $State.pendingAutoResumeNotBefore = ''
    Save-State -State $State
    $Script:PendingAutoResumeAfterStartup = $true
}

function Clear-StaleRunningState {
    param(
        [Parameter(Mandatory)]
        $State
    )

    if ($State.aktivProsessId) {
        $exists = $false

        try {
            $null = Get-Process -Id $State.aktivProsessId -ErrorAction Stop
            $exists = $true
        }
        catch {
            $exists = $false
        }

        if (-not $exists) {
            $State.aktivProsessId = $null
            $varKrasj = ($State.status -eq 'Kjører')

            if ($varKrasj) {
                $State.status = 'Stoppet'
                $State.sisteHendelse = 'Forrige kjøring var ikke aktiv ved oppstart. State er satt til Stoppet.'
                Add-History -State $State -Message $State.sisteHendelse
            }

            Save-State -State $State

            # Fiskum IT: status var "Kjører" ved forrige avslutning -> ekte krasj (et bevisst
            # "Stopp test"-klikk eller en ren avslutning setter alltid status til "Stoppet" selv)
            if ($varKrasj) {
                Resolve-CrashedRun -State $State
            }
        }
    }
}

function Get-CpuInstruksjonssett {
    # Fiskum IT: avgjor hvilke SIMD-instruksjonssett (AVX/AVX2/AVX512) denne CPU-en
    # faktisk stotter, via Windows' egen IsProcessorFeaturePresent (kernel32.dll) - se
    # Add-Type-deklarasjonen i toppen av filen. Brukes til a velge optimale standardtester
    # (Get-StabilitetsPlan) og til a gra ut/hindre avhuking av ustottede tester i
    # "Avansert..."-dialogen (Show-AvansertDialog), slik at Manageren takler alle
    # x86-64-CPU'er - ikke bare AMD Ryzen 3000/5000
    # PF_AVX_INSTRUCTIONS_AVAILABLE=39, PF_AVX2_INSTRUCTIONS_AVAILABLE=40,
    # PF_AVX512F_INSTRUCTIONS_AVAILABLE=41 (Windows SDK sin winnt.h) - verifisert empirisk
    # mot en kjent CPU-modell (Skylake-U: AVX/AVX2 ja, AVX512 nei) under utvikling
    if ($Script:CpuInstruksjonssettCache) {
        return $Script:CpuInstruksjonssettCache
    }

    try {
        $avx    = [FiskumIT.CpuFeature]::IsProcessorFeaturePresent(39)
        $avx2   = [FiskumIT.CpuFeature]::IsProcessorFeaturePresent(40)
        $avx512 = [FiskumIT.CpuFeature]::IsProcessorFeaturePresent(41)
    }
    catch {
        # Fiskum IT: hvis selve sjekken feiler, anta laveste fellesnevner (kun det som
        # garantert finnes pa enhver x86-64-CPU) i stedet for a anta stotte som kan vaere feil
        $avx = $false; $avx2 = $false; $avx512 = $false
    }

    $Script:CpuInstruksjonssettCache = [pscustomobject]@{
        AVX    = [bool]$avx
        AVX2   = [bool]$avx2
        AVX512 = [bool]$avx512
    }

    return $Script:CpuInstruksjonssettCache
}

function Get-SystemResourceSnapshot {
    # Fiskum IT (v0.8.2): for lettere feilsoking ved svaert lange kjoringer - funnet
    # nodvendig etter en reell hendelse pa NR-GAMER (2026-06-21) der systemet gikk tom
    # for minne over ca. 17 sammenhengende timer, men ingen logg viste denne opptrappingen
    # underveis - kun de endelige feilmeldingene da det allerede var for sent
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalKB = [double]$os.TotalVisibleMemorySize
        $freeKB  = [double]$os.FreePhysicalMemory

        if ($totalKB -le 0) {
            return $null
        }

        $bruktKB     = $totalKB - $freeKB
        $ramProsent  = [math]::Round(($bruktKB / $totalKB) * 100)
        $ramBruktGB  = [math]::Round($bruktKB / 1MB, 1)
        $ramTotaltGB = [math]::Round($totalKB / 1MB, 1)

        $topProsess = Get-Process -ErrorAction SilentlyContinue |
            Sort-Object -Property WorkingSet64 -Descending |
            Select-Object -First 1

        $topNavn = ''
        $topMB   = 0

        if ($topProsess) {
            $topNavn = $topProsess.ProcessName
            $topMB   = [math]::Round($topProsess.WorkingSet64 / 1MB)
        }

        return [pscustomobject]@{
            RamProsent     = $ramProsent
            RamBruktGB     = $ramBruktGB
            RamTotaltGB    = $ramTotaltGB
            TopProsessNavn = $topNavn
            TopProsessMB   = $topMB
        }
    }
    catch {
        return $null
    }
}

function Write-SystemResourceLogIfDue {
    # Fiskum IT (v0.8.2): logger maks en gang per 60 sekund (IKKE hvert 1,5 sek-tick) -
    # 60 sek gir nok opplosning til a se en minne-opptrapping over flere timer, uten at
    # selve loggingen bidrar nevneverdig til loggvekst over en svaert lang kjoring
    $naa = Get-Date

    if ($Script:SisteRessursLoggTid -and (($naa - $Script:SisteRessursLoggTid).TotalSeconds -lt 60)) {
        return
    }

    $Script:SisteRessursLoggTid = $naa

    try {
        $snap = Get-SystemResourceSnapshot

        if ($snap) {
            Write-ManagerLog -Text ("Ressursbruk: RAM {0}% ({1} GB / {2} GB) - storste prosess: {3} ({4} MB)" -f $snap.RamProsent, $snap.RamBruktGB, $snap.RamTotaltGB, $snap.TopProsessNavn, $snap.TopProsessMB)
        }
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke logge ressursbruk: $($_.Exception.Message)"
    }
}

function Test-StottetAvCpu {
    # Fiskum IT: $Krav er testplan.json sitt "kreverInstruksjonssett"-felt - tomt/manglende
    # betyr ingen krav utover grunnleggende x86-64 (stottes derfor alltid)
    param(
        [string]$Krav
    )

    if (-not $Krav) {
        return $true
    }

    $cap = Get-CpuInstruksjonssett

    switch ($Krav) {
        'AVX'    { return $cap.AVX }
        'AVX2'   { return $cap.AVX2 }
        'AVX512' { return $cap.AVX512 }
        default  { return $true }
    }
}

function Get-UndervoltStotteInfo {
    # Fiskum IT: avgjor om og hvordan "Assistert undervolting" kan kjores pa DENNE CPU-en.
    #
    # AMD: Curve Optimizer er en AMD-funksjon som forst kom med Zen 3 (Ryzen 5000-serien) -
    # Ryzen 1000/2000/3000/4000 (Zen 1/Zen+/Zen 2) har den IKKE, uavhengig av hva motoren
    # ellers stotter for disse generasjonene (f.eks. vanlig stabilitetstest). Minimumsverdien
    # for Curve Optimizer er ogsa generasjonsavhengig: -30 for 5000/6000-serien, -50 for
    # 7000-serien og nyere - se ogsa script-corecycler.ps1 sin egen "[7-9]\d{3}"-sjekk for
    # "startValues = Minimum", som denne funksjonen er bevisst konsistent med.
    # Threadripper/EPYC/Athlon gjenkjennes IKKE av modellnummer-regex-en under (de bruker en
    # annen navngivning), og behandles derfor som "ikke vurdert" - ikke fordi de garantert
    # mangler Curve Optimizer, men fordi vi ikke har grunnlag for a si noe sikkert om dem.
    #
    # VIKTIG (nettsok): AMD har FLERE GANGER solgt ekte Zen 2-silisium (CPUID Family 17h/23)
    # under bade "Ryzen 5000"- og "Ryzen 7000"-modellnumre i den mobile U/H-serien - til
    # forveksling like modellnumre som ekte Zen 3/Zen 4 i SAMME serie:
    #   - "Lucienne" (Ryzen 5 5500U, Ryzen 3 5300U, Ryzen 7 5700U m.fl.) = Zen 2, MEN markedsfort
    #     som "5000-serien" sammen med ekte Zen 3 "Cezanne" (5600U/5800U/5900HX osv.)
    #   - "Mendocino" (Ryzen 3 7320U, Ryzen 5 7520U m.fl.) = Zen 2, MEN markedsfort som
    #     "7000-serien" sammen med ekte Zen 3 "Barcelo-R" og ekte Zen 4 "Phoenix"
    # Modellnummeret ALENE (kun ">= 5000") er derfor IKKE til a stole pa for bærbare CPU-er -
    # det vil feilaktig godkjenne disse Zen 2-brikkene. Den faktiske silisium-generasjonen
    # (CPUID Family, lest fra WMI Description/Caption-strengen, f.eks. "AMD64 Family 25 Model
    # 80 Stepping 0") brukes derfor som den AVGJORENDE sjekken: Family 19h (25 desimalt) og
    # oppover = Zen 3/Zen 3+/Zen 4/Zen 5 = har Curve Optimizer. Family 17h (23 desimalt) og
    # under = Zen/Zen+/Zen 2 = har det IKKE, uansett modellnummer. Dette er IKKE testet pa ekte
    # AMD-maskinvare av Fiskum IT (utviklingsmaskinen er Intel) - det logges derfor alltid en
    # tydelig "CPUID Family"-verdi til Manager-loggen ved oppstart for etterprovbarhet, og det
    # finnes en bevisst, tydelig merket reserveløsning (kun modellnummer) hvis Family-tolkningen
    # av en eller annen grunn skulle vise seg feil i praksis.
    #
    # Merk ogsa: -30 vs -50-grensen er FORTSATT basert pa modellnummer (ikke Family/Model),
    # i likhet med motorens egen "[7-9]\d{3}"-sjekk - en sjelden ekte Zen 3-brikke markedsfort
    # i 7000-serien (f.eks. "Barcelo-R") kan derfor i teorien fa -50 i stedet for -30. Dette er
    # den samme antagelsen som motoren selv gjor, og er ikke noe Fiskum IT kan rette uten ogsa
    # a endre sp00n sin motorkode.
    #
    # Intel: bruker IntelVoltageControl.exe (CoreCycler\tools\IntelVoltageControl\, MSR 0x150)
    # for EN global spenningsforskyvning for hele CPU-en (pluss en lenket cache-plan) - IKKE
    # per kjerne som AMD. Verktoyets egen dokumentasjon bekrefter dette eksplisitt kun for
    # "Skylake og avledede" (ca. 6.-10. generasjon) - nyere hybrid-arkitekturer (Alder Lake+
    # med P-/E-kjerner) er UTENFOR det dokumentasjonen dekker. I tillegg later mange nyere
    # systemer (2021+) MSR 0x150-skriving i BIOS som sikring mot "Plundervolt"-svakheten -
    # dette kan IKKE oppdages av programvare i forveien, kun ved a faktisk prove. Det finnes
    # heller ingen kjent, dokumentert sikker minimumsverdi for Intel slik AMD har -30/-50
    # (se ogsa script-corecycler.ps1, som aktivt AVVISER "Minimum" for Intel)
    if ($Script:UndervoltStotteCache) {
        return $Script:UndervoltStotteCache
    }

    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuNavn = [string]$processor.Name
    $produsent = [string]$processor.Manufacturer

    $info = [pscustomobject]@{
        Vendor     = 'Ukjent'
        Stottet    = $false
        ConfigFil  = $null
        MinVerdi   = $null
        CpuNavn    = $cpuNavn.Trim()
        # Fiskum IT (v0.8.2): AMD-modellnummeret (f.eks. 7950 i "Ryzen 9 7950X3D"), brukt av
        # Activate-TestConfig til a velge riktig y-cruncher AVX512-modus (Zen4 vs Zen5) - se
        # YCRUNCHER_AVX512_1.ini. $null hvis ikke AMD eller modellnummeret ikke kunne leses
        AmdModellNummer = $null
        # Forklaring: fullversjon (logges ved oppstart, til feilsoking/diagnostikk)
        # KortStatus: forkortet ettlinjes-versjon (vises i "Modus"-panelet i UI'et)
        Forklaring = "Ukjent prosessorprodusent: $produsent"
        KortStatus = "Ukjent prosessorprodusent: $produsent"
    }

    if ($produsent -eq 'AuthenticAMD') {
        $info.Vendor = 'AMD'

        # Fiskum IT: ekte silisium-generasjon (CPUID Family, desimalt) - se researchnotatet
        # over. Family 19 (19h) og oppover = Zen 3+ = Curve Optimizer. $null = kunne ikke leses.
        $cpuFamily = $null
        if (([string]$processor.Description) -match 'Family\s+(\d+)' -or ([string]$processor.Caption) -match 'Family\s+(\d+)') {
            $cpuFamily = [int]$Matches[1]
        }
        Write-ManagerLog -Text "AMD CPUID Family lest fra WMI: $(if ($null -ne $cpuFamily) { $cpuFamily } else { 'KUNNE IKKE LESES' })"

        if ($cpuNavn -match 'Ryzen\s+\d\s+(?:PRO\s+)?(\d{4})([A-Z]*)') {
            $modellnummer = [int]$Matches[1]
            $suffiks      = [string]$Matches[2]
            $info.AmdModellNummer = $modellnummer
            $harZen3PlusFamily = $(if ($null -ne $cpuFamily) { $cpuFamily -ge 25 } else { $null })

            if ($harZen3PlusFamily -eq $true -or ($null -eq $harZen3PlusFamily -and $modellnummer -ge 5000)) {
                $info.Stottet    = $true
                $info.ConfigFil  = 'AssistedUndervolting_Ryzen.ini'
                $info.MinVerdi   = $(if ($modellnummer -ge 7000) { -50 } else { -30 })

                $usikkerhetNotat = $(if ($null -eq $cpuFamily) { ' - ADVARSEL: CPUID Family kunne ikke leses, sa dette er basert KUN pa modellnummer (se forbehold om mobile Zen 2-rebrands i AssistedUndervolting_Ryzen.ini)' } else { '' })
                $info.Forklaring = "AMD Ryzen $modellnummer$suffiks (CPUID Family $cpuFamily) - Curve Optimizer (minimum $($info.MinVerdi))$usikkerhetNotat"
                $info.KortStatus = "Curve Optimizer stottet (minimum $($info.MinVerdi))"
            }
            elseif ($harZen3PlusFamily -eq $false) {
                $info.Forklaring = "AMD Ryzen $modellnummer$suffiks er Zen 2 eller eldre (CPUID Family $cpuFamily) til tross for modellnummeret - AMD har solgt eldre Zen 2-silisium under bade 5000- og 7000-serienumre i den bærbare U/H-serien (f.eks. 'Lucienne'/'Mendocino'). Curve Optimizer er en Zen 3+ (Family 19/25 og nyere) funksjon"
                $info.KortStatus = "Zen 2 eller eldre (Family $cpuFamily) - ingen Curve Optimizer, uansett modellnummer"
            }
            else {
                $info.Forklaring = "AMD Ryzen $modellnummer$suffiks har ikke Curve Optimizer (kun Ryzen 5000-serien/Zen 3 og nyere har dette)"
                $info.KortStatus = "ingen Curve Optimizer (krever 5000-serien/Zen 3 eller nyere)"
            }
        }
        else {
            $info.Forklaring = 'Fant ikke et gjenkjennbart Ryzen-modellnummer for Curve Optimizer (krever Ryzen 5000-serien/Zen 3 eller nyere - Threadripper/EPYC/Athlon er ikke vurdert av denne funksjonen)'
            $info.KortStatus = 'ukjent modell - Curve Optimizer-stotte ikke vurdert'
        }
    }
    elseif ($produsent -eq 'GenuineIntel') {
        $info.Vendor = 'Intel'

        if ($cpuNavn -match 'Core\(TM\)\s+i[3579]-(\d{4,5})([A-Z]*)') {
            $modellSiffer = [string]$Matches[1]
            $suffiks      = [string]$Matches[2]

            # Fiskum IT: Intel sin nummerering er IKKE konsekvent - "4770"(4. gen)/"9700"(9. gen)
            # bruker forste siffer som generasjon, men fra 10. generasjon og oppover brukes ofte
            # FORSTE TO sifre selv i et 4-sifret nummer (f.eks. "1065G7" = 10. gen, "1265U" = 12.
            # gen, "1335U" = 13. gen) - IKKE "1. generasjon". Siden ingen reell i3/i5/i7/i9-CPU
            # bruker et 4-sifret modellnummer som begynner pa "1" for a bety "1.-3. generasjon"
            # (de brukte en helt annen 3-sifret navngiving den gangen), er "forste siffer er 1"
            # et trygt signal pa at det faktisk er de to forste sifrene som skal leses
            $generasjon = $(
                if ($modellSiffer.Length -eq 5) {
                    [int]$modellSiffer.Substring(0,2)
                }
                elseif ($modellSiffer.Substring(0,1) -eq '1') {
                    [int]$modellSiffer.Substring(0,2)
                }
                else {
                    [int]$modellSiffer.Substring(0,1)
                }
            )
            # Fiskum IT: U/Y/H/HX/G er baerbar-suffikser (G* er Ice Lake-mobilbrikker med
            # Iris Plus-iGPU-tier, f.eks. "G7" i "1065G7") - forskning (se
            # AssistedUndervolting_Intel.ini sin toppkommentar) viser at OEM-baerbare
            # generelt later spenningskontroll langt mer aggressivt enn entusiast-
            # stasjonaere hovedkort, uavhengig av generasjon
            $erBaerbar    = ($suffiks -match '^(U|Y|HX|H|G)')

            if ($generasjon -ge 4) {
                $info.Stottet    = $true
                $info.ConfigFil  = 'AssistedUndervolting_Intel.ini'
                $info.MinVerdi   = $null

                # Fiskum IT: tillitsniva per generasjon, basert pa nettsok (desember 2019
                # Plundervolt-avsloringen og folgende OEM/BIOS-respons over tid) - se den
                # fulle kildehenvisningen og resonnementet i AssistedUndervolting_Intel.ini
                $tillitNotat = $(
                    if ($generasjon -le 9) {
                        'historisk mest pålitelig generasjon for denne metoden (Haswell t.o.m. Coffee Lake) - men kan være låst på enkelte OEM-bærbare som har fått senere BIOS-oppdateringer mot Plundervolt-sikkerhetshullet'
                    }
                    elseif ($generasjon -eq 10) {
                        'Plundervolt-sikringer begynte å låse dette på mange bærbare fra denne generasjonen (Ice Lake/Comet Lake), spesielt OEM-modeller (Dell/HP/Lenovo m.fl.) - stasjonære modeller er mindre påvirket'
                    }
                    elseif ($generasjon -eq 11) {
                        'mobile Tiger Lake-modeller har ofte dette låst helt av Intel selv, uten mulighet til å låse opp - stasjonære Rocket Lake-hovedkort er mer åpne, men varierer per modell/BIOS'
                    }
                    elseif ($generasjon -ge 12 -and $generasjon -le 14) {
                        'varierer sterkt per hovedkort (Alder Lake/Raptor Lake) - mange entusiast Z-hovedkort holder dette åpent som standard ("CFG Lock"), men ikke alle. Vanligst i praksis i dag er BIOS-intern spenningsforskyvning (UEFI-oppsettet) i stedet for denne kjørende-Windows-metoden - prøv BIOS-innstillingene hvis denne metoden ikke fungerer'
                    }
                    else {
                        'for ny generasjon til at det finnes utbredt dokumentasjon om denne spesifikke metoden ennå - ingen garantier'
                    }
                )

                $enhetNotat    = $(if ($erBaerbar) { ' Bærbar/OEM-modell (suffiks "' + $suffiks + '") - disse er erfaringsmessig MER utsatt for låst spenningskontroll enn stasjonære.' } else { '' })
                $enhetTypeKort = $(if ($erBaerbar) { 'bærbar' } else { 'stasjonær' })

                $info.Forklaring = "Intel Core $generasjon. generasjon$(if ($erBaerbar) {' (baerbar)'} else {' (stasjonaer/ukjent)'}) - spenningsforskyvning via IntelVoltageControl. IKKE garantert å fungere - $tillitNotat.$enhetNotat"
                $info.KortStatus = "$generasjon. gen ($enhetTypeKort) - kan fungere, IKKE garantert (se logg/README)"
            }
            else {
                $info.Forklaring = "Intel Core $generasjon. generasjon er eldre enn det IntelVoltageControl støtter (4. generasjon Haswell og nyere)"
                $info.KortStatus = "$generasjon. gen - for gammel (krever 4. gen/Haswell eller nyere)"
            }
        }
        elseif ($cpuNavn -match 'Core\(TM\)\s+i[3579]') {
            # Gjenkjent som Core i3/i5/i7/i9, men kunne ikke lese ut et generasjonsnummer fra
            # navnet (uvanlig/OEM-spesifikt format) - tillater forsok, men uten garantier
            $info.Stottet    = $true
            $info.ConfigFil  = 'AssistedUndervolting_Intel.ini'
            $info.MinVerdi   = $null
            $info.Forklaring = 'Intel Core-CPU (ukjent generasjon) - spenningsforskyvning via IntelVoltageControl. IKKE garantert å fungere'
            $info.KortStatus = 'ukjent generasjon - kan fungere, IKKE garantert'
        }
        else {
            $info.Forklaring = 'Denne Intel-CPU-familien (ikke Core i3/i5/i7/i9) er ikke vurdert for spenningsforskyvning av denne funksjonen'
            $info.KortStatus = 'ikke Core i3/i5/i7/i9 - ikke vurdert'
        }
    }

    $Script:UndervoltStotteCache = $info

    return $Script:UndervoltStotteCache
}

function Get-AvansertValgFil {
    return (Join-Path $ConfigDir 'avansert-valg.json')
}

function Get-AvansertValg {
    # Fiskum IT: hvilke av de 21 testene i testplan.json som er aktive, og hvilken
    # varighet (minutter, eller "auto") som er valgt for hver - satt via "Avansert..."-dialogen
    # Tomt resultat = ingen overstyring, alle tester aktive med sin opprinnelige varighet
    $data = Read-JsonFile -Path (Get-AvansertValgFil)

    if (-not $data) {
        return @()
    }

    return @($data)
}

function Save-AvansertValg {
    param(
        [Parameter(Mandatory)]
        $Valg
    )

    Write-JsonFile -Path (Get-AvansertValgFil) -Object @($Valg)
}

function Get-StabilitetsPlan {
    # Vanlig stabilitetstest: testplan.json, filtrert av Avansert-valg (se Get-AvansertValg)
    # og av hvilke instruksjonssett denne CPU-en faktisk stotter (se Test-StottetAvCpu).
    # CPU-filteret gjelder alltid, uavhengig av Avansert-valg - en test CPU-en ikke kan
    # kjore skal aldri startes, selv om en gammel avansert-valg.json (f.eks. fra for et
    # CPU-bytte) skulle si "aktiv=true" for den
    $plan = Read-JsonFile -Path $PlanFile

    if (-not $plan) {
        return $plan
    }

    $plan = @($plan | Where-Object { Test-StottetAvCpu -Krav $_.kreverInstruksjonssett })

    # Fiskum IT: @() er kritisk her - Get-AvansertValg kan returnere et tomt eller
    # ett-elements array, og PowerShell "pakker ut" slike ved retur over pipelinen, slik
    # at $avansert ellers kan bli $null (tomt array) eller et enkelt objekt (ett element)
    $avansert = @(Get-AvansertValg)

    if ($avansert.Count -eq 0) {
        # Fiskum IT (v0.8.2): ingen avansert-valg.json finnes ennaa (frisk installasjon, eller
        # brukeren har aldri apnet "Avansert..."-dialogen) - bruk det kuraterte standardsettet
        # ("standardAnbefalt": true i testplan.json) i stedet for ALLE CPU-stottede tester.
        # Gir automatisk CPU-tilpasning gratis: samme instruksjonssett-filter over sorger for
        # at en gammel CPU uten AVX2 likevel far et fornuftig, ikke-tomt standardvalg. Sa snart
        # brukeren apner og lagrer "Avansert..." (selv uten endringer) tar DERES valg over her
        return @($plan | Where-Object { $_.standardAnbefalt -eq $true })
    }

    $avansertMap = @{}

    foreach ($entry in $avansert) {
        $avansertMap[[int]$entry.id] = $entry
    }

    return @($plan | Where-Object {
        $entry = $avansertMap[[int]$_.id]
        -not $entry -or $entry.aktiv -ne $false
    })
}

function Get-AssistertUndervoltingPlan {
    # Fiskum IT: "Assistert undervolting" er ikke en sekvens av flere tester, men en
    # enkelt, syntetisk "test" som peker til den AMD- eller Intel-spesifikke profilen,
    # avhengig av hva Get-UndervoltStotteInfo oppdager for denne CPU-en. Selve gra-
    # ut/blokkeringen av radioknappen (Build-Ui/Switch-Modus) hindrer normalt at denne
    # i det hele tatt kalles pa en ustottet CPU, men faller tilbake til Ryzen-profilen
    # (den opprinnelige, lengst proveded oppforselen) hvis stotte-info av noen grunn
    # ikke kan avgjores, i stedet for at funksjonen returnerer noe ubrukelig
    $stotte = Get-UndervoltStotteInfo
    $configFil = $(if ($stotte.Stottet -and $stotte.ConfigFil) { $stotte.ConfigFil } else { 'AssistedUndervolting_Ryzen.ini' })
    $navn = $(if ($stotte.Vendor -eq 'Intel') {
        'Assistert undervolting (global spenningsforskyvning, 0 -> grense)'
    } else {
        'Assistert undervolting (Curve Optimizer, 0 -> grense per kjerne)'
    })

    return @(
        [pscustomobject]@{
            id     = 1
            navn   = $navn
            config = $configFil
        }
    )
}

function Get-Plan {
    param(
        [string]$Modus = 'Stabilitet'
    )

    # Fiskum IT: @() er kritisk her - se kommentaren i Get-StabilitetsPlan om hvorfor et
    # tomt/ett-elements array ma pakkes inn igjen for ikke a "pakkes ut" over pipelinen
    if ($Modus -eq 'AssistertUndervolting') {
        return @(Get-AssistertUndervoltingPlan)
    }

    return @(Get-StabilitetsPlan)
}

function Get-CurrentTest {
    param(
        [Parameter(Mandatory)]
        $Plan,

        [Parameter(Mandatory)]
        $State
    )

    return $Plan | Where-Object { $_.id -eq $State.aktivTestId } | Select-Object -First 1
}

function Get-NextTest {
    param(
        [Parameter(Mandatory)]
        $Plan,

        [Parameter(Mandatory)]
        $State
    )

    # Fiskum IT: bruker "naermeste hoyere id", ikke "id + 1" - Get-StabilitetsPlan kan
    # fjerne deaktiverte tester (Avansert-valg) midt i rekken, og da finnes ikke
    # noedvendigvis "aktivTestId + 1" lenger i $Plan
    return $Plan |
        Where-Object { [int]$_.id -gt [int]$State.aktivTestId } |
        Sort-Object { [int]$_.id } |
        Select-Object -First 1
}

function Sync-AktivTestId {
    # Fiskum IT: garanterer at $State.aktivTestId faktisk finnes i $Plan. Trengs fordi
    # Avansert-valg (eller bytte av modus) kan fjerne/endre hvilke tester som er aktive,
    # og en tidligere lagret aktivTestId (f.eks. 1, default fra New-DefaultState) kan da
    # ha blitt deaktivert - uten denne synkroniseringen gir Get-CurrentTest ingen treff
    # ("Aktiv test: Ingen" / "Fant ingen aktiv test i testplanen")
    param(
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)] $Plan
    )

    if (@($Plan).Count -eq 0) {
        return
    }

    if (-not (Get-CurrentTest -Plan $Plan -State $State)) {
        $State.aktivTestId = [int]$Plan[0].id
    }
}

function Backup-CurrentCoreCyclerConfig {
    if (Test-Path -LiteralPath $CoreCyclerConfig) {
        $backupName = 'config_backup_{0}.ini' -f (Get-TimeStamp)
        $backupPath = Join-Path $BackupDir $backupName

        Copy-Item -LiteralPath $CoreCyclerConfig -Destination $backupPath -Force
    }
}

function Get-RuntimePerCoreOverrideString {
    param(
        [Parameter(Mandatory)]
        $Varighet
    )

    $v = [string]$Varighet

    if ([string]::IsNullOrWhiteSpace($v) -or $v.Trim().ToLowerInvariant() -eq 'auto') {
        return 'auto'
    }

    if ($v -match '^\s*\d+\s*$') {
        return ('{0}m' -f $v.Trim())
    }

    return $v
}

function Set-ConfigLine {
    # Fiskum IT: patcher (eller legger til, hvis den ikke finnes) en enkelt "key = value"-linje
    # i en gitt ini-seksjon, uten aa skrive om resten av filen. Brukes til aa overstyre
    # runtimePerCore (Avansert-valg) og startValues (krasjgjenoppretting).
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Section,
        [Parameter(Mandatory)] [string]$Key,
        [Parameter(Mandatory)] [string]$Value
    )

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $inSection = $false
    $patched = $false
    $sectionLineIndex = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^\s*\[(?<s>[^\]]+)\]\s*$') {
            $inSection = ($Matches['s'] -eq $Section)

            if ($inSection) {
                $sectionLineIndex = $i
            }

            continue
        }

        if ($inSection -and $line -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $lines[$i] = '{0} = {1}' -f $Key, $Value
            $patched = $true
        }
    }

    if (-not $patched) {
        if ($sectionLineIndex -ge 0) {
            $newLines = New-Object System.Collections.Generic.List[string]
            $newLines.AddRange([string[]] $lines[0..$sectionLineIndex])
            $newLines.Add('{0} = {1}' -f $Key, $Value)

            if ($sectionLineIndex + 1 -le $lines.Count - 1) {
                $newLines.AddRange([string[]] $lines[($sectionLineIndex + 1)..($lines.Count - 1)])
            }

            $lines = @($newLines)
        }
        else {
            $lines += ''
            $lines += ('[{0}]' -f $Section)
            $lines += ('{0} = {1}' -f $Key, $Value)
        }
    }

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Activate-TestConfig {
    param(
        [Parameter(Mandatory)]
        $Test,

        # Fiskum IT: satt naar denne testen startes som gjenopptak etter et krasj/stopp,
        # se Resolve-CrashedRun - da skal Assistert undervolting IKKE starte soket fra 0 paa nytt
        [switch]$ErGjenopptak
    )

    $source = Join-Path $ConfigDir $Test.config

    if (-not (Test-Path -LiteralPath $source)) {
        throw "Fant ikke konfigurasjonsfilen: $source"
    }

    Backup-CurrentCoreCyclerConfig
    Copy-Item -LiteralPath $source -Destination $CoreCyclerConfig -Force

    if ($App.State.modus -eq 'AssistertUndervolting') {
        if ($ErGjenopptak) {
            Set-ConfigLine -Path $CoreCyclerConfig -Section 'AutomaticTestMode' -Key 'startValues' -Value 'CurrentValues'
        }

        # Fiskum IT: skriver inn den faktiske, generasjonsriktige sikkerhetsgrensen for
        # DENNE CPU-en (f.eks. -50 for Ryzen 7000+ i stedet for filens egen -30-standard,
        # som kun er korrekt for Ryzen 5000/6000) - se Get-UndervoltStotteInfo. Kun for
        # AMD, siden Intel ikke har en kjent/dokumentert sikker grense a regne ut
        # (Intel-profilens egen konservative minValue-standard brukes derfor uendret)
        $stotte = Get-UndervoltStotteInfo

        if ($stotte.Vendor -eq 'AMD' -and $stotte.MinVerdi) {
            Set-ConfigLine -Path $CoreCyclerConfig -Section 'AutomaticTestMode' -Key 'minValue' -Value ([string]$stotte.MinVerdi)
            Write-ManagerLog -Text "Activate-TestConfig: satte generasjonsriktig minValue=$($stotte.MinVerdi) for $($stotte.CpuNavn)."
        }
    }
    else {
        # Vanlig stabilitetstest: overstyr varighet hvis valgt i "Avansert..."-dialogen
        $avansert = @(Get-AvansertValg)
        $entry = $avansert | Where-Object { [int]$_.id -eq [int]$Test.id } | Select-Object -First 1

        if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.varighet)) {
            $runtimeValue = Get-RuntimePerCoreOverrideString -Varighet $entry.varighet
            Set-ConfigLine -Path $CoreCyclerConfig -Section 'General' -Key 'runtimePerCore' -Value $runtimeValue
        }

        # Fiskum IT (v0.8.2): for AVX512-y-cruncher-tester, overstyr filens egen "mode = auto"
        # med en eksplisitt, bekreftet riktig modusstreng for AMD Zen4/Zen5 - gjenbruker
        # modellnummeret fra Get-UndervoltStotteInfo (samme kilde som minValue-patchingen
        # over for Assistert undervolting). Kun for AMD - se YCRUNCHER_AVX512_1.ini for
        # hvorfor "auto" er en trygg nok fallback for Intel/usikre tilfeller
        if ($Test.kreverInstruksjonssett -eq 'AVX512') {
            $stotte = Get-UndervoltStotteInfo

            if ($stotte.Vendor -eq 'AMD' -and $stotte.AmdModellNummer) {
                $ycruncherMode = $(
                    if ($stotte.AmdModellNummer -ge 9000) { '24-ZN5 ~ Komari' }
                    elseif ($stotte.AmdModellNummer -ge 7000) { '22-ZN4 ~ Kizuna' }
                    else { $null }
                )

                if ($ycruncherMode) {
                    Set-ConfigLine -Path $CoreCyclerConfig -Section 'yCruncher' -Key 'mode' -Value $ycruncherMode
                    Write-ManagerLog -Text "Activate-TestConfig: satte y-cruncher AVX512-modus til '$ycruncherMode' for $($stotte.CpuNavn)."
                }
            }
        }

        # Fiskum IT (v0.8.2): bekreftelsesrunde - bruk FASTE, margin-justerte verdier i stedet
        # for testens egen normale sok (kun for DENNE kjoringen, se Start-BekreftelsesRundePrompt
        # og fullfort-handteringen som nullstiller bekreftelseAktiv igjen etterpa)
        if ($App.State.bekreftelseAktiv -and -not [string]::IsNullOrWhiteSpace($App.State.bekreftelseOffsets)) {
            Set-ConfigLine -Path $CoreCyclerConfig -Section 'AutomaticTestMode' -Key 'enableAutomaticAdjustment' -Value '0'
            Set-ConfigLine -Path $CoreCyclerConfig -Section 'AutomaticTestMode' -Key 'startValues' -Value $App.State.bekreftelseOffsets
            Write-ManagerLog -Text "Activate-TestConfig: bekreftelsesrunde aktiv - satte faste startValues=$($App.State.bekreftelseOffsets) (enableAutomaticAdjustment=0)."
        }
    }
}

function Get-LatestCoreCyclerLogFile {
    if (-not (Test-Path -LiteralPath $CoreCyclerLogDir)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $CoreCyclerLogDir -Filter 'CoreCycler_*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Read-LastLines {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$Count = 60
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return Get-Content -LiteralPath $Path -Tail $Count -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-ChildProcessIds {
    param(
        [Parameter(Mandatory)]
        [int]$ParentProcessId
    )

    try {
        return Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentProcessId" |
            Select-Object -ExpandProperty ProcessId
    }
    catch {
        return @()
    }
}

function Stop-ProcessTree {
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId
    )

    $children = @(Get-ChildProcessIds -ParentProcessId $ProcessId)

    foreach ($childId in $children) {
        Stop-ProcessTree -ProcessId ([int]$childId)
    }

    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
    }
    catch {
    }
}

function Get-CoreCyclerProcessesFromFolder {
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    if (-not (Test-Path -LiteralPath $FolderPath)) {
        return @()
    }

    try {
        $resolved = (Resolve-Path -LiteralPath $FolderPath).Path.TrimEnd('\')
        $resolvedLower = $resolved.ToLowerInvariant()
    }
    catch {
        return @()
    }

    $currentPid = $PID
    $matchedProcs = @()

    try {
        $allProcesses = Get-CimInstance Win32_Process

        foreach ($proc in $allProcesses) {
            if ($null -eq $proc.ProcessId) {
                continue
            }

            if ([int]$proc.ProcessId -eq [int]$currentPid) {
                continue
            }

            $exeMatch = $false
            $cmdMatch = $false

            if (-not [string]::IsNullOrWhiteSpace($proc.ExecutablePath)) {
                $exePathLower = ([string]$proc.ExecutablePath).ToLowerInvariant()

                if ($exePathLower.StartsWith($resolvedLower)) {
                    $exeMatch = $true
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($proc.CommandLine)) {
                $cmdLineLower = ([string]$proc.CommandLine).ToLowerInvariant()

                if ($cmdLineLower.Contains($resolvedLower)) {
                    $cmdMatch = $true
                }
            }

            if ($exeMatch -or $cmdMatch) {
                $matchedProcs += $proc
            }
        }

        return @($matchedProcs)
    }
    catch {
        return @()
    }
}

function Stop-CoreCyclerProcessesFromFolder {
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    $procs = @(Get-CoreCyclerProcessesFromFolder -FolderPath $FolderPath)

    foreach ($p in $procs) {
        try {
            Stop-ProcessTree -ProcessId ([int]$p.ProcessId)
        }
        catch {
        }
    }
}

function Check-StaleCoreCyclerProcessesOnStartup {
    param(
        [Parameter(Mandatory)]
        $State
    )

    $procs = @(Get-CoreCyclerProcessesFromFolder -FolderPath $CoreCyclerDir)

    if ($procs.Count -eq 0) {
        return
    }

    $msg = @"
Det ser ut som CoreCycler eller en testprosess fortsatt kjører fra CoreCycler-mappen.

Antall prosesser funnet: $($procs.Count)

Dette kan låse CoreCycler-mappen og hindre manageren i å starte riktig.

Vil du stoppe disse prosessene nå?
"@

    $result = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        'Fiskum IT CoreCycler Manager',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Stop-CoreCyclerProcessesFromFolder -FolderPath $CoreCyclerDir

        $State.aktivProsessId = $null
        $State.status = 'Stoppet'
        $State.sisteHendelse = 'Gjenværende CoreCycler-prosesser ble stoppet ved oppstart.'

        Add-History -State $State -Message $State.sisteHendelse
        Save-State -State $State
    }
    else {
        $State.sisteHendelse = 'Gjenværende CoreCycler-prosesser ble funnet ved oppstart, men ikke stoppet.'
        Add-History -State $State -Message $State.sisteHendelse
        Save-State -State $State
    }
}

function Get-CoreStatusFromLog {
    param(
        [string[]]$Lines
    )

    if (-not $Lines) {
        return ''
    }

    $matchLine = $Lines |
        Where-Object { $_ -match 'Set to Core\s+(\d+)\s+\(CPU\s+(\d+)\)' } |
        Select-Object -Last 1

    if ($matchLine -and $matchLine -match 'Set to Core\s+(\d+)\s+\(CPU\s+(\d+)\)') {
        return "Aktiv kjerne: Core $($Matches[1]) (CPU $($Matches[2]))"
    }

    return ''
}

function Get-LatestOffsetFromLog {
    param(
        [string[]]$Lines
    )

    if (-not $Lines) {
        return ''
    }

    $patterns = @(
        'Curve Optimizer[^\-\d]*(?<val>-?\d+)',
        'voltage offset[^\-\d]*(?<val>-?\d+)',
        'offset[^\-\d]*(?<val>-?\d+)'
    )

    $recentLines = @($Lines | Select-Object -Last 200)

    for ($i = $recentLines.Count - 1; $i -ge 0; $i--) {
        $line = [string]$recentLines[$i]

        foreach ($p in $patterns) {
            if ($line -match $p) {
                return $Matches['val']
            }
        }
    }

    return ''
}

function Format-OffsetRekke {
    # Fiskum IT: -ErGlobalVerdi brukes for Intel (IntelVoltageControl) - der finnes det
    # bare EN reell spenningsforskyvning for hele CPU-en, ikke en uavhengig verdi per
    # kjerne som for AMD Curve Optimizer. "Core 0: -50" ville feilaktig antydet
    # per-kjerne-granularitet som ikke finnes - "Alle kjerner: -50" er korrekt
    param(
        $CoreOffsets,
        [switch]$ErGlobalVerdi
    )

    if ($null -eq $CoreOffsets) {
        return 'Ingen Curve Optimizer-verdier registrert enda'
    }

    $names = @(Get-PropertyNames -Object $CoreOffsets)

    if ($names.Count -eq 0) {
        return 'Ingen Curve Optimizer-verdier registrert enda'
    }

    if ($ErGlobalVerdi) {
        $forsteNavn = ($names | Sort-Object { [int]$_ })[0]
        return ('Alle kjerner (global spenningsforskyvning): {0}' -f $CoreOffsets.$forsteNavn)
    }

    $sorted = $names | Sort-Object { [int]$_ }
    $parts = @()

    foreach ($n in $sorted) {
        $v = $CoreOffsets.$n
        $parts += ('Core {0}: {1}' -f $n, $v)
    }

    return ($parts -join '  |  ')
}

function Update-CurveOptimizerStateFromLog {
    param(
        [string[]]$Lines
    )

    if (-not $Lines) {
        return $false
    }

    if ($null -eq $App.State.coreOffsets) {
        $App.State.coreOffsets = [pscustomobject]@{}
    }

    $changed = $false

    foreach ($line in $Lines) {
        $text = [string]$line

        # Fiskum IT-fiks: dette er den faktiske teksten motoren skriver (script-corecycler.ps1,
        # Test-AutomaticTestModeIncrease/Decrease), f.eks.:
        #   "Modifying the Curve Optimizer value for core 3 from -10 to -9"   (Ryzen, per kjerne)
        #   "Modifying the voltage offset value from -50mv to -45mv"          (Intel, global)
        # Den gamle regex-en her ("The New Curve Optimizer Value for Core...") matchet aldri noe.
        if ($text -match 'Modifying the (?:Curve Optimizer|voltage offset) value(?:\s+for\s+core\s+(?<core>\d+))?\s+from\s+-?\d+m?v?\s+to\s+(?<val>-?\d+)m?v?') {
            $val = [int]$Matches['val']

            $coresToUpdate = @()

            if ($Matches['core']) {
                $coresToUpdate += $Matches['core']
            }
            else {
                # Intel: gjelder alle kjerner (motoren har bare en global verdi)
                $coresToUpdate += @(Get-PropertyNames -Object $App.State.coreOffsets)
            }

            foreach ($core in $coresToUpdate) {
                $existing = $null

                if ((Get-PropertyNames -Object $App.State.coreOffsets) -contains $core) {
                    $existing = $App.State.coreOffsets.$core
                }

                if ($null -eq $existing -or [int]$existing -ne $val) {
                    if ((Get-PropertyNames -Object $App.State.coreOffsets) -contains $core) {
                        $App.State.coreOffsets.$core = $val
                    }
                    else {
                        $App.State.coreOffsets | Add-Member -MemberType NoteProperty -Name $core -Value $val -Force
                    }

                    $changed = $true
                }
            }
        }
    }

    if ($changed) {
        $App.State.offsetRekke = Format-OffsetRekke -CoreOffsets $App.State.coreOffsets -ErGlobalVerdi:((Get-UndervoltStotteInfo).Vendor -eq 'Intel')
        $App.State.sisteRapporterteOffset = $App.State.offsetRekke
    }

    return $changed
}

function Mirror-CoreCyclerLogLines {
    param(
        [string[]]$Lines
    )

    if (-not $Lines) {
        return @()
    }

    $mirrored = New-Object System.Collections.Generic.List[string]

    foreach ($line in $Lines) {
        $text = ([string]$line).Trim()

        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $isInteresting = $false

        if ($text -match 'Set to Core\s+\d+') { $isInteresting = $true }
        elseif ($text -match 'Modifying the (Curve Optimizer|voltage offset) value') { $isInteresting = $true }
        elseif ($text -match 'Finished testing Core\s+\d+\s+\(CPU\s+\d+\)') { $isInteresting = $true }
        elseif ($text -match 'This core passed without error, decreasing the (?:Curve Optimizer|voltage offset) value') { $isInteresting = $true }

        if (-not $isInteresting) { continue }

        $hash = $text

        if ($App.MirroredLogLines.ContainsKey($hash)) {
            continue
        }

        $App.MirroredLogLines[$hash] = $true
        $mirrored.Add($text)

        Write-ManagerLog -Text ("CoreCycler: {0}" -f $text)
    }

    # Limit memory growth
    if ($App.MirroredLogLines.Count -gt 5000) {
        $App.MirroredLogLines.Clear()
    }

    return @($mirrored)
}

function Write-DesktopLog {
    # Fiskum IT: IKKE [Parameter(Mandatory)] her - for en [string[]]-parameter legger PowerShell
    # da implisitt til en valideringsregel som forkaster HVERT ELEMENT som er en tom streng, ikke
    # bare hvis HELE arrayen er tom. Siden $Lines her ALLTID inneholder minst en tom streng for
    # tom-linje-mellomrom (se Write-DesktopSnapshot/Write-SluttRapport), feilet ethvert reelt kall
    # med "Cannot bind argument to parameter 'Lines' because it is an empty string" - selve
    # skrivingen til skrivebordsloggen har dermed ALDRI fungert. Tom/manglende input handteres
    # allerede eksplisitt rett under, sa Mandatory ga ingen reell beskyttelse uansett
    param(
        [string[]]$Lines
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return
    }

    $normalized = @()
    foreach ($line in $Lines) {
        if ($null -ne $line) {
            $normalized += [string]$line
        }
    }

    if ($normalized.Count -eq 0) {
        return
    }

    try {
        $desktopFolder = Split-Path -Parent $DesktopLog

        if ($desktopFolder -and -not (Test-Path -LiteralPath $desktopFolder)) {
            New-Item -ItemType Directory -Path $desktopFolder -Force | Out-Null
        }

        Add-Content -LiteralPath $DesktopLog -Value $normalized -Encoding UTF8
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke skrive til skrivebordsloggen: $($_.Exception.Message)"
    }
}

function Write-DesktopSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$Reason,

        [string]$CoreStatus = '',

        # Fiskum IT: vis hele per-kjerne-tabellen - kun ved viktige hendelser (test
        # startet/stoppet/avsluttet), ikke ved hver lopende offset-endring. Holder
        # skrivebordsloggen kort og lett a lese for hvermansen
        [switch]$VisDetaljer
    )

    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $separator = '-' * 78
        $entries = New-Object System.Collections.Generic.List[string]

        $entries.Add($separator)
        $entries.Add("Tidspunkt: $timestamp")
        $entries.Add("Aarsak: $Reason")

        if (-not [string]::IsNullOrWhiteSpace($CoreStatus)) {
            $entries.Add("Kjerne: $CoreStatus")
        }
        elseif ($App -and $App.State) {
            # Fiskum IT: "??" (null-coalescing) finnes ikke i Windows PowerShell 5.1 - bruk $(if...)
            $coreStatusText = [string]$(if ($null -ne $App.State.coreStatus) { $App.State.coreStatus } else { 'Ikke registrert' })
            if ([string]::IsNullOrWhiteSpace($coreStatusText)) {
                $coreStatusText = 'Ikke registrert'
            }
            $entries.Add("Kjerne: $coreStatusText")
        }
        else {
            $entries.Add("Kjerne: Ikke registrert")
        }

        if ($App -and $App.State -and $App.State.offsetRekke) {
            $offsetText = [string]$App.State.offsetRekke
            if (-not [string]::IsNullOrWhiteSpace($offsetText)) {
                $entries.Add("Offset-rekke: $offsetText")
            }
        }

        # Fiskum IT: egen try/catch her - sett pa WANJA-GAMER (v0.8) at denne blokken kunne
        # feile med "The property 'Name' cannot be found on this object" (arsak ikke fullt
        # rotfestet - mistenkt en uventet form pa coreOffsets/laasteKjerner etter en JSON-
        # rundtur via state.json, men kunne ikke reproduseres med sikkerhet i etterkant).
        # En feil her skal IKKE hindre resten av oygeblikksbildet (tidspunkt/aarsak/offset-
        # rekke over) fra a bli skrevet - se ogsa Collect-FiskumITDiagnostics.ps1, som na
        # ogsaa tar med state.json, slik at et eventuelt nytt tilfelle kan rotfestes fullt ut
        if ($VisDetaljer -and $App -and $App.State -and $App.State.coreOffsets -and @($App.State.coreOffsets.PSObject.Properties).Count -gt 0) {
            try {
                $entries.Add('')
                $entries.Add('Per kjerne:')

                $laaste = @(Get-PropertyNames -Object $App.State.laasteKjerner)

                foreach ($prop in ($App.State.coreOffsets.PSObject.Properties | Sort-Object { [int]$_.Name })) {
                    $statusTekst = $(if ($laaste -contains $prop.Name) { 'låst' } else { 'under søk' })
                    $entries.Add(("  Core {0}: {1,4}  ({2})" -f $prop.Name, $prop.Value, $statusTekst))
                }
            }
            catch {
                Write-ManagerLog -Text ("Kunne ikke bygge per-kjerne-detaljer til skrivebordslogg: $($_.Exception.Message) " + `
                    "(coreOffsets-type: $($App.State.coreOffsets.GetType().FullName), laasteKjerner-type: " + `
                    "$(if ($null -ne $App.State.laasteKjerner) { $App.State.laasteKjerner.GetType().FullName } else { 'null' }))")
            }
        }

        $entries.Add('')

        if ($entries.Count -gt 0) {
            Write-DesktopLog -Lines @($entries)
        }
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke skrive snapshot til skrivebordslogg: $($_.Exception.Message)"
    }
}

function Get-AnbefaltMargin {
    # Fiskum IT (v0.8.2): isolert, rent (testbar) - all logikk for hvor stor sikkerhetsmargin
    # Write-SluttRapport skal trekke fra de funne verdiene. Flyttet ut av Write-SluttRapport
    # selv for a kunne testes uavhengig av faktisk filskriving (se Manager\Tests).
    #
    # CPU-delen: ikke en universell konstant - se Get-UndervoltStotteInfo for vendor/modell-
    # deteksjon. AMD Ryzen 7000-serien og nyere har et videre Curve Optimizer-omraade (-50 mot
    # -30 for 5000/6000-serien) og far derfor en litt storre margin. Intel sin spenningskontroll
    # har INGEN kjent/dokumentert sikker grense i utgangspunktet (se samme funksjon sin egen
    # dokumentasjon av dette) - far derfor den mest konservative margin av de tre. Dette er
    # Fiskum IT sin egen, forklarte tommelfingerregel - IKKE en offisiell AMD- eller Intel-verdi.
    # Juster selv ved behov, eller ved erfaring fra egne tester.
    #
    # Rigor-delen: motoren sporer ikke antall iterasjoner/forsok per kjerne noe sted Manageren
    # kan lese - en presis "hvor grundig ble dette" finnes derfor ikke. Bruker i stedet en grov,
    # aerlig proxy (total forlopt tid for soket / antall testede kjerner) - under terskelen
    # tyder pa et uvanlig raskt/lite grundig sok, far en ekstra margin som forsiktighetsregel
    param(
        [Parameter(Mandatory)]
        $Stotte,

        # -1 = ukjent/ikke beregnet (f.eks. assistertSokStartTid mangler) - ingen rigor-justering
        [double]$GjennomsnittMinutterPerKjerne = -1
    )

    $margin = 5
    $forklaring = 'standard sikkerhetsmargin'

    if ($Stotte.Vendor -eq 'AMD') {
        if ($null -ne $Stotte.MinVerdi -and $Stotte.MinVerdi -le -50) {
            $margin = 7
            $forklaring = 'AMD Ryzen 7000-serien og nyere har et videre Curve Optimizer-omraade (-50) - litt storre margin enn 5000/6000-serien'
        }
        else {
            $margin = 5
            $forklaring = 'AMD Ryzen 5000/6000-serien (Curve Optimizer-omraade -30)'
        }
    }
    elseif ($Stotte.Vendor -eq 'Intel') {
        $margin = 10
        $forklaring = 'Intel sin spenningskontroll har ingen kjent/dokumentert sikker grense (i motsetning til AMD) - storre margin som forsiktighetsregel'
    }

    $raskTerskelMinutter = 8
    $raskTillegg = 2

    if ($GjennomsnittMinutterPerKjerne -ge 0 -and $GjennomsnittMinutterPerKjerne -lt $raskTerskelMinutter) {
        $margin += $raskTillegg
        $forklaring += (" + {0} ekstra siden soket gikk uvanlig raskt (snitt {1} min/kjerne, under {2}-min-terskelen) - kan tyde pa at ikke alle stegene fikk god nok tid til a feile" -f $raskTillegg, [Math]::Round($GjennomsnittMinutterPerKjerne, 1), $raskTerskelMinutter)
    }

    return [pscustomobject]@{
        Margin     = $margin
        Forklaring = $forklaring
    }
}

function Write-SluttRapport {
    param(
        [Parameter(Mandatory)]
        $State
    )

    if (-not $State.coreOffsets -or @($State.coreOffsets.PSObject.Properties).Count -eq 0) {
        return
    }

    try {
        $sorted = @($State.coreOffsets.PSObject.Properties | Sort-Object { [int]$_.Name })

        if ($sorted.Count -eq 0) {
            return
        }

        $stotte = Get-UndervoltStotteInfo

        # Fiskum IT (v0.8.2): se Get-AnbefaltMargin - grov proxy for "hvor grundig var soket"
        $gjennomsnittMinutter = -1.0

        if (-not [string]::IsNullOrWhiteSpace($State.assistertSokStartTid)) {
            try {
                $startTid = [DateTime]::Parse($State.assistertSokStartTid, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $forlopt = (Get-Date) - $startTid

                if ($forlopt.TotalMinutes -gt 0) {
                    $gjennomsnittMinutter = $forlopt.TotalMinutes / $sorted.Count
                }
            }
            catch {
                Write-ManagerLog -Text "Kunne ikke beregne sok-varighet for sluttrapporten: $($_.Exception.Message)"
            }
        }

        $anbefaling = Get-AnbefaltMargin -Stotte $stotte -GjennomsnittMinutterPerKjerne $gjennomsnittMinutter
        $margin = $anbefaling.Margin
        $marginForklaring = $anbefaling.Forklaring

        $entries = New-Object System.Collections.Generic.List[string]
        $linje = '=' * 78

        $entries.Add($linje)
        $entries.Add('TEST FULLFØRT - oppsummering av Curve Optimizer-verdiene')
        $entries.Add($linje)
        $entries.Add('')
        $entries.Add("CPU: $($stotte.CpuNavn) ($($stotte.Vendor))")
        $entries.Add('')
        $entries.Add('Verdier som ble funnet (grensen testen faktisk klarte):')

        foreach ($prop in $sorted) {
            $entries.Add(("  Core {0}: {1}" -f $prop.Name, $prop.Value))
        }

        $entries.Add('')
        $entries.Add("Anbefalt for ekstra stabilitet ($margin mindre aggressiv enn over, per kjerne - $marginForklaring):")

        # Fiskum IT (v0.8.2): samles ogsa strukturert for a kunne tilbys som bekreftelsesrunde
        # (se Start-BekreftelsesRundePrompt) - returneres pa slutten av denne funksjonen
        $anbefalteVerdier = New-Object System.Collections.Generic.List[pscustomobject]

        foreach ($prop in $sorted) {
            # Fiskum IT: "mindre aggressiv" betyr naermere 0 - aldri over 0 (ingen overvolting)
            $anbefalt = [Math]::Min(0, [int]$prop.Value + $margin)
            $entries.Add(("  Core {0}: {1}" -f $prop.Name, $anbefalt))
            $anbefalteVerdier.Add([pscustomobject]@{ Core = [int]$prop.Name; Verdi = $anbefalt })
        }

        $entries.Add('')
        $entries.Add($linje)
        $entries.Add('')

        # Fiskum IT (v0.8.2): overskriver (IKKE tilfoyer) skrivebordsloggen her - filen skal
        # KUN inneholde resultatene fra siste fullforte test na, ikke hele historikken av
        # lopende oyeblikksbilder skrevet til samme fil underveis i kjoringen (se
        # Write-DesktopSnapshot/Maybe-LogDesktopSnapshot, som bruker Write-DesktopLog sin
        # Add-Content - fortsatt riktig oppforsel for DEM, kun selve sluttrapporten skal
        # "rydde opp" og sta for seg selv)
        $desktopFolder = Split-Path -Parent $DesktopLog

        if ($desktopFolder -and -not (Test-Path -LiteralPath $desktopFolder)) {
            New-Item -ItemType Directory -Path $desktopFolder -Force | Out-Null
        }

        Set-Content -LiteralPath $DesktopLog -Value $entries -Encoding UTF8

        # Fiskum IT (v0.8.2): arkiver SAMME innhold som en tidsstemplet kopi i Manager\logs -
        # skrivebordsfilen overskrives ved hver fullforte test (med vilje, se over), men da
        # forsvinner forrige kjorings resultater helt uten denne arkiveringen
        try {
            $arkivFil = Join-Path $ManagerLogDir ('Sluttrapport_{0}.txt' -f (Get-TimeStamp))
            Set-Content -LiteralPath $arkivFil -Value $entries -Encoding UTF8
        }
        catch {
            Write-ManagerLog -Text "Kunne ikke arkivere sluttrapport til Manager\logs: $($_.Exception.Message)"
        }

        return [pscustomobject]@{
            Margin           = $margin
            Forklaring       = $marginForklaring
            AnbefalteVerdier = @($anbefalteVerdier)
        }
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke skrive sluttrapport til skrivebordsloggen: $($_.Exception.Message)"
    }
}

function Show-TestFullfortVarsel {
    # Fiskum IT: varsler brukeren synlig nar en hel testplan/sok er fullfort (samme
    # $varFullfort-tidspunkt som Write-SluttRapport kalles fra) - tidligere ble en fullfort
    # "Vanlig stabilitetstest" KUN logget, ingen synlig varsling i UI'et
    param(
        $SluttrapportInfo
    )

    if ($SluttrapportInfo -and $SluttrapportInfo.AnbefalteVerdier -and @($SluttrapportInfo.AnbefalteVerdier).Count -gt 0) {
        $resultatTekst = "Anbefalt sikkerhetsmargin: $($SluttrapportInfo.Margin) ($($SluttrapportInfo.Forklaring))"
    }
    else {
        $resultatTekst = 'Se rapporten for detaljer om resultatet.'
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Testen er fullført.`r`n`r`n$resultatTekst`r`n`r`nFullstendig rapport (skrivebordet): $DesktopLog",
        'Fiskum IT CoreCycler Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Start-BekreftelsesRundePrompt {
    # Fiskum IT (v0.8.2): tilbys etter en fullfort Assistert undervolting-sok (IKKE etter en
    # bekreftelsesrunde selv - se kallsstedet). Ved Ja: kjorer "Vanlig stabilitetstest" en gang
    # til, men med de FASTE (margin-justerte) verdiene i stedet for et nytt sok - se
    # Activate-TestConfig sin bekreftelseAktiv-grein
    param(
        # Fiskum IT: IKKE Mandatory - Write-SluttRapport (kallsstedet) returnerer $null bade
        # ved en tom coreOffsets og ved en feil i sin egen try/catch, og $null ville feilet
        # parameterbindingen her hvis dette var Mandatory
        $SluttrapportInfo
    )

    if (-not $SluttrapportInfo -or -not $SluttrapportInfo.AnbefalteVerdier -or @($SluttrapportInfo.AnbefalteVerdier).Count -eq 0) {
        return
    }

    $verdier = @($SluttrapportInfo.AnbefalteVerdier | Sort-Object Core)

    # Fiskum IT (v0.8.2): KRITISK - startValues er en posisjonsbasert liste (kjerne 0, 1, 2, ...)
    # i selve motoren (se config.ini sin egen dokumentasjon av dette). Hvis coreOffsets har
    # "hull" (ikke alle kjerner 0..N-1 representert, f.eks. etter en avbrutt sok-sesjon), ville
    # en sammenhengende streng av BARE de funne verdiene forskyve alt til feil kjerne. Avbryt i
    # stedet for a risikere det
    for ($i = 0; $i -lt $verdier.Count; $i++) {
        if ($verdier[$i].Core -ne $i) {
            Write-ManagerLog -Text "Bekreftelsesrunde ikke tilbudt: coreOffsets har hull (forventet kjerne $i, fant $($verdier[$i].Core)) - kan ikke bygge en trygg startValues-rekkefolge."
            return
        }
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "Vil du bekrefte de anbefalte verdiene (margin: $($SluttrapportInfo.Margin)) med en lengre stabilitetstest uten søk?`r`n`r`nDette kjører ""Vanlig stabilitetstest"" med de FASTE anbefalte verdiene (ikke et nytt søk), for å bekrefte at de er stabile.",
        'Fiskum IT CoreCycler Manager - bekreftelsesrunde',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    # Fiskum IT (v0.8.2): KRITISK - motoren foretrekker ALLTID en eksisterende offset-snapshot
    # over startValues hvis en finnes (samme grunn/monster som "Nullstill state" lenger ned i
    # filen) - uten denne ville bekreftelsesrunden stille kjort med de ORIGINALE (mer
    # aggressive, ikke margin-justerte) funnene i stedet for de trygge verdiene vi nettopp
    # bekreftet til brukeren
    $snapshotPath = Join-Path $CoreCyclerLogDir 'fiskumit-offset-snapshot.json'
    if (Test-Path -LiteralPath $snapshotPath) {
        Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
    }

    $App.State.bekreftelseOffsets = ($verdier | ForEach-Object { $_.Verdi }) -join ', '
    $App.State.bekreftelseAktiv = $true

    [void](Switch-Modus -NyModus 'Stabilitet')

    if ($App.Ui.radioStabilitet) {
        $App.Ui.radioStabilitet.Checked = $true
    }

    Save-State -State $App.State

    Write-ManagerLog -Text "Bekreftelsesrunde startet med faste verdier: $($App.State.bekreftelseOffsets)"
}

function Maybe-LogDesktopSnapshot {
    param(
        [string[]]$MirroredLines = @()
    )

    $currentCore = $App.State.coreStatus
    $currentOffset = $App.State.offsetRekke

    $coreChanged = $false
    $offsetChanged = $false

    if ($currentCore -and $App.LastLoggedCoreStatus -ne $currentCore) {
        $coreChanged = $true
    }

    if ($currentOffset -and $App.LastLoggedOffset -ne $currentOffset) {
        $offsetChanged = $true
    }

    if ($coreChanged -or $offsetChanged -or ($MirroredLines -and $MirroredLines.Count -gt 0)) {
        $reasonParts = @()

        if ($coreChanged) { $reasonParts += 'Kjerneskifte oppdaget' }
        if ($offsetChanged) { $reasonParts += 'Curve Optimizer-verdi endret' }
        if ($MirroredLines -and $MirroredLines.Count -gt 0 -and -not $coreChanged -and -not $offsetChanged) {
            $reasonParts += 'Nye CoreCycler-meldinger'
        }

        Write-DesktopSnapshot `
            -Reason (($reasonParts -join ' + ')) `
            -CoreStatus $currentCore

        $App.LastLoggedCoreStatus = $currentCore
        $App.LastLoggedOffset = $currentOffset
    }
}

function Test-LogIndicatesFatal {
    param(
        [string[]]$Lines
    )

    if (-not $Lines) {
        return $false
    }

    $joined = $Lines -join "`n"

    return (
        $joined -match 'FATAL ERROR' -or
        $joined -match 'all of the cores have thrown an error'
    )
}

function Test-LogIndicatesSuccessfulCompletion {
    param(
        [string[]]$Lines
    )

    if (-not $Lines) {
        return $false
    }

    $joined = $Lines -join "`n"

    return (
        $joined -match 'Finished testing Core\s+\d+\s+\(CPU\s+\d+\)' -or
        $joined -match 'All tests have been run for this core' -or
        $joined -match 'Test completed in\s+\d{2}h\s+\d{2}m\s+\d{2}s'
    )
}

function Get-CompletedRoundCount {
    param(
        [Parameter(Mandatory)]
        $Plan,

        [Parameter(Mandatory)]
        $State
    )

    if ($State.status -eq 'Fullført') {
        return $Plan.Count
    }

    $count = 0

    if ([int]$State.sisteFullforteTestId -gt 0) {
        $count = [int]$State.sisteFullforteTestId
    }

    return $count
}

function Write-DesktopStatusReport {
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        $Plan
    )

    # Beholdt for kompatibilitet. All skrivebordslogging skjer nå i én fil ($DesktopLog).
    # Vi skriver kun et kort statusbanner én gang per kjøring (når filen ikke finnes ennå).
    if (Test-Path -LiteralPath $DesktopLog) {
        return
    }

    $banner = @(
        '================================================================================',
        'Fiskum IT - CoreCycler Manager - samlet logg',
        ('Opprettet: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        ('State-fil: {0}' -f $StateFile),
        '================================================================================',
        ''
    )

    $banner | Set-Content -LiteralPath $DesktopLog -Encoding UTF8
}

function Start-CoreCyclerStep {
    param(
        [Parameter(Mandatory)]
        $Test,

        [Parameter(Mandatory)]
        $State,

        # Fiskum IT: sant nar dette er et gjenopptak (etter krasj/stopp/avslutning) av en
        # allerede paabegynt Assistert undervolting-sesjon, ikke en helt ny sok-sesjon
        [switch]$ErGjenopptak
    )

    Activate-TestConfig -Test $Test -ErGjenopptak:$ErGjenopptak

    $State.status = 'Kjører'
    $State.sisteHendelse = "Starter test: $($Test.navn)"
    $State.aktivTestStart = Get-NowIso

    Add-History -State $State -Message $State.sisteHendelse
    Save-State -State $State

    $psArgs = @(
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"{0}"' -f $CoreCyclerScript)
    )

    # Fiskum IT: kjores skjult - selve CoreCycler-konsollen er ikke ment a vises lenger,
    # innholdet dens speiles i stedet inn i "Siste CoreCycler-logg" i Manager-UI'et (se
    # Refresh-CoreCyclerLogView/Get-KonsollEkvivalenteLinjer)
    $proc = Start-Process -FilePath 'powershell.exe' `
                          -ArgumentList ($psArgs -join ' ') `
                          -WorkingDirectory $CoreCyclerDir `
                          -WindowStyle Hidden `
                          -PassThru

    $State.aktivProsessId = $proc.Id

    if ($State.modus -eq 'AssistertUndervolting') {
        $State.assistertSokStartet = $true

        # Fiskum IT (v0.8.2): kun ved en helt ny sok-sesjon (ikke et gjenopptak) - se
        # Get-AnbefaltMargin/Write-SluttRapport. $ErGjenopptak er den autoritative kilden
        # her (samme switch Activate-TestConfig over allerede bruker), ikke den GAMLE
        # verdien av assistertSokStartet (som pa dette punktet allerede er satt til $true)
        if (-not $ErGjenopptak -and [string]::IsNullOrWhiteSpace($State.assistertSokStartTid)) {
            $State.assistertSokStartTid = Get-NowIso
        }
    }

    Save-State -State $State

    # Fiskum IT: sa lenge en test er aktiv, skal Manageren kunne starte seg selv igjen ved
    # innlogging etter en eventuell krasj - se Resolve-CrashedRun. Betinget av v0.8.2 sin
    # nye "Autostart"-checkbox (Build-Ui) - default AV, null oppforingsendring uten den
    if ($State.autostartTask) {
        Add-ManagerAutoStartTask
    }

    Write-DesktopSnapshot `
        -Reason "Test startet: $($Test.navn)" `
        -CoreStatus $State.coreStatus `
        -VisDetaljer

    return $proc
}

function Stop-CoreCyclerStep {
    param(
        [Parameter(Mandatory)]
        $State
    )

    Write-ManagerLog -Text "Stoppsignal mottatt. Forsøker å stoppe CoreCycler og underprosesser."

    if ($State.aktivProsessId) {
        try {
            Stop-ProcessTree -ProcessId ([int]$State.aktivProsessId)
            Write-ManagerLog -Text "Stoppet prosesstre med rot-PID $($State.aktivProsessId)."
        }
        catch {
            Write-ManagerLog -Text "Klarte ikke stoppe prosesstre for PID $($State.aktivProsessId): $($_.Exception.Message)"
        }
    }

    Start-Sleep -Milliseconds 500

    try {
        Stop-CoreCyclerProcessesFromFolder -FolderPath $CoreCyclerDir
        Write-ManagerLog -Text "Ryddet opp i eventuelle gjenværende prosesser fra CoreCycler-mappen."
    }
    catch {
        Write-ManagerLog -Text "Feil under opprydding av CoreCycler-prosesser: $($_.Exception.Message)"
    }

    $State.aktivProsessId = $null
    $State.status = 'Stoppet'
    $State.sisteHendelse = 'Test stoppet av bruker. CoreCycler-prosesser er forsøkt ryddet opp.'

    # Fiskum IT: bevisst stopp - ingen flere automatiske gjenopptak ved innlogging forventes.
    # Rydder na ogsa autologon (hvis v0.8.2 satte den opp) i samme slag - se
    # Remove-AutoRecoveryInfrastructure
    Remove-AutoRecoveryInfrastructure -State $State

    Add-History -State $State -Message $State.sisteHendelse

    try {
        $latestLog = Get-LatestCoreCyclerLogFile
        $lines = @()

        if ($latestLog) {
            $lines = Read-LastLines -Path $latestLog.FullName -Count 200
        }

        Write-DesktopSnapshot `
            -Reason 'Test stoppet av bruker' `
            -CoreStatus $State.coreStatus `
            -VisDetaljer
    }
    catch {
        Write-ManagerLog -Text "Kunne ikke skrive spenningssnapshot ved stopp: $($_.Exception.Message)"
    }

    Save-State -State $State
}

function Advance-StateAfterSuccess {
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        $Plan
    )

    $State.sisteFullforteTestId = [int]$State.aktivTestId

    $next = Get-NextTest -Plan $Plan -State $State

    if ($next) {
        $State.aktivTestId = $next.id
        $State.status = 'Klar for neste test'
        $State.sisteHendelse = 'Test fullført, går videre til neste test'
    }
    else {
        $State.status = 'Fullført'
        $State.sisteHendelse = 'Hele testplanen er fullført'
    }

    $State.aktivProsessId = $null
    Add-History -State $State -Message $State.sisteHendelse
    Save-State -State $State
}

$App = [ordered]@{
    Plan                 = $null
    MirroredLogLines     = @{}
    State                = $null
    Process              = $null
    CurrentCoreCyclerLog = $null
    AutoContinue         = $true
    Timer                = $null
    LastLoggedCoreStatus = ''
    LastLoggedOffset     = ''
    Ui                   = [ordered]@{}
}

function Update-AssistertUiEnabled {
    # Fiskum IT: "Avansert..." (testvalg/varighet) gjelder kun Vanlig stabilitetstest og har
    # ingen innvirkning paa Assistert undervolting selv - men knappen er ogsaa tilgjengelig
    # mens Assistert undervolting er valgt, sa lenge auto-overgang er paa, slik at brukeren
    # kan forhaandskonfigurere stabilitetstesten som starter automatisk etterpaa
    # "auto-overgang"-avhukingen gjelder kun Assistert undervolting
    if (-not $App.Ui.btnAvansert -or -not $App.Ui.chkAutoSwitch) {
        return
    }

    $erAssistert = ($App.State.modus -eq 'AssistertUndervolting')

    $App.Ui.btnAvansert.Enabled = (-not $erAssistert) -or $App.Ui.chkAutoSwitch.Checked

    # Fiskum IT: CheckBox.Enabled=$false ville tvunget gjennom Windows' egen (for morke,
    # darlig lesbare pa mork bakgrunn) gratoneoverstyring av SELVE TEKSTEN, uavhengig av
    # FlatStyle/ForeColor. Holder den derfor alltid interaktiv (a huke av/pa nar den
    # "ikke gjelder" er harmlost - det er bare en forhandsinnstilling for naeste gang
    # Assistert undervolting er aktiv), og signaliserer "ikke relevant na" med en dimmet,
    # men fortsatt fullt lesbar, tekstfarge i stedet
    $App.Ui.chkAutoSwitch.Enabled = $true
    $App.Ui.chkAutoSwitch.ForeColor = if ($erAssistert) {
        [System.Drawing.Color]::FromArgb(225,225,225)
    } else {
        [System.Drawing.Color]::FromArgb(150,154,160)
    }
}

function Switch-Modus {
    # Fiskum IT: bytter mellom "Stabilitet" (testplan.json) og "AssistertUndervolting"
    # (AssistedUndervolting_Ryzen.ini). Brukes bade fra radioknappene i UI og automatisk
    # av Handle-ProcessFinished nar Assistert undervolting er fullfort.
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Stabilitet', 'AssistertUndervolting')]
        [string]$NyModus
    )

    if ($App.State.status -eq 'Kjører') {
        [System.Windows.Forms.MessageBox]::Show(
            'Stopp den aktive testen før du bytter modus.',
            'Fiskum IT CoreCycler Manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        return $false
    }

    # Fiskum IT: na-knapp-niva-forsvar i tillegg til selve UI-gra-utingen (Build-Ui) - hindrer
    # "Assistert undervolting" pa en ustottet CPU uansett hvordan denne funksjonen kalles fra
    if ($NyModus -eq 'AssistertUndervolting' -and -not (Get-UndervoltStotteInfo).Stottet) {
        [System.Windows.Forms.MessageBox]::Show(
            "Assistert undervolting er ikke støttet på denne CPU-en.`r`n`r`n$((Get-UndervoltStotteInfo).Forklaring)",
            'Fiskum IT CoreCycler Manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null

        return $false
    }

    if ($App.State.modus -eq $NyModus) {
        return $true
    }

    $App.State.modus = $NyModus
    $App.State.assistertSokStartet = $false
    $App.State.assistertSokStartTid = ''
    $App.Plan = @(Get-Plan -Modus $NyModus)
    $App.State.aktivTestId = 1
    Sync-AktivTestId -State $App.State -Plan $App.Plan
    $App.State.sisteFullforteTestId = 0
    $App.State.status = 'Klar'
    $App.State.sisteHendelse = "Modus endret til: $NyModus"

    Add-History -State $App.State -Message $App.State.sisteHendelse
    Save-State -State $App.State

    Update-AssistertUiEnabled

    return $true
}

function Get-StatusColor {
    # Fiskum IT: lysnet for det morke fargetemaet - de opprinnelige fargene var valgt for
    # lys bakgrunn og ville vaert vanskelig lesbare (for mork kontrast) na som UI'et er
    # mork-temaet, se Build-Ui/New-Label
    param(
        [string]$Status
    )

    switch ($Status) {
        'Kjører' { return [System.Drawing.Color]::FromArgb(87,209,138) }
        'Fullført' { return [System.Drawing.Color]::FromArgb(95,179,255) }
        'Feil' { return [System.Drawing.Color]::FromArgb(255,107,107) }
        'Stoppet' { return [System.Drawing.Color]::FromArgb(255,167,38) }
        'Klar for neste test' { return [System.Drawing.Color]::FromArgb(38,214,193) }
        default { return [System.Drawing.Color]::FromArgb(190,190,190) }
    }
}

function Refresh-UiState {
    $plan = $App.Plan
    $state = $App.State

    $current = Get-CurrentTest -Plan $plan -State $state
    $next = Get-NextTest -Plan $plan -State $state
    $nextErEtterAutoOvergang = $false

    # Fiskum IT: i Assistert undervolting-modus er $plan kun ett syntetisk steg, sa
    # Get-NextTest finner aldri noe "neste" der - men hvis auto-overgang til Vanlig
    # stabilitetstest er avhuket, vet vi faktisk hva som skjer etterpa: forste aktive
    # test i Vanlig stabilitetstest (samme test Switch-Modus/Sync-AktivTestId velger)
    if (-not $next -and $state.modus -eq 'AssistertUndervolting' -and $state.autoSwitchToStability) {
        $stabilitetsPlan = @(Get-StabilitetsPlan)

        if ($stabilitetsPlan.Count -gt 0) {
            $next = $stabilitetsPlan[0]
            $nextErEtterAutoOvergang = $true
        }
    }

    $completedRounds = Get-CompletedRoundCount -Plan $plan -State $state
    $totalRounds = $plan.Count

    $pct = if ($totalRounds -gt 0) {
        [math]::Floor(($completedRounds / $totalRounds) * 100)
    }
    else {
        0
    }

    if ($pct -gt 100) { $pct = 100 }
    if ($pct -lt 0) { $pct = 0 }

    $App.Ui.lblStatusValue.Text = $state.status
    $App.Ui.lblStatusValue.ForeColor = Get-StatusColor -Status $state.status

    $App.Ui.lblCurrentTestValue.Text = if ($current) { $current.navn } else { 'Ingen' }
    $App.Ui.lblNextValue.Text = if ($next) {
        if ($nextErEtterAutoOvergang) { $next.navn + ' (auto-overgang)' } else { $next.navn }
    } else { 'Ingen' }
    $App.Ui.lblAdminValue.Text = if (Test-ErAdministrator) { 'Ja' } else { 'Nei' }
    $App.Ui.lblCoreValue.Text = if ($state.coreStatus) { $state.coreStatus } else { 'Ikke registrert enda' }
    $App.Ui.lblPidValue.Text = if ($state.aktivProsessId) { [string]$state.aktivProsessId } else { 'Ingen' }
    $App.Ui.lblLastLogValue.Text = if ($state.sisteLoggfil) { $state.sisteLoggfil } else { 'Ingen' }
    $App.Ui.lblOffsetValue.Text = if ($state.offsetRekke) { $state.offsetRekke } else { $state.sisteRapporterteOffset }

    $App.Ui.progress.Value = $pct
    $App.Ui.lblProgressValue.Text = ('{0}/{1} tester ({2}%)' -f $completedRounds, $totalRounds, $pct)

    Write-DesktopStatusReport -State $state -Plan $plan
}

function Update-StateFromOffsetSnapshot {
    # Fiskum IT: oppdaterer state fra den strukturerte, alltid-pa snapshot-filen som
    # CoreCycler-motoren skriver (fiskumit-offset-snapshot.json). Dette er den
    # autoritative kilden for lopende offset-visning og for krasjgjenoppretting -
    # se Resolve-CrashedRun.
    param(
        [Parameter(Mandatory)]
        $Snapshot
    )

    if ($null -eq $Snapshot.offsets) {
        return
    }

    $offsetsObj = [pscustomobject]@{}
    $i = 0

    foreach ($v in @($Snapshot.offsets)) {
        $offsetsObj | Add-Member -MemberType NoteProperty -Name ([string]$i) -Value ([int]$v) -Force
        $i++
    }

    $App.State.coreOffsets            = $offsetsObj
    $App.State.offsetRekke            = Format-OffsetRekke -CoreOffsets $offsetsObj -ErGlobalVerdi:((Get-UndervoltStotteInfo).Vendor -eq 'Intel')
    $App.State.sisteRapporterteOffset = $App.State.offsetRekke

    if ($null -ne $Snapshot.activeCore) {
        $App.State.coreStatus = "Aktiv kjerne: Core $($Snapshot.activeCore)"
    }

    $App.State.sokRetning             = [string]$Snapshot.searchDirection
    $App.State.sisteOffsetSnapshotTid = [string]$Snapshot.timestamp

    $laaste = [pscustomobject]@{}

    if ($Snapshot.lockedCores) {
        foreach ($prop in $Snapshot.lockedCores.PSObject.Properties) {
            $laaste | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
        }
    }

    $App.State.laasteKjerner = $laaste
}

function Get-KonsollEkvivalenteLinjer {
    # Fiskum IT: CoreCycler-vinduet kjores na skjult (se Start-CoreCyclerStep) - dette
    # gjenskaper hva det skjulte konsollvinduet FAKTISK ville vist, ut fra loggfilen.
    # Motoren skriver verbose- og debug-tekst (Write-VerboseText/Write-DebugText) KUN til
    # loggfilen ved standard logLevel=2 - de vises ALDRI pa selve konsollen, kun i loggen.
    # Begge kjennes alltid igjen pa eksakt 14 mellomrom + et "+"-tegn (se
    # ''.PadLeft(14,' ') + '+   '/'+++ ' i script-corecycler.ps1) - filtreres bort her slik
    # at UI-visningen matcher konsollen, ikke loggfilens mer detaljerte fulle innhold
    param(
        [string[]]$Lines
    )

    if (-not $Lines) {
        return @()
    }

    return @($Lines | Where-Object { $_ -notmatch '^ {14}\+' })
}

function Get-KonsollLinjeFarge {
    # Fiskum IT: tilnaermer fargevalgene motoren selv bruker (Write-ColorText -ForegroundColor
    # i script-corecycler.ps1) ut fra noyaktig hvilken farge sp00n bruker for samme type
    # innhold - ikke en pikselnoyaktig kopi (selve fargeinformasjonen finnes ikke i
    # loggfilen, kun ren tekst), men gir samme visuelle inntrykk: rodt/magenta for feil,
    # gult for advarsler, gront for vellykkede hendelser/overskrifter, cyan for vanlig info
    #
    # VIKTIG (reell, alvorlig bug funnet pa WANJA-GAMER 2026-06-21): IKKE [Parameter(Mandatory)]
    # her - se forklaring i Write-DesktopLog. Ekte CoreCycler-logglinjer inneholder ofte blanke
    # linjer, og Set-LiveLogView sin foreach-lopkalt DENNE funksjonen for HVER linje uten a
    # hoppe over blanke. Med Mandatory feilet kallet med "Cannot bind argument to parameter
    # 'Line' because it is an empty string" sa snart en blank linje ble nadd - dette kastet seg
    # helt opp til hovedtimerens try/catch (logget som "Timer-feil: ..."), som AVBRYTER resten
    # av tick-en FOR den nar Handle-ProcessFinished/Refresh-UiState OG, kritisk, FOR
    # Refresh-CoreCyclerLogView sin egen senere lesing av offset-snapshot-filen. Nettoeffekten:
    # "Siste CoreCycler-logg" i UI'et viste naermest ingenting (RichTextBox-en blir tomet med
    # .Clear() FORST i Set-LiveLogView, sa krasjer det pa forste blanke linje - bygges aldri opp
    # pa nytt), OG Offset-rekken/skrivebordsloggen oppdaterte seg ikke - SELV OM motoren selv
    # fortsatte a soke helt korrekt i bakgrunnen (bekreftet i CoreCycler-loggen: gikk fra
    # Core 0 -1 til -16 og videre til Core 3 -10 over de samme 43 minuttene brukeren observerte
    # "ingen endring"). Dette var en visningsbug i Manageren, IKKE en reell svikt i sokealgoritmen
    param(
        [string]$Line
    )

    if ($Line -match 'FATAL ERROR') {
        return [System.Drawing.Color]::Red
    }

    if ($Line -match '(?i)\bWHEA\b' -or $Line -match '(?i)^\s*ERROR:') {
        return [System.Drawing.Color]::Magenta
    }

    if ($Line -match '(?i)WARNING') {
        return [System.Drawing.Color]::Yellow
    }

    if ($Line -match 'finished!|passed without error' -or $Line -match '^\s*[╔╚╟═─╢╗╝│]') {
        return [System.Drawing.Color]::Green
    }

    if ($Line -match '- Iteration \d') {
        return [System.Drawing.Color]::Yellow
    }

    return [System.Drawing.Color]::Cyan
}

function Set-LiveLogView {
    # Fiskum IT: bygger om hele innholdet i "Siste CoreCycler-logg" (samme full-erstatt-
    # modell som tidligere ble brukt for den enkle TextBox-en), men na med filtrerte,
    # fargelagte linjer i en RichTextBox - for a etterligne det skjulte konsollvinduet i
    # stedet for a vise loggfilens raa, mer detaljerte innhold
    # Fiskum IT: IKKE [Parameter(Mandatory)] her - se forklaring i Write-DesktopLog. Ekte
    # CoreCycler-logglinjer inneholder ofte blanke linjer, som ville fatt ETHVERT reelt
    # kall til a feile med "empty string"-bindingsfeil
    param(
        [string[]]$RawLines
    )

    $konsollLinjer = @(Get-KonsollEkvivalenteLinjer -Lines $RawLines | Select-Object -Last 80)

    # Fiskum IT: nyeste linje forst (vises ovenst i boksen) - brukeren skal se siste hendelse
    # uten a scrolle, med historikk som vokser NEDOVER etter hvert som flere hendelser skjer
    [array]::Reverse($konsollLinjer)

    # Fiskum IT: synlig flimring "med ujevne mellomrom" - rotarsak: RichTextBox-en ble tomt
    # og bygget opp igjen pa HVERT tick (hvert 1,5 sekund), uansett om CoreCycler faktisk
    # hadde logget noe nytt siden forrige gang. CoreCycler logger ikke en ny konsoll-
    # hendelse pa hvert tick - derfor virket flimringen "uregelmessig": den skjedde pa et
    # jevnt klokkeslett (hvert tick), men var bare SYNLIG nar innholdet faktisk endret seg.
    # Hopper na over hele ombygningen nar innholdet er likt som forrige gang
    $nyttInnhold = $konsollLinjer -join "`n"

    if ($nyttInnhold -eq $Script:SisteLiveLogInnhold) {
        return
    }

    $Script:SisteLiveLogInnhold = $nyttInnhold

    $rtb = $App.Ui.txtLog
    $WM_SETREDRAW = 0x000B

    # Fiskum IT: undertrykker selve SKJERMMALINGEN (IKKE det samme som SuspendLayout, som
    # bare gjelder kontroll-layout/posisjonering) mens vi tomer og bygger opp pa nytt - uten
    # dette ville selv en reell ENDRING fortsatt gitt et kort synlig "tomt"-blink midt i
    # ombygningen, siden RichTextBox normalt maler seg pa nytt etter HVER AppendText
    [void][FiskumIT.NoFlicker]::SendMessage($rtb.Handle, $WM_SETREDRAW, $false, 0)

    try {
        $rtb.SuspendLayout()
        $rtb.Clear()

        foreach ($line in $konsollLinjer) {
            $rtb.SelectionStart  = $rtb.TextLength
            $rtb.SelectionLength = 0
            $rtb.SelectionColor  = Get-KonsollLinjeFarge -Line $line
            $rtb.AppendText($line + "`r`n")
        }

        $rtb.SelectionStart = 0

        # Fiskum IT: RichTextBox bygger opp en INTERN angre-historikk (Undo-buffer) for
        # HVER AppendText - uten denne rydder ikke .Clear() den bufferen, og over en
        # langvarig kjoring (timer-tick hvert 1,5 sek i flere timer/dogn) vokser
        # minnebruken sakte men sikkert ubegrenset. Funnet som en sannsynlig medvirkende
        # arsak til "System.OutOfMemoryException" pa Manager-siden etter en ~17-timers
        # sammenhengende kjoring pa NR-GAMER 2026-06-21 (sammen med en mye tyngre enn
        # vanlig egendefinert testbatteri - se Utviklingslogg-UI-Stabilitet.md). Denne
        # boksen er en ren programmatisk visning - brukeren har ingen bruk for Ctrl+Z her
        $rtb.ClearUndo()

        $rtb.ResumeLayout()
    }
    finally {
        [void][FiskumIT.NoFlicker]::SendMessage($rtb.Handle, $WM_SETREDRAW, $true, 0)
    }

    $rtb.ScrollToCaret()
    $rtb.Refresh()
}

function Refresh-CoreCyclerLogView {
    $latest = Get-LatestCoreCyclerLogFile
    $lines  = @()

    if ($latest) {
        $App.CurrentCoreCyclerLog = $latest.FullName
        $App.State.sisteLoggfil = $latest.FullName

        # Fiskum IT: leser et stort rentersvindu siden en stor andel av linjene normalt
        # filtreres bort av Set-LiveLogView (verbose/debug-tier, se Get-KonsollEkvivalenteLinjer)
        # - 400 raa linjer kan i praksis gi langt faerre enn 80 konsoll-ekvivalente linjer
        $lines = Read-LastLines -Path $latest.FullName -Count 1500

        # Fiskum IT: egen try/catch - en feil i selve UI-tegningen skal IKKE kunne hindre
        # offset-snapshot-lesingen under (se forklaringen i Get-KonsollLinjeFarge for
        # bakgrunnen - dette er ekstra beskyttelse i tillegg til at selve roten er fikset)
        try {
            Set-LiveLogView -RawLines $lines
        }
        catch {
            Write-ManagerLog -Text "Kunne ikke oppdatere 'Siste CoreCycler-logg': $($_.Exception.Message)"
        }

        $coreText = Get-CoreStatusFromLog -Lines $lines

        if ($coreText) {
            $App.State.coreStatus = $coreText
        }
    }

    # Fiskum IT: foretrekk den strukturerte snapshot-filen fra motoren - den er alltid
    # noyaktig og oppdateres lopende, uavhengig av hvilket testprogram som kjorer
    $snapshot = Get-CoreOffsetSnapshot

    if ($snapshot) {
        Update-StateFromOffsetSnapshot -Snapshot $snapshot
    }
    elseif ($lines.Count -gt 0) {
        # Fallback for de forste sekundene av en kjoring, for snapshot-filen er skrevet
        [void](Update-CurveOptimizerStateFromLog -Lines $lines)

        if (-not $App.State.coreOffsets -or @($App.State.coreOffsets.PSObject.Properties).Count -eq 0) {
            $offset = Get-LatestOffsetFromLog -Lines $lines

            if ($offset) {
                $App.State.sisteRapporterteOffset = $offset
            }
        }
    }

    # Fiskum IT: Maybe-LogDesktopSnapshot maa kalles HVER gang, ikke bare nar $lines har
    # innhold - statusoppdateringen over (Update-StateFromOffsetSnapshot) er den primaere,
    # palitelige kilden og kan oppdatere $App.State helt uavhengig av om den raa CoreCycler-
    # tekstloggen ble lest denne runden. Sto dette inni "if ($lines.Count -gt 0)" tidligere,
    # ble skrivebordsloggen aldri oppdatert i de (ikke uvanlige) tilfellene hvor $lines var
    # tom en runde - selve funksjonen har allerede sin egen interne sjekk for om noe faktisk
    # endret seg, sa det er trygt aa alltid kalle den
    $mirrored = @()

    if ($lines.Count -gt 0) {
        $mirrored = @(Mirror-CoreCyclerLogLines -Lines $lines)
    }

    Maybe-LogDesktopSnapshot -MirroredLines $mirrored

    Save-State -State $App.State
}

function Read-CurveOptimizerFromConfigFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = [pscustomobject]@{}

    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    try {
        $content = Get-Content -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        return $result
    }

    $allCoresVal = $null
    $perCore     = @{}

    foreach ($raw in $content) {
        $line = ($raw -replace '[#;].*$','').Trim()

        if (-not $line) { continue }

        # AMD Ryzen 3000/5000 - CoreCycler config.ini bruker f.eks.:
        #   curveOptimizerAllCores = -10
        #   curveOptimizerSingleCores = 0|-5, 1|-10, 2|-3 ...
        if ($line -match '^\s*curveOptimizerAllCores\s*=\s*(-?\d+)\s*$') {
            $allCoresVal = [int]$Matches[1]
            continue
        }

        if ($line -match '^\s*curveOptimizerSingleCores\s*=\s*(.+)$') {
            $payload = $Matches[1].Trim().Trim('"').Trim("'")

            foreach ($piece in ($payload -split '[,;]')) {
                $p = $piece.Trim()
                if (-not $p) { continue }

                if ($p -match '^\s*(\d+)\s*\|\s*(-?\d+)\s*$') {
                    $perCore[[string][int]$Matches[1]] = [int]$Matches[2]
                }
            }

            continue
        }
    }

    # Bygg objektet: bruk per-core hvis spesifisert, ellers allCores
    if ($perCore.Count -gt 0) {
        foreach ($k in ($perCore.Keys | Sort-Object { [int]$_ })) {
            $result | Add-Member -MemberType NoteProperty -Name $k -Value $perCore[$k] -Force
        }
    }
    elseif ($null -ne $allCoresVal) {
        # Vi vet ikke antall kjerner her - merk med "alle"
        $result | Add-Member -MemberType NoteProperty -Name 'alle' -Value $allCoresVal -Force
    }

    return $result
}

function Get-OffsetsFromRyzenSmuCli {
    # Leser per-core Curve Optimizer-verdier direkte fra CPU-en via
    # ryzen-smu-cli.exe som ligger i CoreCycler\tools\ryzen-smu-cli\.
    #
    # Fiskum IT-fiks: bruker samme flagg og parsing som CoreCycler-motoren selv
    # (Get-CurveOptimizerValues i script-corecycler.ps1) - "--get-offsets-terse"
    # returnerer en kommaseparert liste pa SISTE linje (f.eks. "-1,-1,-1,-1,-1,-1"),
    # IKKE "Core X: Y"-tekst som de gamle flaggene/regex-ene her feilaktig forventet.
    #
    # Returnerer en PSCustomObject med felter "0","1","2"... -> int,
    # eller $null hvis verktoeyet ikke finnes / output ikke kan parses.

    $ryzenTool = Join-Path $CoreCyclerDir 'tools\ryzen-smu-cli\ryzen-smu-cli.exe'

    if (-not (Test-Path -LiteralPath $ryzenTool)) {
        return $null
    }

    try {
        $rawOutput = & $ryzenTool '--get-offsets-terse' 2>&1 | Out-String
    }
    catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        return $null
    }

    $outputLines = @($rawOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($outputLines.Count -eq 0) {
        return $null
    }

    # Den siste ikke-tomme linjen er den kommaseparerte offset-listen, en verdi per kjerne i indeksrekkefolge
    $lastLine = $outputLines[$outputLines.Count - 1].Trim()
    $values   = @($lastLine -split ',' | Where-Object { $_ -match '^\s*-?\d+\s*$' } | ForEach-Object { [int] $_.Trim() })

    if ($values.Count -eq 0) {
        return $null
    }

    $offsets = [pscustomobject]@{}

    for ($i = 0; $i -lt $values.Count; $i++) {
        $offsets | Add-Member -MemberType NoteProperty -Name ([string]$i) -Value $values[$i] -Force
    }

    return $offsets
}

function Set-OffsetsViaRyzenSmuCli {
    # Fiskum IT: skriver et komplett sett Curve Optimizer-verdier direkte til CPU-en,
    # brukt ved krasjgjenoppretting (se Resolve-CrashedRun) for a rette EN kjerne
    # for CoreCycler startes pa nytt. Speiler motorens egen Set-CurveOptimizerValues-bruk.
    param(
        [Parameter(Mandatory)]
        [int[]]$Offsets
    )

    $ryzenTool = Join-Path $CoreCyclerDir 'tools\ryzen-smu-cli\ryzen-smu-cli.exe'

    if (-not (Test-Path -LiteralPath $ryzenTool)) {
        Write-ManagerLog -Text 'Set-OffsetsViaRyzenSmuCli: fant ikke ryzen-smu-cli.exe.'
        return $false
    }

    $argumentString = '--offset ' + ($Offsets -join ',')

    try {
        $procInfo = New-Object System.Diagnostics.ProcessStartInfo
        $procInfo.FileName               = $ryzenTool
        $procInfo.Arguments              = $argumentString
        $procInfo.Verb                   = 'runas'
        $procInfo.RedirectStandardError  = $true
        $procInfo.RedirectStandardOutput = $true
        $procInfo.UseShellExecute        = $false

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $procInfo
        [void]$proc.Start()

        $stdOut = $proc.StandardOutput.ReadToEnd()
        $stdErr = $proc.StandardError.ReadToEnd()

        if (-not $proc.WaitForExit(5000)) {
            $proc.Kill()
            $proc.Dispose()
            Write-ManagerLog -Text 'Set-OffsetsViaRyzenSmuCli: ryzen-smu-cli svarte ikke innen 5 sekunder.'
            return $false
        }

        $exitCode = $proc.ExitCode
        $proc.Dispose()

        if ($exitCode -ne 0) {
            Write-ManagerLog -Text "Set-OffsetsViaRyzenSmuCli: ryzen-smu-cli returnerte feilkode $exitCode. $stdErr"
            return $false
        }

        Write-ManagerLog -Text "Set-OffsetsViaRyzenSmuCli: satte offset $($Offsets -join ',') via ryzen-smu-cli."
        return $true
    }
    catch {
        Write-ManagerLog -Text "Set-OffsetsViaRyzenSmuCli feilet: $($_.Exception.Message)"
        return $false
    }
}

function Get-OffsetsFromIntelVoltageControl {
    # Fiskum IT: leser DEN ENE globale spenningsforskyvningen direkte fra CPU-en via
    # IntelVoltageControl.exe ("show"). Speiler regex-en motoren selv bruker
    # (Get-IntelVoltageOffset i script-corecycler.ps1): "Plane 0: <tall>" pa en av
    # linjene i output. Returnerer en PSCustomObject med kun felt "0" -> int (Intel har
    # ingen per-kjerne-granularitet, se Format-OffsetRekke -ErGlobalVerdi),
    # eller $null hvis verktoyet ikke finnes / output ikke kan parses.
    $intelTool = Join-Path $CoreCyclerDir 'tools\IntelVoltageControl\IntelVoltageControl.exe'

    if (-not (Test-Path -LiteralPath $intelTool)) {
        return $null
    }

    try {
        $procInfo = New-Object System.Diagnostics.ProcessStartInfo
        $procInfo.FileName               = $intelTool
        $procInfo.Arguments              = 'show'
        $procInfo.Verb                   = 'runas'
        $procInfo.RedirectStandardError  = $true
        $procInfo.RedirectStandardOutput = $true
        $procInfo.UseShellExecute        = $false

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $procInfo
        [void]$proc.Start()

        $stdOut = $proc.StandardOutput.ReadToEnd()

        if (-not $proc.WaitForExit(5000)) {
            $proc.Kill()
            $proc.Dispose()
            return $null
        }

        $exitCode = $proc.ExitCode
        $proc.Dispose()

        if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdOut)) {
            return $null
        }
    }
    catch {
        return $null
    }

    $match = [regex]::Match($stdOut, 'Plane 0:\s*(-?\d+\.?\d*)')

    if (-not $match.Success) {
        Write-ManagerLog -Text "Get-OffsetsFromIntelVoltageControl: fant ikke 'Plane 0: <tall>' i output. Raatekst: $stdOut"
        return $null
    }

    $verdi = [int][Math]::Round([double]$match.Groups[1].Value)

    $offsets = [pscustomobject]@{}
    $offsets | Add-Member -MemberType NoteProperty -Name '0' -Value $verdi -Force

    return $offsets
}

function Set-OffsetViaIntelVoltageControl {
    # Fiskum IT: skriver den globale spenningsforskyvningen direkte til CPU-en, brukt ved
    # krasjgjenoppretting (se Resolve-CrashedRun). Speiler motorens egen
    # Set-IntelVoltageOffset-bruk: plan 0 (kjerne) og plan 2 (cache, lenket til plan 0 pa
    # Skylake-avledede) MA settes til SAMME verdi for at endringen skal ha noen effekt
    param(
        [Parameter(Mandatory)]
        [int]$Verdi
    )

    $intelTool = Join-Path $CoreCyclerDir 'tools\IntelVoltageControl\IntelVoltageControl.exe'

    if (-not (Test-Path -LiteralPath $intelTool)) {
        Write-ManagerLog -Text 'Set-OffsetViaIntelVoltageControl: fant ikke IntelVoltageControl.exe.'
        return $false
    }

    $argumentString = 'set --allow-overvolt --commit 0 {0} 2 {0}' -f $Verdi

    try {
        $procInfo = New-Object System.Diagnostics.ProcessStartInfo
        $procInfo.FileName               = $intelTool
        $procInfo.Arguments              = $argumentString
        $procInfo.Verb                   = 'runas'
        $procInfo.RedirectStandardError  = $true
        $procInfo.RedirectStandardOutput = $true
        $procInfo.UseShellExecute        = $false

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $procInfo
        [void]$proc.Start()

        $stdOut = $proc.StandardOutput.ReadToEnd()
        $stdErr = $proc.StandardError.ReadToEnd()

        if (-not $proc.WaitForExit(5000)) {
            $proc.Kill()
            $proc.Dispose()
            Write-ManagerLog -Text 'Set-OffsetViaIntelVoltageControl: IntelVoltageControl svarte ikke innen 5 sekunder.'
            return $false
        }

        $exitCode = $proc.ExitCode
        $proc.Dispose()

        if ($exitCode -ne 0) {
            Write-ManagerLog -Text "Set-OffsetViaIntelVoltageControl: IntelVoltageControl returnerte feilkode $exitCode. $stdErr"
            return $false
        }

        Write-ManagerLog -Text "Set-OffsetViaIntelVoltageControl: satte spenningsforskyvning $Verdi mV via IntelVoltageControl."
        return $true
    }
    catch {
        Write-ManagerLog -Text "Set-OffsetViaIntelVoltageControl feilet: $($_.Exception.Message)"
        return $false
    }
}

function Get-CoreOffsetSnapshot {
    # Fiskum IT: leser den alltid-pa snapshot-filen som CoreCycler-motoren skriver
    # (CoreCycler\logs\fiskumit-offset-snapshot.json). $null hvis filen ikke finnes -
    # det betyr enten at ingen test i Automatic Test Mode har kjort enda, eller at
    # forrige kjoring ble avsluttet rent (motoren fjerner filen selv ved ren avslutning)
    $path = Join-Path $CoreCyclerLogDir 'fiskumit-offset-snapshot.json'
    return Read-JsonFile -Path $path
}

function Initialize-OffsetsFromLogAndConfig {
    param(
        $Test
    )

    # 1) Forsøk å lese gjeldende verdier direkte fra CPU-en - ryzen-smu-cli.exe (AMD) eller
    #    IntelVoltageControl.exe (Intel), se Get-UndervoltStotteInfo
    try {
        $stotteForLesing = Get-UndervoltStotteInfo
        $erIntel = ($stotteForLesing.Vendor -eq 'Intel')
        $smuOffsets = $(if ($erIntel) { Get-OffsetsFromIntelVoltageControl } else { Get-OffsetsFromRyzenSmuCli })

        if ($smuOffsets -and @($smuOffsets.PSObject.Properties).Count -gt 0) {
            $App.State.coreOffsets           = $smuOffsets
            $App.State.offsetRekke           = Format-OffsetRekke -CoreOffsets $smuOffsets -ErGlobalVerdi:$erIntel
            $App.State.sisteRapporterteOffset = $App.State.offsetRekke

            $kilde = $(if ($erIntel) { 'IntelVoltageControl' } else { 'ryzen-smu-cli' })
            Write-ManagerLog -Text "Initiell Offset-rekke hentet fra $kilde`: $($App.State.offsetRekke)"
            Save-State -State $App.State
            return
        }
    }
    catch {
        Write-ManagerLog -Text "Lesing av spenningsverdier feilet ved oppstart: $($_.Exception.Message)"
    }

    $foundFromLog = $false

    # 2) Fall tilbake til verdier fra siste CoreCycler-logg
    $latest = Get-LatestCoreCyclerLogFile

    if ($latest) {
        $lines = Read-LastLines -Path $latest.FullName -Count 1000

        if ($lines -and $lines.Count -gt 0) {
            [void](Update-CurveOptimizerStateFromLog -Lines $lines)

            if ($App.State.coreOffsets -and @($App.State.coreOffsets.PSObject.Properties).Count -gt 0) {
                $foundFromLog = $true
            }
        }
    }

    if ($foundFromLog) {
        Write-ManagerLog -Text "Initiell Offset-rekke hentet fra siste CoreCycler-logg: $($App.State.offsetRekke)"
        return
    }

    # 3) Fall tilbake til verdier konfigurert i aktiv config.ini for testen
    if (-not $Test) {
        $App.State.offsetRekke = 'Ingen spenningsverdier funnet (verken direkte fra CPU-en eller fra logg)'
        Save-State -State $App.State
        return
    }

    $cfgPath = Join-Path $ConfigDir $Test.config
    $offsets = Read-CurveOptimizerFromConfigFile -Path $cfgPath

    if (@($offsets.PSObject.Properties).Count -gt 0) {
        $App.State.coreOffsets = $offsets
        $App.State.offsetRekke = Format-OffsetRekke -CoreOffsets $offsets -ErGlobalVerdi:((Get-UndervoltStotteInfo).Vendor -eq 'Intel')
        $App.State.sisteRapporterteOffset = $App.State.offsetRekke

        Write-ManagerLog -Text "Initiell Offset-rekke hentet fra config $($Test.config): $($App.State.offsetRekke)"
    }
    else {
        $App.State.offsetRekke = 'Ingen Curve Optimizer-verdier funnet (verken i logg eller config)'
    }

    Save-State -State $App.State
}

function Start-CurrentOrResume {
    if ($App.State.status -eq 'Kjører') {
        [System.Windows.Forms.MessageBox]::Show(
            'En test kjører allerede.',
            'Fiskum IT CoreCycler Manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        return
    }

    $test = Get-CurrentTest -Plan $App.Plan -State $App.State

    if (-not $test) {
        [System.Windows.Forms.MessageBox]::Show(
            'Fant ingen aktiv test i testplanen.',
            'Fiskum IT CoreCycler Manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        return
    }

    try {
        # Sørg for at "Offset-rekke" er fylt inn så snart testen starter:
        # 1) Forsøk å lese gjeldende verdier fra siste CoreCycler-logg
        # 2) Fall tilbake til verdiene i den aktive config.ini
        try { Initialize-OffsetsFromLogAndConfig -Test $test } catch {}

        $erGjenopptak = ($App.State.modus -eq 'AssistertUndervolting' -and $App.State.assistertSokStartet)

        $App.Process = Start-CoreCyclerStep -Test $test -State $App.State -ErGjenopptak:$erGjenopptak
        Refresh-UiState
    }
    catch {
        $App.State.status = 'Feil'
        $App.State.sisteHendelse = "Kunne ikke starte test: $($_.Exception.Message)"

        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State
        Invoke-AutoRestartIfEnabled -State $App.State -Reason 'Feil ved start av test'
        Refresh-UiState
    }
}

function Stop-CurrentRun {
    if ($App.State.status -ne 'Kjører') {
        return
    }

    Stop-CoreCyclerStep -State $App.State
    Refresh-UiState
}

function Handle-ProcessFinished {
    if (-not $App.State.aktivProsessId) {
        return
    }

    $procExists = $true

    try {
        $null = Get-Process -Id $App.State.aktivProsessId -ErrorAction Stop
    }
    catch {
        $procExists = $false
    }

    if ($procExists) {
        return
    }

    $App.State.aktivProsessId = $null

    $latestLog = Get-LatestCoreCyclerLogFile
    $lines = @()

    if ($latestLog) {
        $lines = Read-LastLines -Path $latestLog.FullName -Count 200
        $App.State.sisteLoggfil = $latestLog.FullName

        $offset = Get-LatestOffsetFromLog -Lines $lines

        if ($offset) {
            $App.State.sisteRapporterteOffset = $offset
        }
    }

    Write-DesktopSnapshot `
        -Reason 'CoreCycler-prosess avsluttet' `
        -CoreStatus $App.State.coreStatus `
        -VisDetaljer

    if (Test-LogIndicatesFatal -Lines $lines) {
        $App.State.status = 'Feil'
        $App.State.sisteHendelse = 'CoreCycler avsluttet med feilindikasjon i logg'

        # Fiskum IT (v0.8.2): en feilet bekreftelsesrunde betyr at margin IKKE var stor nok -
        # nullstill flagget na (ALDRI la det lekke videre/auto-gjenopptas med de samme
        # verdiene) og gi en tydelig annerledes melding enn en vanlig sok-feil
        if ($App.State.bekreftelseAktiv) {
            $App.State.sisteHendelse = 'Bekreftelsestest feilet - margin var IKKE stor nok (feilindikasjon i logg)'
            $App.State.bekreftelseAktiv = $false
            $App.State.bekreftelseOffsets = ''
        }

        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State
        Invoke-AutoRestartIfEnabled -State $App.State -Reason 'CoreCycler avsluttet med feilindikasjon i logg'
        Refresh-UiState

        return
    }

    if (-not (Test-LogIndicatesSuccessfulCompletion -Lines $lines)) {
        $App.State.status = 'Feil'
        $App.State.sisteHendelse = 'CoreCycler avsluttet uten fullført test eller klart resultat i logg'

        if ($App.State.bekreftelseAktiv) {
            $App.State.sisteHendelse = 'Bekreftelsestest feilet - margin var IKKE stor nok (uklart resultat i logg)'
            $App.State.bekreftelseAktiv = $false
            $App.State.bekreftelseOffsets = ''
        }

        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State
        Invoke-AutoRestartIfEnabled -State $App.State -Reason 'CoreCycler avsluttet uten fullført test eller klart resultat i logg'
        Refresh-UiState

        return
    }

    Advance-StateAfterSuccess -State $App.State -Plan $App.Plan

    # Fiskum IT: fanges FOR en evt. Switch-Modus under, som setter status tilbake til
    # "Klar" for auto-overgangen - uten denne ville sluttrapporten ALDRI bli skrevet nar
    # auto-overgang til Vanlig stabilitetstest er aktivert, siden statusen ikke lenger
    # er "Fullført" pa det punktet vi sjekker det
    $varFullfort = ($App.State.status -eq 'Fullført')

    # Fiskum IT (v0.8.2): fanges FOR auto-overgangen under (som kan endre $App.State.modus) og
    # FOR completion-handlingen (som nullstiller bekreftelseAktiv) - se
    # Start-BekreftelsesRundePrompt/bekreftelsesrunde-fullfort-handteringen under
    $varVarAssistertUndervolting = ($App.State.modus -eq 'AssistertUndervolting')
    $varVarBekreftelseAktiv = $App.State.bekreftelseAktiv

    # Fiskum IT: nar Assistert undervolting er fullfort og auto-overgang er aktivert,
    # bytt modus til Vanlig stabilitetstest na - status blir da "Klar" igjen, slik at
    # AutoContinue-sjekken under starter den forste stabilitetstesten automatisk
    if ($varFullfort -and $App.State.modus -eq 'AssistertUndervolting' -and $App.State.autoSwitchToStability) {
        Write-ManagerLog -Text 'Assistert undervolting fullført. Bytter automatisk til Vanlig stabilitetstest.'
        [void](Switch-Modus -NyModus 'Stabilitet')

        if ($App.Ui.radioStabilitet) {
            $App.Ui.radioStabilitet.Checked = $true
        }
    }

    if ($varFullfort) {
        if ($varVarBekreftelseAktiv) {
            # Fiskum IT (v0.8.2): dette var bekreftelsesrunden selv som fullforte (ikke et nytt
            # sok) - tydelig annerledes melding, og nullstill ALLTID flagget na som den er ferdig
            # slik at den aldri kan lekke inn i en senere, urelatert vanlig stabilitetstest
            $App.State.bekreftelseAktiv = $false
            $App.State.bekreftelseOffsets = ''
            Save-State -State $App.State

            Write-ManagerLog -Text 'Bekreftelsestest fullført - ingen feil på de anbefalte verdiene over en lengre test.'

            [System.Windows.Forms.MessageBox]::Show(
                "Bekreftelsestest fullført - ingen feil på de anbefalte verdiene over en lengre test.`r`n`r`nFullstendig rapport (skrivebordet): $DesktopLog",
                'Fiskum IT CoreCycler Manager - bekreftelsesrunde',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        else {
            $sluttrapportInfo = Write-SluttRapport -State $App.State
            Show-TestFullfortVarsel -SluttrapportInfo $sluttrapportInfo

            if ($varVarAssistertUndervolting) {
                Start-BekreftelsesRundePrompt -SluttrapportInfo $sluttrapportInfo
            }
        }

        # Fiskum IT (v0.8.2): en faktisk fullfort test er det sterkeste signalet om at
        # et eventuelt underliggende problem (som forarsaket tidligere auto-restarts) er
        # lost - nullstill forsoksgrensen, se Invoke-AutoRestartIfEnabled
        $App.State.consecutiveAutoRestartCount = 0

        Remove-AutoRecoveryInfrastructure -State $App.State
    }

    Refresh-UiState

    if ($App.State.status -ne 'Fullført' -and $App.AutoContinue) {
        Start-CurrentOrResume
    }
}

function Open-LatestLog {
    $path = $App.State.sisteLoggfil

    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Fant ingen logg å åpne.',
            'Fiskum IT CoreCycler Manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        return
    }

    Start-Process notepad.exe -ArgumentList ('"{0}"' -f $path)
}

function Open-DesktopReport {
    if (-not (Test-Path -LiteralPath $DesktopLog)) {
        Write-DesktopStatusReport -State $App.State -Plan $App.Plan
    }

    Start-Process notepad.exe -ArgumentList ('"{0}"' -f $DesktopLog)
}

function Reset-StateToStart {
    $result = [System.Windows.Forms.MessageBox]::Show(
        'Vil du nullstille state og starte fra test 1?',
        'Fiskum IT CoreCycler Manager',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    if ($App.State.status -eq 'Kjører') {
        Stop-CurrentRun
    }

    Remove-AutoRecoveryInfrastructure -State $App.State

    # Fiskum IT: full nullstilling skal ogsa gi et reelt blankt blad for Curve Optimizer-
    # verdiene - fjern motorens offset-snapshot, slik at neste test ikke "gjenopptar" gamle
    # funn (se Get-FiskumOffsetSnapshotValues i script-corecycler.ps1, som ellers ville
    # foretrukket denne filen fremfor en frisk start)
    $snapshotPath = Join-Path $CoreCyclerLogDir 'fiskumit-offset-snapshot.json'
    if (Test-Path -LiteralPath $snapshotPath) {
        Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
    }

    $App.State = New-DefaultState
    $App.Plan = @(Get-Plan -Modus $App.State.modus)
    Sync-AktivTestId -State $App.State -Plan $App.Plan
    Save-State -State $App.State

    if ($App.Ui.radioStabilitet) {
        $App.Ui.radioStabilitet.Checked = $true
    }

    if ($App.Ui.chkAutoSwitch) {
        $App.Ui.chkAutoSwitch.Checked = [bool]$App.State.autoSwitchToStability
    }

    if ($App.Ui.chkAutostart) {
        $App.Ui.chkAutostart.Checked = [bool]$App.State.autostartTask
    }

    if ($App.Ui.chkAutoRestart) {
        $App.Ui.chkAutoRestart.Checked = [bool]$App.State.autoRestartOnFeil
    }

    if ($App.Ui.numRestartWaitMinutes) {
        $App.Ui.numRestartWaitMinutes.Value = [int]$App.State.restartWaitMinutes
    }

    Update-AssistertUiEnabled
    Refresh-UiState
}

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 180,
        [int]$H = 22,
        [bool]$Bold = $false
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Object System.Drawing.Point($X,$Y)
    $lbl.Size = New-Object System.Drawing.Size($W,$H)
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(225,225,225)

    $lbl.Font = if ($Bold) {
        New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    }
    else {
        New-Object System.Drawing.Font('Segoe UI',9)
    }

    return $lbl
}

function New-Button {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 140,
        [int]$H = 34
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X,$Y)
    $btn.Size = New-Object System.Drawing.Size($W,$H)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(13,234,160)
    $btn.ForeColor = [System.Drawing.Color]::FromArgb(15,17,22)
    $btn.FlatStyle = 'Flat'
    $btn.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)

    return $btn
}

function Show-AutoRestartCountdown {
    # Fiskum IT (v0.8.2): liten, alltid-overst nedtellingsdialog FOR en auto-utlost restart
    # (se Invoke-AutoRestartIfEnabled) - gir en fysisk tilstedevarende bruker en SJANSE til
    # a avbryte, uten a KREVE det (ment a kjore helt ubetjent som normaltilfellet). Bruker
    # dialogens egen ShowDialog()-meldingslope (IKKE Start-Sleep/DoEvents) - holder bade
    # nedtellingen og Avbryt-knappen responsive uten a blokkere noe
    param(
        [int]$Sekunder = 60
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Fiskum IT CoreCycler Manager - Automatisk restart'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MinimizeBox = $false
    $dlg.MaximizeBox = $false
    $dlg.TopMost = $true
    $dlg.StartPosition = 'CenterScreen'
    $dlg.Size = New-Object System.Drawing.Size(460,180)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.ForeColor = [System.Drawing.Color]::White
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI',10)
    $lbl.Location = New-Object System.Drawing.Point(20,20)
    $lbl.Size = New-Object System.Drawing.Size(420,80)
    $lbl.Text = "Datamaskinen restarter automatisk om $Sekunder sekunder for å gjenopprette etter en feil.`r`n`r`nTrykk Avbryt for å stoppe restarten."

    $btnAvbryt = New-Object System.Windows.Forms.Button
    $btnAvbryt.Text = 'Avbryt'
    $btnAvbryt.Location = New-Object System.Drawing.Point(170,110)
    $btnAvbryt.Size = New-Object System.Drawing.Size(120,32)
    $btnAvbryt.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dlg.Controls.AddRange(@($lbl, $btnAvbryt))
    $dlg.CancelButton = $btnAvbryt

    $Script:AutoRestartCountdownSekunder = $Sekunder

    $countdownTimer = New-Object System.Windows.Forms.Timer
    $countdownTimer.Interval = 1000

    $countdownTimer.Add_Tick({
        $Script:AutoRestartCountdownSekunder--
        $lbl.Text = "Datamaskinen restarter automatisk om $($Script:AutoRestartCountdownSekunder) sekunder for å gjenopprette etter en feil.`r`n`r`nTrykk Avbryt for å stoppe restarten."

        if ($Script:AutoRestartCountdownSekunder -le 0) {
            $countdownTimer.Stop()
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    }.GetNewClosure())

    $dlg.Add_Shown({ $countdownTimer.Start() })
    $dlg.Add_FormClosing({ $countdownTimer.Stop() })

    $result = $dlg.ShowDialog()

    return ($result -eq [System.Windows.Forms.DialogResult]::OK)
}

function Show-AvansertDialog {
    # Fiskum IT: "Avansert..." - velg hvilke av de 21 testene i testplan.json som skal
    # kjores i Vanlig stabilitetstest, og hvilken varighet (minutter, eller "auto") hver
    # av dem skal bruke. Lagres til Manager\config\avansert-valg.json, se Get-AvansertValg.
    # Fiskum IT: IKKE pakk inn med @() her - Read-JsonFile/ConvertFrom-Json returnerer
    # allerede et korrekt formet array (selv med 0/1 elementer), og en ekstra @()-innpakning
    # her forer til at hele resultatet blir naestet ett hakk for dypt (array-i-array)
    $allTests = Read-JsonFile -Path $PlanFile

    if (-not $allTests -or $allTests.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'Fant ingen tester i testplan.json.',
            'Fiskum IT CoreCycler Manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        return
    }

    $eksisterende = @(Get-AvansertValg)
    $eksisterendeMap = @{}

    foreach ($entry in $eksisterende) {
        $eksisterendeMap[[int]$entry.id] = $entry
    }

    # Fiskum IT: samme morke fargetema som hovedvinduet, se Build-Ui
    $dlgPanelBackColor = [System.Drawing.Color]::FromArgb(30,33,40)
    $dlgPanelForeColor = [System.Drawing.Color]::FromArgb(225,225,225)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Avansert - velg tester og varighet (Vanlig stabilitetstest)'
    $dlg.StartPosition = 'CenterParent'
    $dlg.Size = New-Object System.Drawing.Size(720,664)
    $dlg.MinimumSize = New-Object System.Drawing.Size(720,664)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(15,17,22)
    $dlg.ForeColor = $dlgPanelForeColor

    $lblHeader = New-Label -Text 'Huk av hvilke tester som skal kjøres, og angi varighet i minutter (eller "auto").' -X 16 -Y 12 -W 680 -H 22 -Bold $true
    $dlg.Controls.Add($lblHeader)

    # Fiskum IT: viser hva Get-CpuInstruksjonssett faktisk fant for DENNE maskinen, slik at
    # det gir mening nar enkelte tester nedenfor er gratt ut og ikke kan hukes av
    $cpuCap = Get-CpuInstruksjonssett
    $stottedeSett = @('SSE/x86 (alltid)')
    if ($cpuCap.AVX)    { $stottedeSett += 'AVX' }
    if ($cpuCap.AVX2)   { $stottedeSett += 'AVX2' }
    if ($cpuCap.AVX512) { $stottedeSett += 'AVX512' }
    $lblCpuCaps = New-Label -Text ('Denne CPU-en stotter: ' + ($stottedeSett -join ', ') + ' - tester som krever mer er gratt ut nedenfor.') -X 16 -Y 36 -W 680 -H 20
    $lblCpuCaps.ForeColor = [System.Drawing.Color]::FromArgb(150,154,160)
    $dlg.Controls.Add($lblCpuCaps)

    $btnAlleAuto = New-Button -Text 'Sett alle: Auto' -X 16 -Y 64 -W 160 -H 28
    $btnAlle5Min = New-Button -Text 'Sett alle: 5 minutter' -X 184 -Y 64 -W 160 -H 28
    $dlg.Controls.AddRange(@($btnAlleAuto, $btnAlle5Min))

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(16,102)
    $panel.Size = New-Object System.Drawing.Size(680,480)
    $panel.AutoScroll = $true
    $panel.BackColor = $dlgPanelBackColor
    $dlg.Controls.Add($panel)

    $rowControls = New-Object System.Collections.Generic.List[object]
    $y = 8

    foreach ($test in $allTests) {
        $eksisterendeEntry = $eksisterendeMap[[int]$test.id]
        $erAktiv  = -not ($eksisterendeEntry -and $eksisterendeEntry.aktiv -eq $false)
        # Fiskum IT: standard ("out of box") er 5 minutter, ikke "auto" - se Manager\config\avansert-valg.json
        $varighet = $(if ($eksisterendeEntry -and $eksisterendeEntry.varighet) { [string]$eksisterendeEntry.varighet } else { '5' })
        $stottet  = Test-StottetAvCpu -Krav $test.kreverInstruksjonssett

        # Fiskum IT (v0.8.2): merk de kuraterte "standardAnbefalt"-testene fra testplan.json
        # (samme sett som Get-StabilitetsPlan sin standard-fallback bruker) med stjerne+bold -
        # kun nar testen ogsa er CPU-stottet, ellers ville stjernen lovet noe gra-utingen
        # under reverserer uansett
        $erMarkert = $stottet -and ($test.standardAnbefalt -eq $true)

        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = ('{0}{1}: {2}' -f $(if ($erMarkert) { '★ ' } else { '' }), $test.id, $test.navn)
        $chk.Location = New-Object System.Drawing.Point(8,$y)
        $chk.Size = New-Object System.Drawing.Size(480,24)
        $chk.Font = New-Object System.Drawing.Font('Segoe UI', 9, $(if ($erMarkert) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))

        if ($stottet) {
            $chk.Checked = $erAktiv
            $chk.ForeColor = $dlgPanelForeColor
        }
        else {
            # Fiskum IT: IKKE Enabled=$false her - Windows tvinger da gjennom en for mork,
            # darlig lesbar gratoneoverstyring av selve teksten pa mork bakgrunn (samme funn
            # som for chkAutoSwitch, se Update-AssistertUiEnabled). Holder boksen interaktiv
            # i WinForms-forstand, men reverserer ethvert avhukingsforsok og dimmer teksten
            # manuelt til en fortsatt lesbar gra, for et reelt "gratt ut og kan ikke hukes av"
            $chk.Text = '{0} - krever {1} (ikke stottet av denne CPU-en)' -f $chk.Text, $test.kreverInstruksjonssett
            $chk.Checked = $false
            $chk.ForeColor = [System.Drawing.Color]::FromArgb(150,154,160)
            $chk.Add_CheckedChanged({
                if ($chk.Checked) { $chk.Checked = $false }
            }.GetNewClosure())
        }

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point(500,($y - 2))
        $txt.Size = New-Object System.Drawing.Size(100,24)
        $txt.Text = $varighet
        $txt.BackColor = [System.Drawing.Color]::FromArgb(45,48,56)
        $txt.ForeColor = $(if ($stottet) { $dlgPanelForeColor } else { [System.Drawing.Color]::FromArgb(150,154,160) })
        $txt.BorderStyle = 'FixedSingle'

        $panel.Controls.AddRange(@($chk, $txt))

        $rowControls.Add([pscustomobject]@{
            Id      = [int]$test.id
            CheckBox = $chk
            TextBox  = $txt
        })

        $y += 30
    }

    $btnOk = New-Button -Text 'OK' -X 420 -Y 592 -W 120 -H 34
    $btnAvbryt = New-Button -Text 'Avbryt' -X 552 -Y 592 -W 120 -H 34
    $dlg.Controls.AddRange(@($btnOk, $btnAvbryt))

    $btnAlleAuto.Add_Click({
        foreach ($row in $rowControls) { $row.TextBox.Text = 'auto' }
    }.GetNewClosure())

    $btnAlle5Min.Add_Click({
        foreach ($row in $rowControls) { $row.TextBox.Text = '5' }
    }.GetNewClosure())

    $btnAvbryt.Add_Click({
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    }.GetNewClosure())

    $btnOk.Add_Click({
        $nyttValg = @()

        foreach ($row in $rowControls) {
            $nyttValg += [pscustomobject]@{
                id       = $row.Id
                aktiv    = [bool]$row.CheckBox.Checked
                varighet = $row.TextBox.Text.Trim()
            }
        }

        Save-AvansertValg -Valg $nyttValg

        if ($App.State.modus -eq 'Stabilitet') {
            $App.Plan = @(Get-Plan -Modus 'Stabilitet')
            Sync-AktivTestId -State $App.State -Plan $App.Plan
        }

        $App.State.sisteHendelse = 'Avansert testvalg lagret.'
        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State
        Refresh-UiState

        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    }.GetNewClosure())

    [void]$dlg.ShowDialog()
}

function Build-Ui {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Fiskum IT CoreCycler Manager v$ManagerVersion"
    $form.StartPosition = 'CenterScreen'
    # Fiskum IT (v0.8.2): vinduet ble for hoyt til a passe godt pa en 1080p-skjerm (spesielt
    # med oppgavelinjen). Bredden er IKKE problemet (1260 er allerede smalt nok for bade
    # 1920- og 1280-bredde skjermer) - kun hoyden last ned/frigjort. Alt fra $groupModus og
    # nedover sitter na i en rullbar $mainPanel (se under), sa standardhoyden under er et
    # KOMFORT-mal, ikke en hard grense - et mindre vindu (ned til MinimumSize) scroller i
    # stedet for a klippe noe. Bredden er fortsatt last (Min- og MaximumSize.Width like)
    $form.Size = New-Object System.Drawing.Size(1260,900)
    $form.MinimumSize = New-Object System.Drawing.Size(1260,540)
    $form.MaximumSize = New-Object System.Drawing.Size(1260,3000)

    # Fiskum IT (v0.8.2): gjenopprett lagret vindusstorrelse/-posisjon fra forrige lukking
    # (se Add_FormClosing under) - 0 betyr "ikke lagret ennaa", bruk standardverdiene over.
    # Faller tilbake til CenterScreen hvis den lagrede posisjonen ikke lenger er synlig pa
    # noen tilkoblet skjerm (f.eks. en frakoblet ekstra skjerm)
    if ($App.State.vindueBredde -gt 0 -and $App.State.vindueHoyde -gt 0) {
        $form.Size = New-Object System.Drawing.Size([int]$App.State.vindueBredde, [int]$App.State.vindueHoyde)

        $lagretRect = New-Object System.Drawing.Rectangle([int]$App.State.vindueX, [int]$App.State.vindueY, [int]$App.State.vindueBredde, [int]$App.State.vindueHoyde)
        $synlig = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.Bounds.IntersectsWith($lagretRect) }

        if ($synlig) {
            $form.StartPosition = 'Manual'
            $form.Location = New-Object System.Drawing.Point([int]$App.State.vindueX, [int]$App.State.vindueY)
        }
    }

    # Fiskum IT: mork fagetema - samme morke farge som toppfeltet ($header), for et
    # sammenhengende utseende uten en lys/mork skjott mellom dem
    $form.BackColor = [System.Drawing.Color]::FromArgb(15,17,22)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(225,225,225)
    $form.KeyPreview = $true

    # Fiskum IT: gjenbrukt for alle GroupBox-paneler under, for et konsekvent mork tema
    $panelBackColor = [System.Drawing.Color]::FromArgb(30,33,40)
    $panelForeColor = [System.Drawing.Color]::FromArgb(225,225,225)

    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0,0)
    $header.Size = New-Object System.Drawing.Size(1260,96)
    $header.BackColor = [System.Drawing.Color]::FromArgb(15,17,22)
    $form.Controls.Add($header)

    # --- Fiskum IT logo (embedded base64) ---
    $logoB64 = 'iVBORw0KGgoAAAANSUhEUgAAAHgAAAB4CAYAAAA5ZDbSAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAABmJLR0QA/wD/AP+gvaeTAAAAB3RJTUUH4QwcDiIitr9NbwAAEBRJREFUeNrt3Xuw3GV9x/HXd/dcSAISiIgBBTTACRe1Urk41k5bi61X1EYQTQC1hUHFOl6xrTrawUKnWGvVKYoVcg7IbbwVtVWozoh4GRFvmHMCAcJN5GISMMnJOWd/3/7xOwkQc9lNds/u2e57ZjOZs/v77fN7Pvt9nu/zfZ7n+4SxkdSja6m0uwA9WktP4C6nJ3CX0xO4y+kJ3OX07eC9Ar/FFKLdBe2xTZLsw77ENo11RwKvwSkyV4noWXonkgrhUFwpLdiWGfZt70qihntErDa0tN2P0mNbjA3DIGrb+8jOLLPXNHc+O9So1/R2OT2Bu5yewF1OT+Aupydwl9MTuMvpCdzl9ATucnoCdzk9gbucnsBdTt/u36IDue9zEDZVQ0aYlKY2pr5IQ2e1u3QzyuwW+PblUDEZc6X5Ig4kD/SIhcRCkfsqW6mavj03Yr3R4d/iIdwn3IO1xDoZExa/od1P1HRml8C3X8vGe6nO21M41GQeQzyHPAyH4smYg0Ey5PRESyBz+j+RmMQ4uR73YiXFL40N34hbFP0PiyItfn27n3i3mR0Cj45Av4k1B6vO+xO8mjwW+8jsE/HYpFnGtifQYssfAwPlK56EheTzlJPgv5NuEVM3CNcZG7kJD83m+fDOFnjlMGlQ5vHEMvwpebCIvi0qbi3mLs1gByGwl3CCdALeIvNmXGV0+Kti02r609Dp7a6VhuhMgUeHYUDhBLwJLycXPM4KW0v5NXPxAuL55Jly8BLhCj9cfo/9gmcua3ct1UVnCbzqcvadFx549DCZb8OpePKMCbs15fdWiKNkXoAl5scFpnzDyuXjBudy8JJ219oO6Yxx8G0jjI1QK57kgUfOxJdwjoj2ibs1ERXieHxeulDGIlccwO3/2e6S7ZD2C/zgp3hkDzIXy/w0Po4jO0bY3yP2ls7GVU5a9SrjA31WjLS7UNulvQKvWM5De/WZt/EkXCHjDcQe7a6UnRIRxDG4WCXfr5Lzp1c4dhztE3h0hKj0i3iz9FkRz5l1azjDAvyD9K/EgUZHuO3SdpfqCbRH4LFhIueQb8f5IvZr6v1z+rXN93I66NEMgogBnC7zInKRySorl7eu7hpk5r3olcuJnKuI9+HdIubu9j1LwWp4APcQq3E71mEDuan8XCzAM3AQuVA6CHvBbvX5ESHzZehXybfhVqOX6YTQ58wKPLZ8OnAR78R7iDm7frMkbcQtxHdE/lBaqYwxr/FoFgYiPXs6CjX2GfrXh/G96R8clMV+OGQ6sPHH0nOxUOxiqxZB5ovxCRlnybzLHZfyjPYGRmZO4NIJqUin470i5uxyn5v5oIjrRF4t3ah/8AFZpENP2f41Q2fyWMM9jrutuupuG9d/V1//p7AIr5D5eiwWUW24XBHIv5TOF86xqfLwjNXvdpgZgVcOlw1oxYn4ELFX4zdJyg1xV+FS6WaMW7wbEaVFJ2/+3wZjI78o49AuJ5aQb5YxNB3CbICAk0WuovhHY8snDJ3W4grePq13slZcVk4AVGIxPiocsAuWW8i4EWeIeIeK71u8dPfE3ZqhpSxeWhB3ivwYXkN+ivxtw/cKVbyVyitklEGcNtF6gSsFcp7Mc6VjGp4NyFwv89PC60Ttq6Yq4w5vYRx4aCkroyBXkO8i3iTd0viNYh/pw3h287z2xmmtwLdeQ1EjnYzXNuSpZiLvF95JvleRdzv8DI6cgTnaly9l6DSiMqFW+4rIpeT1uyDUUcIHhbYFQlorcDFO9B1OvJMGh0PhLrxdVC8W1Y2OaMPszdBSqhA/lf5auKqhQXT5g34ZTpz5wpe0TuDRYTL7ybNFHl1/y5zIu/E2AxPXyFphqI3jyaHTS6HFnThH+kJDlpz2IJ5v4yZuu3zGi9/qPvh4nNpQv5selM4VlWtNDKahDpl3XbyUjAfwfnxr+6GyrQlkvw3zyu5qhmmNwKNbUgu8EfvXfV3mRpyn6kpZZMctlVm8FO4SzsWv6romssCYBVNMDM54kVsjcCAcg5fV7ViVBnGpcLGaWsdY7tYMFkzGT/D35EM7f6b4OfE1gqNPrucbmkrzBR5bjlpFWkLUab2JvAkXSOubOr5tNs84nf6CyGtxnsz1O3imW2V+wFTtjnbNb7fAgivoezpeUnfXmzbg44q40z5TbamIhhg6jZopRXGR8AHyLo91yoV0r3SRcLJafF2lyuHtcRSbG6q89Qpqk0S8UMSiuq4pPdJvifiKKvZ/Y1sqomGOOI2x4Y34JK7H82QeIuJu4UdURolNjmrv2urmClybQgxIJwoDdV0TsZ68RHq0jHrNIko/YRI/Nzby83KlB8i2Du0eR3MFjoSF0gnbXYD+BBJuwLcFDm9fUH63KT3+jkuu3rw+eNW1m5vbPxAOqrP/reEaRawTs8x6ZwnNE3hqTdlY8YfY+cK5clnN7fi2Ss5u6+1gmuhFBwMxSJ0zRuVHfqDIuzqvYesemidwIGIfHFKXYJmEH4mYVJltyylnD81zsoqEA9h2WtvfI6zBz0vnqoUhyVVfoFqtGN+0GCcKQ9Nrr9vfbmQW+I2IG/BdrG92eLbZS3b2w951PBgRa3Fnk7//iaxYzsRkRUydjI8o9xB3XnOR+ahwKfFhYyNN3a7anCb6zpHpFNMWKDdg75gI0q+ldS2zo7GR8nsiXogLcdj0joQWfeEuUJaPiL2It8h8t6LaZ7R504rNEXhic6XF/Ppjrnm/zImWtZRRoVItd05EHNC5e522UMGpYuqIHeT33qWb7j6Zm4McjewrGleeC9EasiCLJ+NZ7VwT1SBPw5FgVXMW6jVJYJub3Ym6rwmTqlm0uMXcA3vMAuudrpOoCPvK2Oy07jbNs+By5cJEAy1uVbZQ3jKQMmtMd9sPsPs0x4uuKhvbmI5l1Vf+uezC7oF6KbuMcWzsKMdqh3WSKawjqTanzM2x4MEB0+30+gZ+eHtKrRNYgXxYGp1FdvyANCY0LQdIcwQ+eHpPUObvtuzk2zn7q+Rg64yrQlYmMUz+tuMdrbJ8X1aJXzYzstfsFR1r8Lu6PhkW0OR9wY9naBmScB0+iHvLvcE67JWbFxteQZ6nyE2q402rhuZFskpP9SHlntwFdVwxXzoEo00rw9YsXsbY8KSKi6QbpVcKR5Mzv7xx2xS4X/oGviMr68xdx8FvbdoXNFFg8IAiH8Qz6xia7Ck8Vy3+28phLdtvVK66mHL7lTer9P/U1Pp+mS3s+xsi7TEwYWKysKg1z9/cyYa0QbhVxPE7vyDIfL5KzlHExpY83eN55imUjWL9Y/UuoHl9cDVIkyJubsBrPQaHd8LETrfSPIEP27xRK38m8pE6rzpQ+DPo1DREs53metGlZ/hL6Y76LggyTiL23ZL6t0dTaa7AEVQqD4m4sa5mNyCPI8vtlaOdk36oW2juhP+Bc7h7Q03Ft6QzRB1zw+X88RnC/1BZ2+4KaYixkTJdQ2EReZyIBWVQJW6WOSYqk+1OpdRcC97zr6bnHOIH6h3flnPwf0K+RpHcOkuseGzYdGqKt5LXEpfi48Ql5NeECymONjpS6a4cHYEnTdwvfL3u8GDGHvhbFYcpZkFfPDpMRp90jjJT32GPy69VEXEQzsHVwksMpnYlLG2+wEPLeKQ/8UXleQg7p9T02TiX2Kudv/i6CX+Bd283mVu5FGexdL7xOLRdE1qt2+Gf+Qvhq43thPcG8iyVqWq5DbUDKc+PeJbMj0yvQdsZR+LFZZ3MfHFbI/DiZYhJZcKy++q/MAZxrqJ6qko1Os6SS6fqEOJjZTrhusyyInLIeHDbzI/1W5xlJ28SLmvop1smDD1fUbxSMRkdEwApnaqF5PnCn9fd5JYLDyYMRhOz3NZP6wRevIxKTOEi6Wd1P1xAHIh/F31LqFaMXTbjFbOF2y7hV5eRDpU+hcbyMJQJU38gam3Zf9VaC54/h8lchQuJ9Y1dHE/HJ6j9jSzmTPd9M8vocnIu1eI4fB6vbijvcPmb/iZxffc5WbD/EvqrROWLuLLhJiriqdKF+GeRB3nHnTOT93Hskumk5QbVJpZIy0X8UWOrMxNWE+dLa9uVVKb1uSqLRLFe5AXCTQ17khHzhLfgamff8Drs2VKRV4xQVCvS0cS/ifysiKGG75OxgbzA1MAP2xlnb73ARyxFUFhJ/J3I+sbGTyAqMo7Dxcqm8kRjw3OMjZBNEvvWEVZfXlEpFgnvw5ekM4n5jd8sC/JzxKX6JtIR7QtXzky+6KGlZZNXqV2nqHyYvLDhnNGlEcyTlggvkr5JXmGlG627+kGbMj2lwTxUt32BjRMM9O2lls81XrxKxkuV+5h27cdfbov9snAeuaHd+b5mLuP70DLGRgphucyFMs8Vu5DSvxR6H+IU8pX4hfvHv4MfGRteKeM+mWvV7i9U9k5Hnlle99PPUquFOQOh2j8oPcXU1CEGqieQL8Kx00fU7vozlj7G/+I9Cr+xR/uPpZrZMxuGljI6vAn/ggHpXaKh/UyPUQ6n5kjHlTM5asRvcK+wWt9TV4l4xNjIhmmz2lvmfOWCwAOVe5mfjj3L1Ze72U+W4n5beJvC7fqCZ7Q/087Mn7pSrnTcgH+arpR37tbhHLHlnyoOEHmAdOw2PrTVn2LH7zfCllxfzlGLMQM1Du2MU0rb04aUa5bXCx/Fh+QupM3fLlv23G7jrc1/b6JXmwp8RThLEWMGJztGXNp58tnQaYgN0seJs8q0+bNs8V3mBvI/iLNl3OGIpSzqrEx97fUChpZSG5g0Z+015CnSVeWm8FlAukN4l/Be/Ho61XDH0X4376hTGJ9Pxi3EWcK5Mu/p3L1EuVHmNdOJRj+jiPWdKi6dIDClJR+xlMi1Ij6B12K5zDWdIXQiC5k34WyRbxb5Y1EUZSCnc+msE8DLoEDN2PAPpJ8Sy8k3yXwJsc/MB+xzsxP1K2Wy8itVnnS32hqGzmh3bdVFZwm8mVLocaPD15PfI14g8nQZJ5L7I1qeliFzA24Srpb+S9G/WqWWDjup3bXTEJ0p8GYWTwu9cuR63CDzaLwULyKPluYT1V0/A9FjI6Yy3cMGrBa+J3xV+r5a8bAjO2fY0yidLfBmykx4m6wYuUnhJ/ryk8rDJI8lj5XxbPLAMmCSg8IgYpuzOGFzvHiTsFF6CL8gfoIfYlS4n5jsuENBdoHZIfBmjtiSk3kNfmzFZT8WxcWYr8ywt78yBHkAsVDk3p4Y1agRa/Ew7sNduEd6SP9TNqqtTUMzf3BGK5ldAm9NOQ03iQenX7eB1SMQiqKyJQNQJEU1bRpM1Voael27Sz8jzG6Bt8fBWyx95k+i6jA6Yxzco2X0BO5yegJ3OT2Bu5yewF1OT+Aupydwl9MTuMvpCdzl9ATucnoCdzk7E7gT1sv02DE71Gg7kw1bFpI/TeYmYyM9S+9EUiHy6Ww/c/6OZpP2wZUipsyaQw/+nxFSqeF216vtSOAKntzuZ+ixM3Zse72mt8vpCdzl9ATucnoCdzk9gbuc/wOkqY/KH3t84wAAAA90RVh0QXV0aG9yAExvZ2FzdGVy9Fq0CgAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyMi0wMy0yMlQyMjoyMjo1MiswMDowMNDSmygAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMTctMTItMjhUMTQ6MzQ6MzQrMDA6MDBvfoVnAAAAAElFTkSuQmCC'
    try {
        $logoBytes = [Convert]::FromBase64String($logoB64)
        $logoMs = New-Object System.IO.MemoryStream(,$logoBytes)
        $logoImg = [System.Drawing.Image]::FromStream($logoMs)
        $logoBox = New-Object System.Windows.Forms.PictureBox
        $logoBox.Image = $logoImg
        $logoBox.SizeMode = 'Zoom'
        $logoBox.Location = New-Object System.Drawing.Point(16,12)
        $logoBox.Size = New-Object System.Drawing.Size(72,72)
        $logoBox.BackColor = [System.Drawing.Color]::Transparent
        $header.Controls.Add($logoBox)
        $iconBmp = New-Object System.Drawing.Bitmap($logoImg,32,32)
        $hIcon = $iconBmp.GetHicon()
        $form.Icon = [System.Drawing.Icon]::FromHandle($hIcon)
    } catch {}


    $title = New-Label -Text 'Fiskum IT CoreCycler Manager v0.8.2' -X 100 -Y 14 -W 800 -H 30 -Bold $true
    $title.ForeColor = [System.Drawing.Color]::White
    $title.Font = New-Object System.Drawing.Font('Segoe UI',18,[System.Drawing.FontStyle]::Bold)
    $header.Controls.Add($title)

    $subtitle = New-Label -Text 'Norsk kontrollflate for testplan, fremdrift, stopp og rapportering' -X 102 -Y 50 -W 900 -H 20
    $subtitle.ForeColor = [System.Drawing.Color]::White
    $header.Controls.Add($subtitle)

    $groupStatus = New-Object System.Windows.Forms.GroupBox
    $groupStatus.Text = 'Status'
    $groupStatus.Location = New-Object System.Drawing.Point(16,100)
    $groupStatus.Size = New-Object System.Drawing.Size(610,260)
    $groupStatus.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $groupStatus.BackColor = $panelBackColor
    $groupStatus.ForeColor = $panelForeColor
    $form.Controls.Add($groupStatus)

    $groupActions = New-Object System.Windows.Forms.GroupBox
    $groupActions.Text = 'Handlinger'
    $groupActions.Location = New-Object System.Drawing.Point(640,100)
    $groupActions.Size = New-Object System.Drawing.Size(590,260)
    $groupActions.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $groupActions.BackColor = $panelBackColor
    $groupActions.ForeColor = $panelForeColor
    $form.Controls.Add($groupActions)

    # Fiskum IT (v0.8.2): fast topp-sone (header + Status/Handlinger) er ALLTID synlig -
    # de "her og na"-feltene (status, aktiv test, PID, kjerne, offset) og Start/Stopp-
    # knappene skal aldri kunne scrolles bort. Alt under (Modus/Automatisk gjenoppretting/
    # Fremdrift/Siste logg) sitter i denne rullbare panelen i stedet - samme etablerte
    # AutoScroll-monster som allerede brukes i Show-AvansertDialog. Anchor=Top,Bottom,Left,
    # Right gjor at panelen automatisk fyller resten av klientarealet nar vinduet endrer
    # storrelse, uten en egen Resize-handler
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Location = New-Object System.Drawing.Point(0,364)
    $mainPanel.Size = New-Object System.Drawing.Size(1260,536)
    $mainPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $mainPanel.AutoScroll = $true
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(15,17,22)
    $form.Controls.Add($mainPanel)

    $lblStatus = New-Label -Text 'Status:' -X 18 -Y 28 -W 130 -H 22 -Bold $true
    $lblStatusValue = New-Label -Text '-' -X 170 -Y 28 -W 420 -H 22 -Bold $true

    $lblCurrentTest = New-Label -Text 'Aktiv test:' -X 18 -Y 56 -W 130 -H 22 -Bold $true
    $lblCurrentTestValue = New-Label -Text '-' -X 170 -Y 56 -W 420 -H 22

    $lblNext = New-Label -Text 'Neste test:' -X 18 -Y 84 -W 130 -H 22 -Bold $true
    $lblNextValue = New-Label -Text '-' -X 170 -Y 84 -W 420 -H 22

    $lblAdmin = New-Label -Text 'Administrator:' -X 18 -Y 112 -W 130 -H 22 -Bold $true
    $lblAdminValue = New-Label -Text '-' -X 170 -Y 112 -W 180 -H 22

    $lblPid = New-Label -Text 'Aktiv PID:' -X 18 -Y 140 -W 130 -H 22 -Bold $true
    $lblPidValue = New-Label -Text '-' -X 170 -Y 140 -W 180 -H 22

    $lblCore = New-Label -Text 'Kjerne-status:' -X 18 -Y 168 -W 130 -H 22 -Bold $true
    $lblCoreValue = New-Label -Text '-' -X 170 -Y 168 -W 420 -H 22

    $lblOffset = New-Label -Text 'Offset-rekke (alle kjerner):' -X 18 -Y 196 -W 250 -H 22 -Bold $true
    $lblOffsetValue = New-Label -Text '-' -X 18 -Y 220 -W 580 -H 34
    $lblOffsetValue.AutoSize = $false
    $lblOffsetValue.Font = New-Object System.Drawing.Font('Consolas',9,[System.Drawing.FontStyle]::Bold)

    $groupStatus.Controls.AddRange(@(
        $lblStatus,
        $lblStatusValue,
        $lblCurrentTest,
        $lblCurrentTestValue,
        $lblNext,
        $lblNextValue,
        $lblAdmin,
        $lblAdminValue,
        $lblPid,
        $lblPidValue,
        $lblCore,
        $lblCoreValue,
        $lblOffset,
        $lblOffsetValue
    ))

    $btnStart = New-Button -Text 'Start / Gjenoppta' -X 22 -Y 34 -W 170
    $btnStop = New-Button -Text 'Stopp test' -X 208 -Y 34 -W 140
    $btnOpenLog = New-Button -Text 'Åpne siste logg' -X 364 -Y 34 -W 180

    $btnOpenReport = New-Button -Text 'Åpne skrivebordsrapport' -X 22 -Y 82 -W 240
    $btnResetState = New-Button -Text 'Nullstill state' -X 278 -Y 82 -W 160
    $btnOpenConfigDir = New-Button -Text 'Åpne config-mappe' -X 454 -Y 82 -W 130
    $btnExit = New-Button -Text 'Avslutt' -X 454 -Y 130 -W 130

    $chkAutoContinue = New-Object System.Windows.Forms.CheckBox
    $chkAutoContinue.Text = 'Start neste test automatisk'
    $chkAutoContinue.Location = New-Object System.Drawing.Point(22,138)
    $chkAutoContinue.Size = New-Object System.Drawing.Size(280,24)
    $chkAutoContinue.Checked = $true
    $chkAutoContinue.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $chkAutoContinue.ForeColor = $panelForeColor
    # Fiskum IT: Flat-stil unngar at Windows tvinger gjennom sin egen (for morke, darlig
    # lesbare) grafarge for tekst hvis kontrollen skulle bli deaktivert
    $chkAutoContinue.FlatStyle = 'Flat'

    $lblHint = New-Label -Text 'Hurtigtaster: F5 = Start/Gjenoppta, Esc = Stopp' -X 22 -Y 172 -W 420 -H 24
    $lblHint2 = New-Label -Text 'Tips: Skrivebordsrapporten viser også sti til spenningslogg.' -X 22 -Y 198 -W 520 -H 24

    # Fiskum IT (v0.8.2): knappeteksten selv er ogsa indikatoren (endres til "Ny versjon
    # tilgjengelig: vX.Y.Z" + fremhevet farge nar Invoke-OppdateringssjekkVedOppstart finner
    # en - se App.Ui.btnSjekkOppdatering) i stedet for en egen label-kontroll, for a spare
    # den begrensede plassen i den faste (ikke-rullbare) topp-sonen
    $btnSjekkOppdatering = New-Button -Text 'Sjekk etter oppdatering' -X 22 -Y 224 -W 300 -H 30

    $groupActions.Controls.AddRange(@(
        $btnStart,
        $btnStop,
        $btnOpenLog,
        $btnOpenReport,
        $btnResetState,
        $btnOpenConfigDir,
        $btnExit,
        $chkAutoContinue,
        $lblHint,
        $lblHint2,
        $btnSjekkOppdatering
    ))

    $groupModus = New-Object System.Windows.Forms.GroupBox
    $groupModus.Text = 'Modus'
    # Fiskum IT (v0.8.2): Y er na relativ til $mainPanel (rullbar), ikke $form direkte
    $groupModus.Location = New-Object System.Drawing.Point(16,8)
    $groupModus.Size = New-Object System.Drawing.Size(1214,172)
    $groupModus.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $groupModus.BackColor = $panelBackColor
    $groupModus.ForeColor = $panelForeColor
    $mainPanel.Controls.Add($groupModus)

    # Fiskum IT: avgjor om "Assistert undervolting" overhodet kan velges pa denne CPU-en -
    # se Get-UndervoltStotteInfo. Brukes til a gra ut radioknappen under OG til a vise
    # forklaringen i $lblUndervoltStotte
    $undervoltStotte = Get-UndervoltStotteInfo

    $radioAssistert = New-Object System.Windows.Forms.RadioButton
    $radioAssistert.Text = 'Assistert undervolting (finn grensen per kjerne)'
    $radioAssistert.Location = New-Object System.Drawing.Point(18,26)
    $radioAssistert.Size = New-Object System.Drawing.Size(440,24)
    $radioAssistert.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $radioAssistert.FlatStyle = 'Flat'

    if ($undervoltStotte.Stottet) {
        $radioAssistert.ForeColor = $panelForeColor
    }
    else {
        # Fiskum IT: IKKE Enabled=$false - se den allerede etablerte begrunnelsen ved
        # chkAutoSwitch/Update-AssistertUiEnabled (Windows tvinger da gjennom en darlig
        # lesbar gratoneoverstyring av selve teksten). Holder radioknappen interaktiv, men
        # CheckedChanged-handleren under reverserer ethvert forsok pa a velge den, og
        # Switch-Modus avviser ogsa byttet som et ekstra forsvarslag
        $radioAssistert.Text = $radioAssistert.Text + ' - ikke stottet av denne CPU-en'
        $radioAssistert.ForeColor = [System.Drawing.Color]::FromArgb(150,154,160)
    }

    $radioStabilitet = New-Object System.Windows.Forms.RadioButton
    $radioStabilitet.Text = 'Vanlig stabilitetstest (full testplan)'
    $radioStabilitet.Location = New-Object System.Drawing.Point(18,54)
    $radioStabilitet.Size = New-Object System.Drawing.Size(440,24)
    $radioStabilitet.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $radioStabilitet.Checked = $true
    $radioStabilitet.ForeColor = $panelForeColor
    $radioStabilitet.FlatStyle = 'Flat'

    $btnAvansert = New-Button -Text 'Avansert...' -X 18 -Y 84 -W 160 -H 30

    # Fiskum IT: holdes alltid Enabled=$true - se Update-AssistertUiEnabled for hvorfor
    # (CheckBox.Enabled=$false tvinger gjennom en for mork, darlig lesbar tekstfarge fra
    # Windows uavhengig av FlatStyle/ForeColor). "Ikke relevant na" vises i stedet med en
    # dimmet ForeColor, satt av Update-AssistertUiEnabled like etter UI'et er bygget
    $chkAutoSwitch = New-Object System.Windows.Forms.CheckBox
    $chkAutoSwitch.Text = 'Gå automatisk videre til Vanlig stabilitetstest når Assistert undervolting er fullført'
    $chkAutoSwitch.Location = New-Object System.Drawing.Point(490,24)
    $chkAutoSwitch.Size = New-Object System.Drawing.Size(700,48)
    $chkAutoSwitch.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $chkAutoSwitch.Checked = $true
    $chkAutoSwitch.Enabled = $true
    $chkAutoSwitch.ForeColor = $panelForeColor
    $chkAutoSwitch.FlatStyle = 'Flat'

    $lblModusHint = New-Label -Text '"Avansert..." (valg av tester/varighet) gjelder kun Vanlig stabilitetstest.' -X 490 -Y 76 -W 700 -H 22

    # Fiskum IT: marker hvilken CPU som er oppdaget og hvorfor Assistert undervolting
    # er (eller ikke er) tilgjengelig - se Get-UndervoltStotteInfo
    # H=40 (i stedet for enlinjes 22): KortStatus-teksten kan variere i lengde avhengig av
    # CPU-modell/generasjon - lar etiketten brette til 2 linjer i stedet for a klippes/overlappe
    # GroupBox-en under (WinForms Label bretter automatisk nar AutoSize=false, som er default)
    $lblUndervoltStotte = New-Label -Text ('CPU oppdaget: {0} - {1}' -f $undervoltStotte.CpuNavn, $undervoltStotte.KortStatus) -X 18 -Y 122 -W 1170 -H 40
    $lblUndervoltStotte.ForeColor = [System.Drawing.Color]::FromArgb(150,154,160)

    $groupModus.Controls.AddRange(@(
        $radioAssistert,
        $radioStabilitet,
        $btnAvansert,
        $chkAutoSwitch,
        $lblModusHint,
        $lblUndervoltStotte
    ))

    # Fiskum IT (v0.8.2): ny GroupBox satt inn MELLOM groupModus og groupProgress -
    # groupModus var allerede full (6 kontroller), og alt under denne flyttes 150px ned
    $groupGjenoppretting = New-Object System.Windows.Forms.GroupBox
    $groupGjenoppretting.Text = 'Automatisk gjenoppretting'
    $groupGjenoppretting.Location = New-Object System.Drawing.Point(16,188)
    $groupGjenoppretting.Size = New-Object System.Drawing.Size(1214,162)
    $groupGjenoppretting.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $groupGjenoppretting.BackColor = $panelBackColor
    $groupGjenoppretting.ForeColor = $panelForeColor
    $mainPanel.Controls.Add($groupGjenoppretting)

    $chkAutostart = New-Object System.Windows.Forms.CheckBox
    $chkAutostart.Text = 'Autostart Manageren ved innlogging (Scheduled Task)'
    $chkAutostart.Location = New-Object System.Drawing.Point(18,28)
    $chkAutostart.Size = New-Object System.Drawing.Size(560,24)
    $chkAutostart.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $chkAutostart.ForeColor = $panelForeColor
    $chkAutostart.FlatStyle = 'Flat'

    $chkAutoRestart = New-Object System.Windows.Forms.CheckBox
    $chkAutoRestart.Text = 'Auto-restart datamaskinen ved krasj/feil (krever Autostart)'
    $chkAutoRestart.Location = New-Object System.Drawing.Point(18,56)
    $chkAutoRestart.Size = New-Object System.Drawing.Size(560,24)
    $chkAutoRestart.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $chkAutoRestart.ForeColor = $panelForeColor
    $chkAutoRestart.FlatStyle = 'Flat'

    $lblRestartWaitMinutes = New-Label -Text 'Minutter å vente etter restart før gjenopptak:' -X 18 -Y 86 -W 320 -H 22

    $numRestartWaitMinutes = New-Object System.Windows.Forms.NumericUpDown
    $numRestartWaitMinutes.Location = New-Object System.Drawing.Point(346,84)
    $numRestartWaitMinutes.Size = New-Object System.Drawing.Size(70,24)
    $numRestartWaitMinutes.Minimum = 1
    $numRestartWaitMinutes.Maximum = 60
    $numRestartWaitMinutes.Value = 5
    $numRestartWaitMinutes.Font = New-Object System.Drawing.Font('Segoe UI',9)

    # Fiskum IT: NumericUpDown har en intern TextBox+spinner som ikke alltid arver
    # ForeColor/BackColor like rent som Label/CheckBox - kosmetisk avvik pa enkelte
    # Windows-tema er akseptert, ingen funksjonell konsekvens
    $numRestartWaitMinutes.BackColor = $panelBackColor
    $numRestartWaitMinutes.ForeColor = $panelForeColor

    $lblGjenopprettingHint = New-Label -Text 'Med auto-restart på: du blir spurt om å bekrefte Windows-passordet ditt når du trykker "Start" (ikke når en feil oppstår) - kun hvis autologon ikke allerede er satt opp.' -X 18 -Y 112 -W 1170 -H 22
    $lblGjenopprettingHint.ForeColor = [System.Drawing.Color]::FromArgb(150,154,160)

    $lblGjenopprettingHint2 = New-Label -Text 'Har kontoen ingen passord? Trykk bare OK uten å skrive noe. Husk: det er PASSORDET (ikke PIN-koden/Windows Hello) som skal fylles inn.' -X 18 -Y 134 -W 1170 -H 22
    $lblGjenopprettingHint2.ForeColor = [System.Drawing.Color]::FromArgb(150,154,160)

    $groupGjenoppretting.Controls.AddRange(@(
        $chkAutostart,
        $chkAutoRestart,
        $lblRestartWaitMinutes,
        $numRestartWaitMinutes,
        $lblGjenopprettingHint,
        $lblGjenopprettingHint2
    ))

    $groupProgress = New-Object System.Windows.Forms.GroupBox
    $groupProgress.Text = 'Fremdrift'
    $groupProgress.Location = New-Object System.Drawing.Point(16,358)
    $groupProgress.Size = New-Object System.Drawing.Size(1214,90)
    $groupProgress.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $groupProgress.BackColor = $panelBackColor
    $groupProgress.ForeColor = $panelForeColor
    $mainPanel.Controls.Add($groupProgress)

    # Fiskum IT: Windows tegner selve fremdriftsindikatoren med eget OS-tema uavhengig av
    # BackColor/ForeColor (krever owner-draw for full kontroll) - rammen rundt blir likevel
    # mork, og selve baren er fortsatt godt synlig
    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(18,32)
    $progress.Size = New-Object System.Drawing.Size(980,24)
    $progress.Minimum = 0
    $progress.Maximum = 100
    $progress.Value = 0
    $progress.BackColor = $panelBackColor
    $progress.ForeColor = [System.Drawing.Color]::FromArgb(13,234,160)

    $lblProgressValue = New-Label -Text '0/0 tester (0%)' -X 1010 -Y 34 -W 180 -H 22 -Bold $true

    $groupProgress.Controls.AddRange(@(
        $progress,
        $lblProgressValue
    ))

    # Fiskum IT: dette er na hovedinnholdet i vinduet - CoreCycler-konsollen kjores skjult
    # (se Start-CoreCyclerStep), og denne RichTextBox-en viser i stedet et fargelagt,
    # filtrert ekvivalent av det konsollvinduet (sammen med "State og historikk", som
    # tidligere lå her som et eget panel - rent Manager-internt bokforing, fjernet fra
    # UI'et siden det ikke er interessant for vanlige brukere, men fortsatt fullt
    # tilgjengelig i Manager\logs\ - se Add-History)
    $groupLog = New-Object System.Windows.Forms.GroupBox
    $groupLog.Text = 'Siste CoreCycler-logg'
    $groupLog.Location = New-Object System.Drawing.Point(16,456)
    # Fiskum IT (v0.8.2): redusert fra 380 - na i en rullbar panel, sa dette er kun et
    # komfort-mal for standardvisningen, ikke en hard grense
    $groupLog.Size = New-Object System.Drawing.Size(1214,260)
    $groupLog.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $groupLog.BackColor = $panelBackColor
    $groupLog.ForeColor = $panelForeColor
    $mainPanel.Controls.Add($groupLog)

    $lblLastLog = New-Label -Text 'Loggfil:' -X 16 -Y 26 -W 90 -H 22 -Bold $true
    $lblLastLogValue = New-Label -Text '-' -X 110 -Y 26 -W 1080 -H 22

    $txtLog = New-Object System.Windows.Forms.RichTextBox
    $txtLog.Location = New-Object System.Drawing.Point(16,52)
    # Fiskum IT (v0.8.2): redusert fra 300 til 180 - matcher $groupLog sin nye, lavere
    # standardhoyde (260, var 380). Vinduet/panelen er na rullbar uansett
    $txtLog.Size = New-Object System.Drawing.Size(1178,180)
    $txtLog.BackColor = [System.Drawing.Color]::Black
    $txtLog.ReadOnly = $true
    $txtLog.Font = New-Object System.Drawing.Font('Consolas',9)

    $groupLog.Controls.AddRange(@(
        $lblLastLog,
        $lblLastLogValue,
        $txtLog
    ))

    $App.Ui.Form = $form
    $App.Ui.chkAutoContinue = $chkAutoContinue
    $App.Ui.btnExit = $btnExit
    $App.Ui.lblStatusValue = $lblStatusValue
    $App.Ui.lblCurrentTestValue = $lblCurrentTestValue
    $App.Ui.lblNextValue = $lblNextValue
    $App.Ui.lblAdminValue = $lblAdminValue
    $App.Ui.lblPidValue = $lblPidValue
    $App.Ui.lblCoreValue = $lblCoreValue
    $App.Ui.lblOffsetValue = $lblOffsetValue
    $App.Ui.lblProgressValue = $lblProgressValue
    $App.Ui.progress = $progress
    $App.Ui.lblLastLogValue = $lblLastLogValue
    $App.Ui.txtLog = $txtLog
    $App.Ui.radioAssistert = $radioAssistert
    $App.Ui.radioStabilitet = $radioStabilitet
    $App.Ui.btnAvansert = $btnAvansert
    $App.Ui.chkAutoSwitch = $chkAutoSwitch
    $App.Ui.chkAutostart = $chkAutostart
    $App.Ui.chkAutoRestart = $chkAutoRestart
    $App.Ui.numRestartWaitMinutes = $numRestartWaitMinutes
    $App.Ui.btnSjekkOppdatering = $btnSjekkOppdatering

    $btnStart.Add_Click({
        Invoke-ProaktivAutologonOppsett
        Start-CurrentOrResume
    })

    $btnStop.Add_Click({
        Stop-CurrentRun
        Refresh-UiState
    })

    $btnOpenLog.Add_Click({
        Open-LatestLog
    })

    $btnOpenReport.Add_Click({
        Open-DesktopReport
    })

    $btnResetState.Add_Click({
        Reset-StateToStart
    })

    $btnOpenConfigDir.Add_Click({
        Start-Process explorer.exe -ArgumentList ('"{0}"' -f $ConfigDir)
    })

    $btnExit.Add_Click({
        param($sender, $eventArgs)

        $sender.FindForm().Close()
    })

    $chkAutoContinue.Add_CheckedChanged({
        param($sender, $eventArgs)

        $App.AutoContinue = [bool]$sender.Checked
        $App.State.sisteHendelse = "Autofortsett er satt til: $($App.AutoContinue)"

        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State
        Refresh-UiState
    })

    $radioAssistert.Add_CheckedChanged({
        param($sender, $eventArgs)

        if ($sender.Checked) {
            if (Switch-Modus -NyModus 'AssistertUndervolting') {
                Refresh-UiState
            }
            else {
                # Bytte ble avvist (en test kjorer, eller CPU-en stotter ikke Assistert
                # undervolting - se Switch-Modus) - tilbakefor radioknappen
                $radioStabilitet.Checked = $true
            }
        }
    })

    $radioStabilitet.Add_CheckedChanged({
        param($sender, $eventArgs)

        if ($sender.Checked) {
            if (Switch-Modus -NyModus 'Stabilitet') {
                Refresh-UiState
            }
            else {
                $radioAssistert.Checked = $true
            }
        }
    })

    $chkAutoSwitch.Add_CheckedChanged({
        param($sender, $eventArgs)

        $App.State.autoSwitchToStability = [bool]$sender.Checked
        $App.State.sisteHendelse = "Auto-overgang til Vanlig stabilitetstest er satt til: $($App.State.autoSwitchToStability)"

        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State

        # Fiskum IT: "Avansert..." skal vaere tilgjengelig i Assistert undervolting-modus
        # naar denne er avhuket, se Update-AssistertUiEnabled
        Update-AssistertUiEnabled
    })

    $chkAutostart.Add_CheckedChanged({
        param($sender, $eventArgs)

        $App.State.autostartTask = [bool]$sender.Checked
        $App.State.sisteHendelse = "Autostart ved innlogging er satt til: $($App.State.autostartTask)"

        # Fiskum IT (v0.8.2): auto-restart uten autostart er meningslost (gjenopptak etter
        # reboot krever at Manageren faktisk starter pa nytt) - reverser et forsok pa a
        # skru av autostart mens auto-restart fortsatt star pa, samme monster som
        # $radioAssistert sin egen reversering for en ustottet CPU (Switch-Modus)
        if ((-not $App.State.autostartTask) -and $App.State.autoRestartOnFeil) {
            $App.State.autostartTask = $true
            $sender.Checked = $true
        }

        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State
    })

    $chkAutoRestart.Add_CheckedChanged({
        param($sender, $eventArgs)

        $App.State.autoRestartOnFeil = [bool]$sender.Checked

        if ($App.State.autoRestartOnFeil -and -not $App.State.autostartTask) {
            $App.State.autostartTask = $true

            # Fiskum IT: IKKE referer den lokale $chkAutostart-variabelen her - denne
            # script-blocken kjores av WinForms LANGT etter at Build-Ui (som
            # $chkAutostart kun finnes lokalt inni) har returnert, og PowerShell fanger
            # IKKE opp den lokale variabelen som en closure i en Add_CheckedChanged-
            # handler. $App.Ui.chkAutostart er trygt, siden $App er i script-scope
            # (samme monster brukt av alle andre handlere i denne filen)
            if ($App.Ui.chkAutostart) {
                $App.Ui.chkAutostart.Checked = $true
            }
        }

        $App.State.sisteHendelse = "Auto-restart ved krasj/feil er satt til: $($App.State.autoRestartOnFeil)"

        Add-History -State $App.State -Message $App.State.sisteHendelse
        Save-State -State $App.State
    })

    $numRestartWaitMinutes.Add_ValueChanged({
        param($sender, $eventArgs)

        $App.State.restartWaitMinutes = [int]$sender.Value
        Save-State -State $App.State
    })

    $btnAvansert.Add_Click({
        Show-AvansertDialog
    })

    $btnSjekkOppdatering.Add_Click({
        # Fiskum IT (v0.8.2): et eksplisitt klikk ignorerer 2-timers cachen fra
        # Invoke-OppdateringssjekkVedOppstart - et bevisst brukervalg skal alltid gi et
        # live svar. Bruker $App.Ui/$App.State (ikke de bare lokale variablene) inni
        # handleren - Build-Ui sitt eget stack-frame er borte naar dette faktisk fyrer
        $resultat = Test-NyVersjonTilgjengelig
        $App.State.sisteOppdateringssjekk = Get-NowIso
        Save-State -State $App.State

        if (-not $resultat.Forsokt) {
            [System.Windows.Forms.MessageBox]::Show(
                'Kunne ikke sjekke etter oppdatering (ingen internettforbindelse, eller GitHub svarte ikke). Se Manager-loggen for detaljer.',
                'Fiskum IT CoreCycler Manager',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        if ($resultat.NyVersjonTilgjengelig) {
            $App.Ui.btnSjekkOppdatering.Text = "Ny versjon tilgjengelig: v$($resultat.SisteVersjon)"
            $App.Ui.btnSjekkOppdatering.BackColor = [System.Drawing.Color]::FromArgb(255,193,7)

            $svar = [System.Windows.Forms.MessageBox]::Show(
                "Ny versjon tilgjengelig: v$($resultat.SisteVersjon) (du har v$ManagerVersion).`r`n`r`nÅpne nedlastingssiden?",
                'Fiskum IT CoreCycler Manager',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($svar -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Process $resultat.Url
            }
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Du har siste versjon (v$ManagerVersion).",
                'Fiskum IT CoreCycler Manager',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })

    $form.Add_KeyDown({
        param($sender,$e)

        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
            Invoke-ProaktivAutologonOppsett
            Start-CurrentOrResume
        }
        elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            Stop-CurrentRun
            Refresh-UiState
        }
    })

    $form.Add_FormClosing({
        param($sender, $e)

        if ($App.State.status -eq 'Kjører') {
            $res = [System.Windows.Forms.MessageBox]::Show(
                'En test kjører fortsatt. Vil du stoppe testen og lukke manageren?',
                'Fiskum IT CoreCycler Manager',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                Stop-CurrentRun
            }
            else {
                $e.Cancel = $true
            }
        }

        # Fiskum IT (v0.8.2): lagre vindusstorrelse/-posisjon for neste oppstart - EFTER
        # stopp-bekreftelsen over, slik at en avbrutt lukking ($e.Cancel) ikke lagrer noe.
        # Bruker RestoreBounds (ikke Size/Location direkte) nar vinduet er minimert/maksimert,
        # ellers ville vi lagret den minimerte/maksimerte storrelsen, ikke den reelle
        if (-not $e.Cancel) {
            $bounds = $(if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) { New-Object System.Drawing.Rectangle($form.Location, $form.Size) } else { $form.RestoreBounds })

            $App.State.vindueBredde = $bounds.Width
            $App.State.vindueHoyde  = $bounds.Height
            $App.State.vindueX      = $bounds.X
            $App.State.vindueY      = $bounds.Y

            Save-State -State $App.State
        }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1500

    $timer.Add_Tick({
        # Fiskum IT: hver av disse i EGEN try/catch - en feil i en av dem skal IKKE kunne
        # sulteforde de andre. Sett i praksis pa WANJA-GAMER 2026-06-21: en feil i
        # Refresh-CoreCyclerLogView (Get-KonsollLinjeFarge sin Mandatory-pa-tom-streng-bug)
        # avbrøt HELE try-blokken for Handle-ProcessFinished/Refresh-UiState noensinne nadde
        # a kjore - Offset-rekken/skrivebordsloggen fikk dermed aldri den faktiske, korrekte
        # verdien fra motorens snapshot-fil, til tross for at sokemotoren selv fungerte helt
        # riktig i bakgrunnen hele tiden
        try {
            Refresh-CoreCyclerLogView
        }
        catch {
            Write-ManagerLog -Text "Timer-feil (Refresh-CoreCyclerLogView): $($_.Exception.Message)"
        }

        try {
            Handle-ProcessFinished
        }
        catch {
            Write-ManagerLog -Text "Timer-feil (Handle-ProcessFinished): $($_.Exception.Message)"
        }

        try {
            Refresh-UiState
        }
        catch {
            Write-ManagerLog -Text "Timer-feil (Refresh-UiState): $($_.Exception.Message)"
        }

        try {
            Write-SystemResourceLogIfDue
        }
        catch {
            Write-ManagerLog -Text "Timer-feil (Write-SystemResourceLogIfDue): $($_.Exception.Message)"
        }

        try {
            # Fiskum IT (v0.8.2): se Check-PendingAutoResume - dekker tilfellet der
            # Manageren allerede star og kjorer nar ventetiden etter en auto-restart
            # gar ut, IKKE bare engangssjekken ved oppstart (unngar en blokkerende
            # Start-Sleep i en WinForms-app)
            if ($Script:PendingAutoResumeNotBefore -and (Get-Date) -ge $Script:PendingAutoResumeNotBefore) {
                Write-ManagerLog -Text "Ventetid etter auto-restart er over (oppdaget i timer-tick). Gjenopptar testen automatisk."
                $Script:PendingAutoResumeNotBefore = $null
                $App.State.pendingAutoResume = $false
                $App.State.pendingAutoResumeNotBefore = ''
                Save-State -State $App.State
                Start-CurrentOrResume
            }
        }
        catch {
            Write-ManagerLog -Text "Timer-feil (PendingAutoResume): $($_.Exception.Message)"
        }
    })

    $timer.Start()
    $App.Timer = $timer

    return $form
}

if (-not (Test-Path -LiteralPath $CoreCyclerScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Fant ikke script-corecycler.ps1 i `n$CoreCyclerScript`n`nKontroller mappeoppsettet før du starter manageren.",
        'Fiskum IT CoreCycler Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null

    exit 1
}

Start-PaaNyttSomAdministrator

# Fiskum IT: State maa lastes for Plan, siden Get-Plan na grenes pa $App.State.modus
$App.State = Get-State
$App.Plan  = @(Get-Plan -Modus $App.State.modus)

if (-not $App.Plan) {
    [System.Windows.Forms.MessageBox]::Show(
        "Fant ikke eller kunne ikke lese testplan.json i `n$PlanFile",
        'Fiskum IT CoreCycler Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null

    exit 1
}

# Fiskum IT: aktivTestId i en lagret state.json kan peke til en test som nylig ble
# deaktivert via Avansert-valg (eller en ny default som denne) - sorg for at den
# peker til en test som faktisk finnes i $App.Plan foer noe annet leser den
$gammelAktivTestId = [int]$App.State.aktivTestId
Sync-AktivTestId -State $App.State -Plan $App.Plan

if ([int]$App.State.aktivTestId -ne $gammelAktivTestId) {
    Save-State -State $App.State
}

Clear-StaleRunningState -State $App.State
Check-StaleCoreCyclerProcessesOnStartup -State $App.State
Check-PendingAutoResume -State $App.State

Write-ManagerLog -Text "Fiskum IT CoreCycler Manager v$ManagerVersion startet."
Add-History -State $App.State -Message 'Manager startet'

# Fiskum IT: logger CPU-instruksjonssett tidlig - nyttig for feilsoking (f.eks. via
# Collect-FiskumITDiagnostics) hvis en bruker lurer pa hvorfor enkelte tester er gratt
# ut i "Avansert...", eller ikke kjorer i den vanlige stabilitetstest-planen
$cpuCapStartup = Get-CpuInstruksjonssett
Write-ManagerLog -Text ('CPU-instruksjonssett oppdaget: AVX={0}, AVX2={1}, AVX512={2}' -f $cpuCapStartup.AVX, $cpuCapStartup.AVX2, $cpuCapStartup.AVX512)

# Fiskum IT: logger den fulle forklaringen for Assistert undervolting-stotte ved oppstart -
# samme info som vises kortere i "Modus"-panelet, men nyttig i sin helhet for feilsoking
# (Collect-FiskumITDiagnostics) hvis en bruker rapporterer at funksjonen ikke virker som forventet
$undervoltStotteStartup = Get-UndervoltStotteInfo
Write-ManagerLog -Text ('Assistert undervolting-stotte: {0} (stottet={1}) - {2}' -f $undervoltStotteStartup.CpuNavn, $undervoltStotteStartup.Stottet, $undervoltStotteStartup.Forklaring)

# Forsoek aa fylle "Offset-rekke" allerede ved oppstart (ryzen-smu-cli -> logg -> aktiv config)
try {
    $bootTest = Get-CurrentTest -Plan $App.Plan -State $App.State
    Initialize-OffsetsFromLogAndConfig -Test $bootTest
}
catch {
    Write-ManagerLog -Text "Kunne ikke initialisere Offset-rekke ved oppstart: $($_.Exception.Message)"
}

Save-State -State $App.State
Write-DesktopStatusReport -State $App.State -Plan $App.Plan

$form = Build-Ui

# Fiskum IT: gjenspeil lastet state i modus-knappene/checkboksen, uten aa trigge Switch-Modus
# (som ville nullstilt aktivTestId) - radioknappene speiler bare hva som allerede er lastet
if ($App.State.modus -eq 'AssistertUndervolting' -and $App.Ui.radioAssistert) {
    $App.Ui.radioAssistert.Checked = $true
}
elseif ($App.Ui.radioStabilitet) {
    $App.Ui.radioStabilitet.Checked = $true
}

if ($App.Ui.chkAutoSwitch) {
    $App.Ui.chkAutoSwitch.Checked = [bool]$App.State.autoSwitchToStability
}

if ($App.Ui.chkAutostart) {
    $App.Ui.chkAutostart.Checked = [bool]$App.State.autostartTask
}

if ($App.Ui.chkAutoRestart) {
    $App.Ui.chkAutoRestart.Checked = [bool]$App.State.autoRestartOnFeil
}

if ($App.Ui.numRestartWaitMinutes) {
    $App.Ui.numRestartWaitMinutes.Value = [int]$App.State.restartWaitMinutes
}

Update-AssistertUiEnabled
Refresh-UiState
Refresh-CoreCyclerLogView

# Fiskum IT (v0.8.2): automatisk, cachet (maks hvert 2. time) oppdateringssjekk mot GitHub -
# se Invoke-OppdateringssjekkVedOppstart. Etter Build-Ui (knappen ma finnes for at et funn
# skal kunne vises) og FOR ShowDialog - kort timeout internt, blokkerer aldri lenge
Invoke-OppdateringssjekkVedOppstart -State $App.State

# Fiskum IT: en krasj ble oppdaget og korrigert under Clear-StaleRunningState ovenfor -
# gjenoppta testen automatisk na som UI-et er klart
if ($PendingCrashResume) {
    Start-CurrentOrResume
    Refresh-UiState
}

# Fiskum IT (v0.8.2): se Check-PendingAutoResume - ventetiden etter en auto-utlost
# restart var allerede over da Manageren startet opp na, gjenoppta umiddelbart
if ($PendingAutoResumeAfterStartup) {
    Start-CurrentOrResume
    Refresh-UiState
}

[void]$form.ShowDialog()