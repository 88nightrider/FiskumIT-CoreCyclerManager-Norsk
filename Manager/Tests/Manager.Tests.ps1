# Fiskum IT (v0.8.2): lett, isolert testsett for de mest rene/risikable logikkfunksjonene i
# Manager-scriptet. Bruker Pester 3.4.0 (bundlet med Windows PowerShell 5.1 - IKKE oppgradert,
# se begrunnelse i plan/README) sin eldre Describe/It/Should-syntaks.
#
# Funksjonene som testes hentes ut via AST fra selve Manager-scriptet (IKKE kopiert/duplisert
# her) og dot-sources isolert i en egen scriptblokk, med Get-CimInstance/Write-ManagerLog
# mocket/stubbet - samme teknikk som ble brukt manuelt for a verifisere Write-SluttRapport
# under utviklingen av disse funksjonene. Dette holder testene i sync med den faktiske koden
# uten a duplisere logikken, men dekker BEVISST kun rene, godt isolerte funksjoner
# (Get-PropertyNames, Get-UndervoltStotteInfo, Get-AnbefaltMargin, Test-NyVersjonTilgjengelig,
# Get-CompletedRoundCount) - ikke UI/motor-integrasjon.

$ManagerScript = Join-Path $PSScriptRoot '..\FiskumIT-CoreCyclerManager.ps1'

$funksjonsNavn = @('Get-PropertyNames', 'Get-UndervoltStotteInfo', 'Get-AnbefaltMargin', 'Test-NyVersjonTilgjengelig', 'Get-CompletedRoundCount', 'Get-YCruncherModusForCpu', 'Get-EndringsloggMellomVersjoner', 'Format-Varighet', 'Get-ConfigLineValue', 'Get-EstimertTestVarighetSekunder', 'Get-SokFremdriftTekst')

$ast = [System.Management.Automation.Language.Parser]::ParseFile($ManagerScript, [ref]$null, [ref]$null)
$funksjoner = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $funksjonsNavn -contains $node.Name
}, $true)

if (@($funksjoner).Count -ne $funksjonsNavn.Count) {
    throw "Fant ikke alle forventede funksjoner i $ManagerScript - forventet $($funksjonsNavn.Count), fant $(@($funksjoner).Count). Har funksjonsnavn endret seg?"
}

