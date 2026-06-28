<#
Fiskum IT: analyserer en HWiNFO64 CSV-eksport fra en lengre stabilitetstest (f.eks. OCCT) og
finner test-faser AUTOMATISK, basert pa endringer i kjerneklokke/effekt-signaturen - i stedet
for at man ma telle/lese radvis manuelt (se Utviklingslogg-UI-Stabilitet.md for bakgrunnen:
en manuell gjennomgang av en 12-timers OCCT-logg fant 6 distinkte faser pa denne maten).

Forutsetninger om CSV-formatet (bekreftet mot en faktisk HWiNFO64-eksport - kan avvike pa andre
maskiner/sprakinnstillinger, se -Verbose for hvilke kolonner som faktisk ble funnet):
- Komma-separert, PUNKTUM som desimaltegn, "Date"/"Time" forst (format DD.MM.AAAA / TT:MM:SS.mmm)
- Ingen kommaer INNI anforte feltverdier (en enkel komma-splitt er derfor trygg)
- Kolonneoverskriftene er pa norsk (samme sprak som HWiNFO selv er satt til) - kolonnegjenkjenningen
  under bruker flere mulige monstre per malt verdi for a tale noe variasjon, men er IKKE testet mot
  en faktisk Intel-maskin sin eksport enda. Kjor med -Verbose forste gang pa en ny maskintype for a
  se hvilke kolonner som ble funnet/ikke funnet.

Bruk:
  .\Analyser-HWiNFOLogg.ps1 -CsvPath "C:\...\logg.csv"
  .\Analyser-HWiNFOLogg.ps1 -CsvPath "C:\...\logg.csv" -MaksTimer 12.1666 -Verbose

Arbeidsflyt for raa-loggene selv (ikke noe skriptet gjor automatisk): nye HWiNFO/OCCT-logger
legges forst i "Loggfiler for utvikling\". Nar en logg er ferdig analysert med dette skriptet,
flyttes BADE raa-CSV-en og den genererte "-analyse.txt"-filen til "Sporingslogg\", omdopt med
maskinnavnet forst i filnavnet (f.eks. "NR-GAMER - 12 timer Stabilitetstest - ....CSV"). Begge
mapper er lokale/ikke-versjonerte (se .gitignore) - raa-loggene kan bli 100+ MB per fil.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    # 0 = hele loggen. Sett f.eks. til 12.1666 (12t10m) for kun a se pa starten av en lengre logg.
    [double]$MaksTimer = 0,

    [int]$BucketMinutter = 1,

    # Hvor mange % endring i snitt-klokke/-effekt (sammenlignet med inneverende fases snitt) som
    # skal til, BEKREFTET over 2 etterfolgende bucket, for at det regnes som et faseskifte.
    [double]$TerskelKlokkeProsent = 2.5,
    [double]$TerskelEffektProsent = 4.0,

    # Faser kortere enn dette slas sammen med foregaende fase - filtrerer bort stoy-utslag
    [double]$MinFaseMinutter = 15
)

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "Fant ikke filen: $CsvPath"
}

function Find-KolonneIndeks {
    param([string[]]$Headere, [string[]]$Monstre, [string[]]$Unnga = @())
    foreach ($monster in $Monstre) {
        for ($i = 0; $i -lt $Headere.Count; $i++) {
            if ($Headere[$i] -notmatch $monster) { continue }
            $skipDenne = $false
            foreach ($u in $Unnga) {
                if ($Headere[$i] -match $u) { $skipDenne = $true; break }
            }
            if (-not $skipDenne) { return $i }
        }
    }
    return -1
}

function Find-AlleKolonneIndekser {
    param([string[]]$Headere, [string]$Monster, [string[]]$Unnga = @())
    $treff = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $Headere.Count; $i++) {
        if ($Headere[$i] -notmatch $Monster) { continue }
        $skipDenne = $false
        foreach ($u in $Unnga) {
            if ($Headere[$i] -match $u) { $skipDenne = $true; break }
        }
        if (-not $skipDenne) { $treff.Add($i) }
    }
    return $treff
}

