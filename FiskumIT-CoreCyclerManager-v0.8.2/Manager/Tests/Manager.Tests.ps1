# Fiskum IT (v0.8.2): lett, isolert testsett for de mest rene/risikable logikkfunksjonene i
# Manager-scriptet. Bruker Pester 3.4.0 (bundlet med Windows PowerShell 5.1 - IKKE oppgradert,
# se begrunnelse i plan/README) sin eldre Describe/It/Should-syntaks.
#
# Funksjonene som testes hentes ut via AST fra selve Manager-scriptet (IKKE kopiert/duplisert
# her) og dot-sources isolert i en egen scriptblokk, med Get-CimInstance/Write-ManagerLog
# mocket/stubbet - samme teknikk som ble brukt manuelt for a verifisere Write-SluttRapport
# under utviklingen av disse funksjonene. Dette holder testene i sync med den faktiske koden
# uten a duplisere logikken, men dekker BEVISST kun rene, godt isolerte funksjoner
# (Get-PropertyNames, Get-UndervoltStotteInfo, Get-AnbefaltMargin) - ikke UI/motor-integrasjon.

$ManagerScript = Join-Path $PSScriptRoot '..\FiskumIT-CoreCyclerManager-v0.8.2.ps1'

$funksjonsNavn = @('Get-PropertyNames', 'Get-UndervoltStotteInfo', 'Get-AnbefaltMargin')

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