$uttrukketKode = ($funksjoner | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"

# Fiskum IT: stub - de uttrukne funksjonene logger via denne, men selve loggingen er
# irrelevant for testene (og har egne, reelle filsystem-avhengigheter vi ikke vil ha her)
function Write-ManagerLog {
    param([string]$Text)
}

# Fiskum IT: Test-NyVersjonTilgjengelig leser disse som script-scope variabler (definert i
# selve Manager-scriptet, ikke inni funksjonen) - ma finnes her ogsa for at funksjonen skal
# kunne kjores isolert
$GitHubRepo = 'test-eier/test-repo'
$ManagerVersion = '0.8.2'

$midlertidigFil = Join-Path ([System.IO.Path]::GetTempPath()) ("FiskumIT-ManagerTests-{0}.ps1" -f ([Guid]::NewGuid()))
Set-Content -LiteralPath $midlertidigFil -Value $uttrukketKode -Encoding UTF8

try {
    . $midlertidigFil
}
finally {
    Remove-Item -LiteralPath $midlertidigFil -Force -ErrorAction SilentlyContinue
}

Describe 'Get-PropertyNames' {
    It 'returnerer tom array for $null' {
        @(Get-PropertyNames -Object $null).Count | Should Be 0
    }

    It 'returnerer tom array for et objekt uten properties' {
        $tomt = [pscustomobject]@{}
        @(Get-PropertyNames -Object $tomt).Count | Should Be 0
    }

    It 'returnerer property-navnene for et normalt objekt' {
        $obj = [pscustomobject]@{ Foo = 1; Bar = 2 }
        $navn = @(Get-PropertyNames -Object $obj)
        $navn.Count | Should Be 2
        $navn -contains 'Foo' | Should Be $true
        $navn -contains 'Bar' | Should Be $true
    }
}

Describe 'Get-UndervoltStotteInfo' {
    BeforeEach {
        # Fiskum IT: funksjonen cacher resultatet i $Script:UndervoltStotteCache - ma
        # nullstilles mellom hver test, ellers gjenbruker test 2+ resultatet fra test 1
        $Script:UndervoltStotteCache = $null
    }

    It 'gjenkjenner AMD Ryzen 7000-serien (Zen 4, Family 25) som stottet med MinVerdi -50' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name         = 'AMD Ryzen 9 7950X3D 16-Core Processor'
                Manufacturer = 'AuthenticAMD'
                Description  = 'AMD64 Family 25 Model 97 Stepping 2'
                Caption      = 'AMD64 Family 25 Model 97 Stepping 2'
            }
        }

        $info = Get-UndervoltStotteInfo
        $info.Vendor          | Should Be 'AMD'
        $info.Stottet         | Should Be $true
        $info.MinVerdi        | Should Be -50
        $info.AmdModellNummer | Should Be 7950
    }

    It 'gjenkjenner AMD Ryzen 5000-serien (Zen 3, Family 25) som stottet med MinVerdi -30' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name         = 'AMD Ryzen 5 5600X 6-Core Processor'
                Manufacturer = 'AuthenticAMD'
                Description  = 'AMD64 Family 25 Model 33 Stepping 0'
                Caption      = 'AMD64 Family 25 Model 33 Stepping 0'
            }
        }

        $info = Get-UndervoltStotteInfo
        $info.Vendor   | Should Be 'AMD'
        $info.Stottet  | Should Be $true
        $info.MinVerdi | Should Be -30
    }

    It 'avviser en mobil Zen 2-rebrand markedsfort som "5000-serien" (Family 23, ikke 25+)' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name         = 'AMD Ryzen 5 5500U with Radeon Graphics'
                Manufacturer = 'AuthenticAMD'
                Description  = 'AMD64 Family 23 Model 104 Stepping 1'
                Caption      = 'AMD64 Family 23 Model 104 Stepping 1'
            }
        }

        $info = Get-UndervoltStotteInfo
        $info.Vendor  | Should Be 'AMD'
        $info.Stottet | Should Be $false
    }

    It 'gjenkjenner Intel 12. generasjon som stottet uten en kjent MinVerdi' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name         = 'Intel(R) Core(TM) i7-12700K'
                Manufacturer = 'GenuineIntel'
                Description  = 'Intel64 Family 6 Model 151 Stepping 2'
                Caption      = 'Intel64 Family 6 Model 151 Stepping 2'
            }
        }

        $info = Get-UndervoltStotteInfo
        $info.Vendor   | Should Be 'Intel'
        $info.Stottet  | Should Be $true
        $info.MinVerdi | Should Be $null
    }

    It 'markerer ukjent produsent som ikke stottet' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name         = 'Some Other CPU'
                Manufacturer = 'NotARealVendor'
                Description  = ''
                Caption      = ''
            }
        }

        $info = Get-UndervoltStotteInfo
        $info.Vendor  | Should Be 'Ukjent'
        $info.Stottet | Should Be $false
    }
}