function ConvertTo-Tidspunkt {
    param([string]$Dato, [string]$Tid)
    $dDel = $Dato.Split('.')
    $tDel = $Tid.Split(':')
    $sekDel = $tDel[2].Split('.')
    $ms = 0
    if ($sekDel.Count -gt 1) {
        $msTekst = $sekDel[1].PadRight(3, '0').Substring(0, 3)
        $ms = [int]$msTekst
    }
    return [DateTime]::new([int]$dDel[2], [int]$dDel[1], [int]$dDel[0], [int]$tDel[0], [int]$tDel[1], [int]$sekDel[0], $ms)
}

Write-Host "Leser header fra: $CsvPath"
$forsteLinje = $null
foreach ($linje in [System.IO.File]::ReadLines($CsvPath)) {
    $forsteLinje = $linje
    break
}
if (-not $forsteLinje) { throw "Filen er tom." }

$headerFelt = $forsteLinje.TrimStart([char]0xFEFF).Split(',') | ForEach-Object { $_.Trim('"') }

$idxDato      = Find-KolonneIndeks -Headere $headerFelt -Monstre @('^Date$')
$idxTid       = Find-KolonneIndeks -Headere $headerFelt -Monstre @('^Time$')
$idxKlokke    = Find-KolonneIndeks -Headere $headerFelt -Monstre @('Kjerneklokker \(avg\)', 'Core Clocks \(avg\)')
$idxTemp      = Find-KolonneIndeks -Headere $headerFelt -Monstre @('Tctl/Tdie', 'CPU Package.*°C', 'CPU \(gjennomsnittlig\)', 'CPU.*°C') -Unnga @('case', 'IOD', 'CCD', 'L3')
$idxEffekt    = Find-KolonneIndeks -Headere $headerFelt -Monstre @('CPU full strømforbruk', 'CPU Package Power', 'CPU.*\[W\]') -Unnga @('Core \d', 'Kjernenes')
$idxMem       = Find-KolonneIndeks -Headere $headerFelt -Monstre @('Fysisk minnebelastning', 'Physical Memory Load')
$idxGpuTemp   = Find-KolonneIndeks -Headere $headerFelt -Monstre @('GPU temperatur', 'GPU Temperature')
$idxGpuEffekt = Find-KolonneIndeks -Headere $headerFelt -Monstre @('Total Graphics Power', 'Total Board Power', 'GPU.*[Ee]ffekt.*\[W\]', 'GPU Power')
$idxGpuBruk   = Find-KolonneIndeks -Headere $headerFelt -Monstre @('GPU-bruk', 'GPU Utilization')
$idxKjerner   = Find-AlleKolonneIndekser -Headere $headerFelt -Monster '^Core \d+ Klokke \(' -Unnga @('Effektiv')
if ($idxKjerner.Count -eq 0) {
    $idxKjerner = Find-AlleKolonneIndekser -Headere $headerFelt -Monster '^Core \d+ Clock \(' -Unnga @('Effective')
}

function Rapporter-Kolonne {
    param([string]$Navn, [int]$Idx)
    if ($Idx -ge 0) {
        Write-Verbose "  $Navn -> kolonne $Idx ($($headerFelt[$Idx]))"
    } else {
        Write-Warning "  $Navn -> IKKE FUNNET i denne loggen (hoppes over)"
    }
}
Write-Verbose 'Kolonner funnet:'
Rapporter-Kolonne 'Dato' $idxDato
Rapporter-Kolonne 'Tid' $idxTid
Rapporter-Kolonne 'Kjerneklokke (avg)' $idxKlokke
Rapporter-Kolonne 'CPU-temperatur' $idxTemp
Rapporter-Kolonne 'CPU-effekt' $idxEffekt
Rapporter-Kolonne 'Minnebelastning' $idxMem
Rapporter-Kolonne 'GPU-temperatur' $idxGpuTemp
Rapporter-Kolonne 'GPU-effekt' $idxGpuEffekt
Rapporter-Kolonne 'GPU-bruk' $idxGpuBruk
Write-Verbose "  Per-kjerne-klokker -> $($idxKjerner.Count) kolonner funnet"