Describe 'Get-AnbefaltMargin' {
    It 'gir margin 5 for AMD 5000/6000-serien (MinVerdi -30)' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; MinVerdi = -30 }
        (Get-AnbefaltMargin -Stotte $stotte).Margin | Should Be 5
    }

    It 'gir margin 7 for AMD 7000-serien og nyere (MinVerdi -50)' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; MinVerdi = -50 }
        (Get-AnbefaltMargin -Stotte $stotte).Margin | Should Be 7
    }

    It 'gir margin 10 for Intel' {
        $stotte = [pscustomobject]@{ Vendor = 'Intel'; MinVerdi = $null }
        (Get-AnbefaltMargin -Stotte $stotte).Margin | Should Be 10
    }

    It 'legger pa 2 ekstra nar soket gikk uvanlig raskt (under 8 min/kjerne)' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; MinVerdi = -30 }
        $anbefaling = Get-AnbefaltMargin -Stotte $stotte -GjennomsnittMinutterPerKjerne 3.0
        $anbefaling.Margin | Should Be 7
        $anbefaling.Forklaring | Should Match 'ekstra'
    }

    It 'legger IKKE pa ekstra margin nar soket gikk normalt (over 8 min/kjerne)' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; MinVerdi = -30 }
        (Get-AnbefaltMargin -Stotte $stotte -GjennomsnittMinutterPerKjerne 20.0).Margin | Should Be 5
    }

    It 'legger IKKE pa ekstra margin nar gjennomsnittet er ukjent (-1)' {
        $stotte = [pscustomobject]@{ Vendor = 'Intel'; MinVerdi = $null }
        (Get-AnbefaltMargin -Stotte $stotte -GjennomsnittMinutterPerKjerne -1).Margin | Should Be 10
    }
}

Describe 'Test-NyVersjonTilgjengelig' {
    It 'oppdager en nyere versjon pa GitHub' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                tag_name = 'v0.9.0'
                html_url = 'https://github.com/test-eier/test-repo/releases/tag/v0.9.0'
            }
        }

        $resultat = Test-NyVersjonTilgjengelig
        $resultat.Forsokt               | Should Be $true
        $resultat.NyVersjonTilgjengelig | Should Be $true
        $resultat.SisteVersjon          | Should Be '0.9.0'
        $resultat.Url                   | Should Be 'https://github.com/test-eier/test-repo/releases/tag/v0.9.0'
    }

    It 'rapporterer ingen ny versjon nar GitHub allerede har samme tag som ManagerVersion' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                tag_name = 'v0.8.2'
                html_url = 'https://github.com/test-eier/test-repo/releases/tag/v0.8.2'
            }
        }

        $resultat = Test-NyVersjonTilgjengelig
        $resultat.Forsokt               | Should Be $true
        $resultat.NyVersjonTilgjengelig | Should Be $false
    }

    It 'feiler stille (Forsokt=$false) ved en nettverksfeil, uten a kaste videre' {
        Mock Invoke-RestMethod {
            throw 'Simulert nettverksfeil'
        }

        $resultat = Test-NyVersjonTilgjengelig
        $resultat.Forsokt               | Should Be $false
        $resultat.NyVersjonTilgjengelig | Should Be $null
        $resultat.Feilmelding           | Should Match 'Simulert nettverksfeil'
    }
}

Describe 'Get-CompletedRoundCount' {
    # Fiskum IT: regresjonstest for buggen sett pa WANJA-GAMER 2026-06-23 (v0.8.2) -
    # "7/5 (100%)" under en kuratert standardtest-kjoring, fordi den rA test-ID-en fra
    # testplan.json (ikke sammenhengende i et filtrert delsett) ble brukt direkte som
    # "antall fullforte" i stedet for en posisjon i $Plan
    $plan = @(
        [pscustomobject]@{ id = 3 },
        [pscustomobject]@{ id = 7 },
        [pscustomobject]@{ id = 10 },
        [pscustomobject]@{ id = 11 },
        [pscustomobject]@{ id = 14 }
    )

    It 'returnerer 0 nar ingen tester er fullfort enda' {
        $state = [pscustomobject]@{ status = 'Klar'; sisteFullforteTestId = 0 }
        Get-CompletedRoundCount -Plan $plan -State $state | Should Be 0
    }

    It 'teller POSISJONEN i $Plan, ikke selve test-ID-en, for et filtrert delsett' {
        $state = [pscustomobject]@{ status = 'KjÃ¸rer'; sisteFullforteTestId = 7 }
        Get-CompletedRoundCount -Plan $plan -State $state | Should Be 2
    }

    It 'returnerer Plan.Count nar status er Fullfort, uavhengig av siste ID' {
        $state = [pscustomobject]@{ status = 'FullfÃ¸rt'; sisteFullforteTestId = 14 }
        Get-CompletedRoundCount -Plan $plan -State $state | Should Be 5
    }
}

Describe 'Get-YCruncherModusForCpu' {
    # Fiskum IT (v0.8.7.2): regresjonstest for y-cruncher sin "auto"-modus-deteksjon, som
    # har vist seg aa feile DETERMINISTISK pa minst en reell maskin (TEST-01, se Feil-mappens
    # diagnostikk 2026-06-26) - Activate-TestConfig overstyrer na alltid "auto" med en av
    # disse eksplisitte, dokumenterte modusstrengene i stedet
    It 'returnerer Intel AVX512-modus for en Intel-CPU med AVX512' {
        $stotte = [pscustomobject]@{ Vendor = 'Intel' }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $true; AVX512 = $true }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '18-CNL ~ Shinoa'
    }

    It 'returnerer Intel AVX2-modus for en Intel-CPU uten AVX512' {
        $stotte = [pscustomobject]@{ Vendor = 'Intel' }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $true; AVX512 = $false }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '13-HSW ~ Airi'
    }

    It 'returnerer Intel AVX-modus for en Intel-CPU uten AVX2' {
        $stotte = [pscustomobject]@{ Vendor = 'Intel' }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $false; AVX512 = $false }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '11-SNB ~ Hina'
    }

    It 'returnerer Intel SSE-modus for en svaert gammel Intel-CPU uten AVX' {
        $stotte = [pscustomobject]@{ Vendor = 'Intel' }
        $caps = [pscustomobject]@{ AVX = $false; AVX2 = $false; AVX512 = $false }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '04-P4P'
    }

    It 'returnerer Zen5-modus for AMD AVX512 med modellnummer >= 9000' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; AmdModellNummer = 9950 }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $true; AVX512 = $true }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '24-ZN5 ~ Komari'
    }

    It 'returnerer Zen4-modus for AMD AVX512 med modellnummer >= 7000 og < 9000' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; AmdModellNummer = 7950 }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $true; AVX512 = $true }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '22-ZN4 ~ Kizuna'
    }

    It 'returnerer Zen2/3-modus for AMD AVX512 med ukjent modellnummer (f.eks. Threadripper)' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; AmdModellNummer = $null }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $true; AVX512 = $true }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '19-ZN2 ~ Kagari'
    }

    It 'returnerer Zen2/3-modus for AMD AVX2 uten AVX512' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; AmdModellNummer = 5700 }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $true; AVX512 = $false }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '19-ZN2 ~ Kagari'
    }

    It 'returnerer AMD AVX-modus (Piledriver) for AMD med AVX men uten AVX2' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; AmdModellNummer = $null }
        $caps = [pscustomobject]@{ AVX = $true; AVX2 = $false; AVX512 = $false }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '12-BD2 ~ Miyu'
    }

    It 'returnerer AMD SSE-modus (Athlon 64) for en svaert gammel AMD-CPU uten AVX' {
        $stotte = [pscustomobject]@{ Vendor = 'AMD'; AmdModellNummer = $null }
        $caps = [pscustomobject]@{ AVX = $false; AVX2 = $false; AVX512 = $false }
        Get-YCruncherModusForCpu -UndervoltStotteInfo $stotte -CpuInstruksjonssett $caps | Should Be '05-A64 ~ Kasumi'
    }
}