if ($idxDato -lt 0 -or $idxTid -lt 0) {
    throw "Fant ikke Date/Time-kolonnene - kan ikke fortsette uten disse."
}

$maksSekunder = if ($MaksTimer -gt 0) { $MaksTimer * 3600 } else { [double]::MaxValue }

$buckets = New-Object System.Collections.Generic.List[object]
$bucketAntall = @{}
$startTid = $null
$forrigeElapsed = -1
$intervallSamples = New-Object System.Collections.Generic.List[double]
$medianIntervall = 0.5
$hullFunnet = New-Object System.Collections.Generic.List[string]
$radNr = 0
$sisteTid = $null

function Hent-ElleTryggBucket {
    param($BucketTabell, [System.Collections.Generic.List[object]]$BucketListe, [int]$Idx)
    if ($BucketTabell.ContainsKey($Idx)) { return $BucketTabell[$Idx] }
    $ny = [pscustomobject]@{
        SumKlokke = 0.0; SumTemp = 0.0; SumEffekt = 0.0; SumGpuTemp = 0.0; SumGpuEffekt = 0.0
        SumGpuBruk = 0.0; SumMem = 0.0; SumSpredning = 0.0; N = 0
        StartTid = $null; SluttTid = $null
    }
    $BucketTabell[$Idx] = $ny
    return $ny
}

$bucketTabell = @{}