Describe 'Get-EndringsloggMellomVersjoner' {
    # Fiskum IT (v0.8.7.3): bruker en SYNTETISK README-tekst (ikke den faktiske README.txt)
    # sa testen ikke knekker hver gang changelogen oppdateres - kun selve parse-logikken
    # testes her
    $syntetiskReadme = @'
Fiskum IT CoreCycler Manager v0.8.7.2
============================================================

Nyheter i v0.8.7.2
-------------------
- Tredje endring

Nyheter i v0.8.7.1
-------------------
- Andre endring

Nyheter i v0.8.7
----------------
- Forste endring

Nyheter i v0.8.6
----------------
- En enda eldre endring
'@

    It 'returnerer kun seksjoner NYERE enn FraVersjon og OPPTIL OG MED TilVersjon' {
        $resultat = Get-EndringsloggMellomVersjoner -ReadmeInnhold $syntetiskReadme -FraVersjon '0.8.7' -TilVersjon '0.8.7.2'
        $resultat | Should Match 'Tredje endring'
        $resultat | Should Match 'Andre endring'
        $resultat | Should Not Match 'Forste endring'
        $resultat | Should Not Match 'en enda eldre endring'
    }

    It 'returnerer alle seksjoner nyere enn en svaert gammel FraVersjon' {
        $resultat = Get-EndringsloggMellomVersjoner -ReadmeInnhold $syntetiskReadme -FraVersjon '0.8.5' -TilVersjon '0.8.7.2'
        $resultat | Should Match 'Tredje endring'
        $resultat | Should Match 'Andre endring'
        $resultat | Should Match 'Forste endring'
        $resultat | Should Match 'En enda eldre endring'
    }

    It 'returnerer en fallback-tekst nar ingen seksjoner matcher' {
        $resultat = Get-EndringsloggMellomVersjoner -ReadmeInnhold $syntetiskReadme -FraVersjon '0.8.7.2' -TilVersjon '0.8.7.2'
        $resultat | Should Be 'Fant ingen detaljert endringslogg for denne oppdateringen.'
    }
}

Describe 'Format-Varighet' {
    It 'returnerer "<1 min" for under ett minutt' {
        Format-Varighet -Sekunder 30 | Should Be '<1 min'
    }

    It 'returnerer kun minutter under en time' {
        Format-Varighet -Sekunder 1500 | Should Be '25 min'
    }

    It 'returnerer timer og minutter over en time' {
        Format-Varighet -Sekunder 9000 | Should Be '2t 30min'
    }

    It 'haandterer negative verdier som 0' {
        Format-Varighet -Sekunder -100 | Should Be '<1 min'
    }
}

Describe 'Get-EstimertTestVarighetSekunder' {
    $midlertidigIniMappe = Join-Path ([System.IO.Path]::GetTempPath()) ("FiskumIT-ManagerTests-Ini-{0}" -f ([Guid]::NewGuid()))
    New-Item -ItemType Directory -Path $midlertidigIniMappe -Force | Out-Null

    It 'parser "5m" som 300 sekunder' {
        $iniPath = Join-Path $midlertidigIniMappe 'fastimer.ini'
        Set-Content -LiteralPath $iniPath -Value @('[General]', 'runtimePerCore = 5m') -Encoding UTF8
        Get-EstimertTestVarighetSekunder -ConfigPath $iniPath | Should Be 300
    }

    It 'parser et rent sekundtall' {
        $iniPath = Join-Path $midlertidigIniMappe 'sekunder.ini'
        Set-Content -LiteralPath $iniPath -Value @('[General]', 'runtimePerCore = 45') -Encoding UTF8
        Get-EstimertTestVarighetSekunder -ConfigPath $iniPath | Should Be 45
    }

    It 'parser "1h30m" som timer+minutter' {
        $iniPath = Join-Path $midlertidigIniMappe 'timer.ini'
        Set-Content -LiteralPath $iniPath -Value @('[General]', 'runtimePerCore = 1h30m') -Encoding UTF8
        Get-EstimertTestVarighetSekunder -ConfigPath $iniPath | Should Be 5400
    }

    It 'beregner "auto" for yCruncher fra tests+testDuration (samme formel som motoren)' {
        $iniPath = Join-Path $midlertidigIniMappe 'auto.ini'
        Set-Content -LiteralPath $iniPath -Value @(
            '[General]',
            'runtimePerCore = auto',
            'suspendPeriodically = 1',
            '[yCruncher]',
            'tests = SFTv4, FFTv4, N63',
            'testDuration = 20',
            '[Debug]',
            'tickInterval = 10',
            'suspensionTime = 1000'
        ) -Encoding UTF8

        # oneRunLength = 3*20 = 60. suspendedTime = 1*60/10*(1000/1000) = 6. bufferTime = 60*0.05 = 3. Total = 69
        Get-EstimertTestVarighetSekunder -ConfigPath $iniPath | Should Be 69
    }

    It 'returnerer $null nar runtimePerCore mangler' {
        $iniPath = Join-Path $midlertidigIniMappe 'tom.ini'
        Set-Content -LiteralPath $iniPath -Value @('[General]', 'stressTestProgram = PRIME95') -Encoding UTF8
        Get-EstimertTestVarighetSekunder -ConfigPath $iniPath | Should Be $null
    }

    Remove-Item -LiteralPath $midlertidigIniMappe -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SokFremdriftTekst' {
    $na = [DateTime]::Parse('2026-06-26T12:00:00Z', $null, [System.Globalization.DateTimeStyles]::RoundtripKind)

    It 'viser "ikke startet" nar assistertSokStartTid er tom' {
        $state = [pscustomobject]@{ assistertSokStartTid = ''; laasteKjerner = [pscustomobject]@{} }
        $stotte = [pscustomobject]@{ Vendor = 'AMD' }
        Get-SokFremdriftTekst -State $state -Stotte $stotte -AntallKjerner 8 -Na $na | Should Be 'Forløpt tid: ikke startet ennå'
    }

    It 'viser kun forlopt tid for Intel (ingen "neste kjerne")' {
        $state = [pscustomobject]@{ assistertSokStartTid = '2026-06-26T11:30:00Z'; laasteKjerner = [pscustomobject]@{} }
        $stotte = [pscustomobject]@{ Vendor = 'Intel' }
        $resultat = Get-SokFremdriftTekst -State $state -Stotte $stotte -AntallKjerner 8 -Na $na
        $resultat | Should Match '^Forløpt tid: 30 min'
        $resultat | Should Match 'estimat ikke mulig'
    }

    It 'viser "estimat kommer etter forste laste kjerne" for AMD uten laste kjerner enda' {
        $state = [pscustomobject]@{ assistertSokStartTid = '2026-06-26T11:50:00Z'; laasteKjerner = [pscustomobject]@{} }
        $stotte = [pscustomobject]@{ Vendor = 'AMD' }
        $resultat = Get-SokFremdriftTekst -State $state -Stotte $stotte -AntallKjerner 8 -Na $na
        $resultat | Should Match 'estimat kommer etter'
    }

    It 'beregner snitt-basert anslag for AMD med noen laste kjerner' {
        # 40 minutter forlopt, 2 kjerner last -> snitt 20 min/kjerne, 6 gjenstaende -> 120 min estimert
        $state = [pscustomobject]@{
            assistertSokStartTid = '2026-06-26T11:20:00Z'
            laasteKjerner = [pscustomobject]@{ '0' = -8; '1' = -6 }
        }
        $stotte = [pscustomobject]@{ Vendor = 'AMD' }
        $resultat = Get-SokFremdriftTekst -State $state -Stotte $stotte -AntallKjerner 8 -Na $na
        $resultat | Should Match '2/8 kjerner låst'
        $resultat | Should Match '2t 0min'
    }

    It 'viser "alle kjerner last" nar antallLaaste >= AntallKjerner' {
        $state = [pscustomobject]@{
            assistertSokStartTid = '2026-06-26T11:00:00Z'
            laasteKjerner = [pscustomobject]@{ '0' = -8; '1' = -6 }
        }
        $stotte = [pscustomobject]@{ Vendor = 'AMD' }
        $resultat = Get-SokFremdriftTekst -State $state -Stotte $stotte -AntallKjerner 2 -Na $na
        $resultat | Should Match 'alle kjerner låst'
    }
}