foreach ($linje in [System.IO.File]::ReadLines($CsvPath)) {
    $radNr++
    if ($radNr -eq 1) { continue }
    if ([string]::IsNullOrWhiteSpace($linje)) { continue }

    $felt = $linje.Split(',')
    if ($felt[0].Trim('"').TrimStart([char]0xFEFF) -eq 'Date') { continue }   # HWiNFO kan skrive ny header ved gjenopptatt logging

    $datoTekst = $felt[$idxDato].Trim('"')
    $tidTekst  = $felt[$idxTid].Trim('"')
    if ([string]::IsNullOrWhiteSpace($datoTekst) -or [string]::IsNullOrWhiteSpace($tidTekst)) { continue }

    try {
        $tidspunkt = ConvertTo-Tidspunkt -Dato $datoTekst -Tid $tidTekst
    } catch {
        continue
    }

    if (-not $startTid) { $startTid = $tidspunkt }
    $elapsed = ($tidspunkt - $startTid).TotalSeconds
    if ($elapsed -gt $maksSekunder) { break }

    if ($forrigeElapsed -ge 0) {
        $intervall = $elapsed - $forrigeElapsed
        if ($intervallSamples.Count -lt 200) { $intervallSamples.Add($intervall) }
        elseif ($intervall -gt ($medianIntervall * 15) -and $intervall -gt 5) {
            $hullFunnet.Add("Uventet pause i loggingen: {0:N1}s mellom {1:HH:mm:ss} og {2:HH:mm:ss} (kan indikere krasj/fryching/omstart)" -f $intervall, $sisteTid, $tidspunkt)
        }
        if ($intervallSamples.Count -eq 200) {
            $sortert = $intervallSamples | Sort-Object
            $medianIntervall = $sortert[100]
        }
    }
    $forrigeElapsed = $elapsed
    $sisteTid = $tidspunkt

    $bucketIdx = [int]([Math]::Floor($elapsed / (60 * $BucketMinutter)))
    $b = Hent-ElleTryggBucket -BucketTabell $bucketTabell -BucketListe $buckets -Idx $bucketIdx
    if (-not $b.StartTid) { $b.StartTid = $tidspunkt }
    $b.SluttTid = $tidspunkt
    $b.N++

    if ($idxKlokke -ge 0) { $b.SumKlokke += [double]::Parse($felt[$idxKlokke].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($idxTemp -ge 0) { $b.SumTemp += [double]::Parse($felt[$idxTemp].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($idxEffekt -ge 0) { $b.SumEffekt += [double]::Parse($felt[$idxEffekt].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($idxGpuTemp -ge 0) { $b.SumGpuTemp += [double]::Parse($felt[$idxGpuTemp].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($idxGpuEffekt -ge 0) { $b.SumGpuEffekt += [double]::Parse($felt[$idxGpuEffekt].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($idxGpuBruk -ge 0) { $b.SumGpuBruk += [double]::Parse($felt[$idxGpuBruk].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($idxMem -ge 0) { $b.SumMem += [double]::Parse($felt[$idxMem].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }

    if ($idxKjerner.Count -gt 1) {
        $verdier = foreach ($ik in $idxKjerner) { [double]::Parse($felt[$ik].Trim('"'), [System.Globalization.CultureInfo]::InvariantCulture) }
        $b.SumSpredning += (($verdier | Measure-Object -Maximum).Maximum - ($verdier | Measure-Object -Minimum).Minimum)
    }
}

foreach ($idx in ($bucketTabell.Keys | Sort-Object)) {
    $b = $bucketTabell[$idx]
    if ($b.N -eq 0) { continue }
    $buckets.Add([pscustomobject]@{
        Idx = $idx
        AvgKlokke = $b.SumKlokke / $b.N
        AvgTemp = $b.SumTemp / $b.N
        AvgEffekt = $b.SumEffekt / $b.N
        AvgGpuTemp = $b.SumGpuTemp / $b.N
        AvgGpuEffekt = $b.SumGpuEffekt / $b.N
        AvgGpuBruk = $b.SumGpuBruk / $b.N
        AvgMem = $b.SumMem / $b.N
        AvgSpredning = $b.SumSpredning / $b.N
        N = $b.N
        StartTid = $b.StartTid
        SluttTid = $b.SluttTid
    })
}

if ($buckets.Count -eq 0) { throw "Fant ingen brukbare datalinjer i loggen." }

# Faseskifte-deteksjon: sammenligner hver bucket mot snittet av inneverende fase sa langt,
# krever bekreftelse over 2 etterfolgende buckets for a unnga at enkelt-utslag splitter en fase
$faseGrenser = New-Object System.Collections.Generic.List[int]
$faseGrenser.Add(0)
for ($i = 1; $i -lt $buckets.Count; $i++) {
    $startIdx = $faseGrenser[$faseGrenser.Count - 1]
    $segment = $buckets.GetRange($startIdx, $i - $startIdx)
    $segKlokke = ($segment | Measure-Object -Property AvgKlokke -Average).Average
    $segEffekt = ($segment | Measure-Object -Property AvgEffekt -Average).Average
    if ($segKlokke -le 0 -or $segEffekt -le 0) { continue }

    $klokkeDiff = [Math]::Abs($buckets[$i].AvgKlokke - $segKlokke) / $segKlokke * 100
    $effektDiff = [Math]::Abs($buckets[$i].AvgEffekt - $segEffekt) / $segEffekt * 100

    if ($klokkeDiff -gt $TerskelKlokkeProsent -or $effektDiff -gt $TerskelEffektProsent) {
        if ($i + 1 -lt $buckets.Count) {
            $klokkeDiff2 = [Math]::Abs($buckets[$i + 1].AvgKlokke - $segKlokke) / $segKlokke * 100
            $effektDiff2 = [Math]::Abs($buckets[$i + 1].AvgEffekt - $segEffekt) / $segEffekt * 100
            if ($klokkeDiff2 -gt $TerskelKlokkeProsent -or $effektDiff2 -gt $TerskelEffektProsent) {
                $faseGrenser.Add($i)
            }
        } else {
            $faseGrenser.Add($i)
        }
    }
}
$faseGrenser.Add($buckets.Count)

# Slar sammen korte "faser" (under $MinFaseMinutter) med den NAERMESTE naboen (malt i
# klokke+effekt-avstand, ikke alltid foregaende) - en stoyete periode (f.eks. en ujevn
# kjernelast-fase) kan trigge mange smaa falske skifter pa rad uten at det er et ekte
# regimeskifte. Slar man alltid sammen bakover, "eter" en lang kjede av smaa stoy-utslag seg
# inn i den ekte fasen FORAN seg og videre fremover til slutten av loggen (sett under
# utvikling/test - se Utviklingslogg-UI-Stabilitet.md). Ved a sammenligne med BEGGE nabofasene
# og slaa sammen med den mest like, forblir en sammenhengende stoyete-men-egen fase samlet med
# seg selv i stedet for a smelte sammen med naboer som faktisk er ulike.
function Get-FaseSnitt {
    param($Buckets, [int]$StartIdx, [int]$SluttIdxEksklusiv)
    $segment = $Buckets.GetRange($StartIdx, $SluttIdxEksklusiv - $StartIdx)
    return @{
        Klokke = ($segment | Measure-Object -Property AvgKlokke -Average).Average
        Effekt = ($segment | Measure-Object -Property AvgEffekt -Average).Average
    }
}

$endretSammenslaaing = $true
while ($endretSammenslaaing -and $faseGrenser.Count -gt 2) {
    $endretSammenslaaing = $false
    for ($f = 0; $f -lt $faseGrenser.Count - 1; $f++) {
        $startIdx = $faseGrenser[$f]
        $sluttIdxEksklusiv = $faseGrenser[$f + 1]
        $varighetMin = ($buckets[$sluttIdxEksklusiv - 1].SluttTid - $buckets[$startIdx].StartTid).TotalMinutes
        if ($varighetMin -ge $MinFaseMinutter) { continue }

        $denne = Get-FaseSnitt -Buckets $buckets -StartIdx $startIdx -SluttIdxEksklusiv $sluttIdxEksklusiv
        $harForrige = $f -gt 0
        $harNeste = ($f + 2) -lt $faseGrenser.Count
        if (-not $harForrige -and -not $harNeste) { continue }

        $avstandForrige = [double]::MaxValue
        $avstandNeste = [double]::MaxValue

        if ($harForrige) {
            $forrige = Get-FaseSnitt -Buckets $buckets -StartIdx $faseGrenser[$f - 1] -SluttIdxEksklusiv $faseGrenser[$f]
            $avstandForrige = ([Math]::Abs($denne.Klokke - $forrige.Klokke) / $forrige.Klokke) + ([Math]::Abs($denne.Effekt - $forrige.Effekt) / $forrige.Effekt)
        }
        if ($harNeste) {
            $neste = Get-FaseSnitt -Buckets $buckets -StartIdx $faseGrenser[$f + 1] -SluttIdxEksklusiv $faseGrenser[$f + 2]
            $avstandNeste = ([Math]::Abs($denne.Klokke - $neste.Klokke) / $neste.Klokke) + ([Math]::Abs($denne.Effekt - $neste.Effekt) / $neste.Effekt)
        }

        if ($harNeste -and $avstandNeste -le $avstandForrige) {
            $faseGrenser.RemoveAt($f + 1)
        } else {
            $faseGrenser.RemoveAt($f)
        }
        $endretSammenslaaing = $true
        break
    }
}

$faser = New-Object System.Collections.Generic.List[object]
for ($f = 0; $f -lt $faseGrenser.Count - 1; $f++) {
    $startIdx = $faseGrenser[$f]
    $sluttIdxEksklusiv = $faseGrenser[$f + 1]
    $segment = $buckets.GetRange($startIdx, $sluttIdxEksklusiv - $startIdx)
    $totalN = ($segment | Measure-Object -Property N -Sum).Sum

    $faser.Add([pscustomobject]@{
        Start         = $segment[0].StartTid
        Slutt         = $segment[-1].SluttTid
        VarighetMin   = [Math]::Round(($segment[-1].SluttTid - $segment[0].StartTid).TotalMinutes, 1)
        AvgKlokke     = [Math]::Round((($segment | ForEach-Object { $_.AvgKlokke * $_.N }) | Measure-Object -Sum).Sum / $totalN, 1)
        AvgTemp       = [Math]::Round((($segment | ForEach-Object { $_.AvgTemp * $_.N }) | Measure-Object -Sum).Sum / $totalN, 1)
        AvgEffekt     = [Math]::Round((($segment | ForEach-Object { $_.AvgEffekt * $_.N }) | Measure-Object -Sum).Sum / $totalN, 1)
        AvgGpuBruk    = [Math]::Round((($segment | ForEach-Object { $_.AvgGpuBruk * $_.N }) | Measure-Object -Sum).Sum / $totalN, 1)
        AvgSpredning  = [Math]::Round((($segment | ForEach-Object { $_.AvgSpredning * $_.N }) | Measure-Object -Sum).Sum / $totalN, 1)
    })
}

$maxTemp = ($buckets | Measure-Object -Property AvgTemp -Maximum).Maximum
$maxEffekt = ($buckets | Measure-Object -Property AvgEffekt -Maximum).Maximum
$maxGpuBruk = ($buckets | Measure-Object -Property AvgGpuBruk -Maximum).Maximum
$totalVarighet = ($buckets[-1].SluttTid - $buckets[0].StartTid)

$ut = New-Object System.Collections.Generic.List[string]
$linjeskift = '=' * 78
$ut.Add($linjeskift)
$ut.Add("HWiNFO-loggsanalyse: $CsvPath")
$ut.Add($linjeskift)
$ut.Add('')
$ut.Add("Start: $($buckets[0].StartTid)")
$ut.Add("Slutt (innenfor analysert vindu): $($buckets[-1].SluttTid)")
$ut.Add("Total varighet analysert: {0:N1} timer" -f $totalVarighet.TotalHours)
$ut.Add("Hoyeste CPU-temp (minutt-snitt): {0:N1} grader" -f $maxTemp)
$ut.Add("Hoyeste CPU-effekt (minutt-snitt): {0:N1} W" -f $maxEffekt)
$ut.Add("Hoyeste GPU-bruk (minutt-snitt): {0:N1} %" -f $maxGpuBruk)
if ($maxGpuBruk -lt 15) {
    $ut.Add("  -> GPU-bruken holdt seg lav hele veien - dette ser ut til a vaere en rendyrket CPU-test, ikke en kombinert CPU+GPU-test.")
}
$ut.Add('')

if ($hullFunnet.Count -gt 0) {
    $ut.Add('ADVARSEL - uventede pauser funnet i loggingen:')
    foreach ($h in $hullFunnet) { $ut.Add("  - $h") }
    $ut.Add('')
}

if ($MaksTimer -gt 0 -and $totalVarighet.TotalHours -lt ($MaksTimer * 0.95)) {
    $ut.Add("ADVARSEL: du ba om analyse av de forste $MaksTimer timene, men loggen tar slutt etter kun {0:N2} timer." -f $totalVarighet.TotalHours)
    $ut.Add("  Dette kan bety at HWiNFO-loggingen stoppet for tiden (krasj/omstart/manuell stopp) - sjekk maskinen.")
    $ut.Add('')
}

$ut.Add("Fant $($faser.Count) distinkt(e) fase(r) (basert pa endring i kjerneklokke/effekt):")
$ut.Add('')
$faseNr = 1
foreach ($fase in $faser) {
    $ut.Add("Fase $faseNr`: $($fase.Start.ToString('HH:mm')) - $($fase.Slutt.ToString('HH:mm')) ($($fase.VarighetMin) min)")
    $ut.Add("  Kjerneklokke (avg): $($fase.AvgKlokke) MHz")
    $ut.Add("  CPU-effekt (avg): $($fase.AvgEffekt) W")
    $ut.Add("  CPU-temp (avg): $($fase.AvgTemp) grader")
    $ut.Add("  GPU-bruk (avg): $($fase.AvgGpuBruk) %")
    $ut.Add("  Kjerne-til-kjerne klokkespredning (avg): $($fase.AvgSpredning) MHz $(if ($fase.AvgSpredning -gt 200) { '<- ujevn kjernelast, mulig minne-/cache-orientert fase' })")
    $ut.Add('')
    $faseNr++
}

$ut | ForEach-Object { Write-Host $_ }

$rapportPath = [System.IO.Path]::ChangeExtension($CsvPath, $null).TrimEnd('.') + '-analyse.txt'
$ut | Set-Content -LiteralPath $rapportPath -Encoding UTF8
Write-Host "Rapport lagret til: $rapportPath"
